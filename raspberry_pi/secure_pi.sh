#!/bin/bash
#
# Prepare Raspberry Pi OS Lite (64-bit) or Ubuntu on ARM for k3s.
# Run once per node as root (local console or existing SSH), BEFORE rpi_container_toolkit.sh.
#

set -o pipefail

ADMIN_USER="${ADMIN_USER:-}"
CREATE_NODE_USER="${CREATE_NODE_USER:-false}"
SKIP_REBOOT="${SKIP_REBOOT:-false}"

function run_as_root() {
    if [[ $(id -u) != 0 ]]; then
        echo '[*] Must be run as root: sudo bash secure_pi.sh --pi-os'
        exit 1
    fi
}

function _help_menu() {
    echo '[*] Help Menu — secure_pi.sh'
    echo ''
    echo '[*] --pi-os        Raspberry Pi OS Lite 64-bit (recommended).'
    echo '                 sudo bash secure_pi.sh --pi-os'
    echo ''
    echo '[*] --raspbian     Alias for --pi-os.'
    echo ''
    echo '[*] --ubuntu       Ubuntu Server for Raspberry Pi (ARM64).'
    echo '                 sudo bash secure_pi.sh --ubuntu'
    echo ''
    echo 'Options (environment):'
    echo '  ADMIN_USER=<name>       Login account (default: user who ran sudo).'
    echo '  CREATE_NODE_USER=true   Also create a "node" user with SSH keys.'
    echo '  SKIP_REBOOT=true        Do not reboot at the end.'
    echo ''
    echo 'Prepares: hostname, OpenSSH (enabled on boot), SSH keys, swap off,'
    echo '          cgroup boot params, USB max current.'
    echo ''
    echo 'Server SSH config: /etc/ssh/sshd_config.d/99-secure-pi.conf'
    echo '(not ssh_config.d — that is for the client only)'
    echo ''
    echo 'Run on each Pi before: sudo bash rpi_container_toolkit.sh --master-k3s'
    exit 0
}

function detect_admin_user() {
    if [[ -n "${ADMIN_USER}" ]]; then
        if ! id "${ADMIN_USER}" &>/dev/null; then
            echo "[*] Error: ADMIN_USER=${ADMIN_USER} does not exist."
            exit 1
        fi
        return
    fi

    if [[ -n "${SUDO_USER:-}" ]] && id "${SUDO_USER}" &>/dev/null; then
        ADMIN_USER="${SUDO_USER}"
    else
        ADMIN_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}' /etc/passwd)
    fi

    if [[ -z "${ADMIN_USER}" ]]; then
        echo '[*] Error: could not detect admin user. Set ADMIN_USER=myuser'
        exit 1
    fi
    echo "[*] Admin user: ${ADMIN_USER}"
}

function update_apt() {
    echo '[*] Updating packages.'
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    apt-get autoremove -y
    apt-get autoclean -y
}

function systemd_unit_is_linked_alias() {
    local unit="$1" p
    for p in "/etc/systemd/system/${unit}" "/lib/systemd/system/${unit}" "/usr/lib/systemd/system/${unit}"; do
        [[ -L "${p}" ]] && return 0
    done
    return 1
}

function ssh_is_running() {
    systemctl is-active --quiet ssh 2>/dev/null && return 0
    systemctl is-active --quiet ssh.socket 2>/dev/null && return 0
    ss -tln 2>/dev/null | grep -q ':22 ' && return 0
    return 1
}

function ensure_sshd_runtime_dir() {
    # sshd -t and the daemon require /run/sshd (often missing until first successful start).
    if [[ -d /run/sshd ]]; then
        return 0
    fi
    echo '[*] Creating /run/sshd (privilege separation directory).'
    mkdir -p /run/sshd
    chmod 755 /run/sshd
    if command -v systemd-tmpfiles &>/dev/null; then
        systemd-tmpfiles --create /usr/lib/tmpfiles.d/sshd.conf 2>/dev/null \
            || systemd-tmpfiles --create /etc/tmpfiles.d/sshd.conf 2>/dev/null \
            || true
    fi
}

function install_ssh_server() {
    echo '[*] Installing OpenSSH server.'
    apt-get install -y openssh-server
    ensure_sshd_runtime_dir
    systemctl unmask ssh.service 2>/dev/null || true
    systemctl disable ssh.socket 2>/dev/null || true
    systemctl enable ssh.service
    systemctl start ssh.service 2>/dev/null || systemctl start ssh.socket 2>/dev/null || true
    if ! ssh_is_running; then
        echo '[*] Error: SSH is not listening on port 22.'
        echo '    Check: systemctl status ssh.service --no-pager'
        exit 1
    fi
    echo '[*] OpenSSH server is running.'
}

function validate_sshd_config() {
    ensure_sshd_runtime_dir
    if sshd -t 2>/tmp/sshd-test.err; then
        return 0
    fi
    echo '[*] Error: sshd config is invalid. Fix before starting SSH:'
    cat /tmp/sshd-test.err
    return 1
}

# Raspberry Pi OS: use ssh.service on boot, not ssh.socket (fewer failures).
function enable_ssh_on_boot() {
    echo '[*] Enabling SSH via ssh.service (disabling ssh.socket on Pi OS).'
    ensure_sshd_runtime_dir

    if ! validate_sshd_config; then
        echo '    Fix /etc/ssh/sshd_config.d/99-secure-pi.conf then run:'
        echo '      sudo sshd -t && sudo systemctl restart ssh.service'
        return 1
    fi

    systemctl unmask ssh.service 2>/dev/null || true
    systemctl stop ssh.socket 2>/dev/null || true
    systemctl disable ssh.socket 2>/dev/null || true

    systemctl enable ssh.service && echo '[*] Enabled ssh.service'
    systemctl restart ssh.service 2>/dev/null || systemctl start ssh.service

    if ssh_is_running; then
        echo '[*] SSH listening on port 22 (ssh.service).'
        return 0
    fi

    echo '[*] Error: ssh.service did not start. Run:'
    echo '      journalctl -u ssh.service -n 30 --no-pager'
    return 1
}

function ensure_sshd_reads_dropins() {
    local main_cfg=/etc/ssh/sshd_config
    if [[ ! -f "${main_cfg}" ]]; then
        echo '[*] Error: /etc/ssh/sshd_config not found.'
        exit 1
    fi
    if grep -qE 'Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "${main_cfg}"; then
        echo '[*] sshd_config already includes sshd_config.d/*.conf'
        return 0
    fi
    echo '[*] Adding Include for /etc/ssh/sshd_config.d/*.conf to sshd_config.'
    mkdir -p /etc/ssh/sshd_config.d
    printf '\n# Added by secure_pi.sh\nInclude /etc/ssh/sshd_config.d/*.conf\n' >> "${main_cfg}"
}

function comment_main_sshd_conflicts() {
    local main_cfg=/etc/ssh/sshd_config key
    [[ -f "${main_cfg}" ]] || return 0
    for key in PasswordAuthentication PermitRootLogin AllowUsers KbdInteractiveAuthentication; do
        if grep -qE "^[[:space:]]*${key}[[:space:]]" "${main_cfg}" 2>/dev/null; then
            sed -i "s/^[[:space:]]*${key}[[:space:]]/# &/" "${main_cfg}"
        fi
    done
}

function backup_other_sshd_dropins() {
    local f
    for f in /etc/ssh/sshd_config.d/*.conf; do
        [[ -f "${f}" ]] || continue
        [[ "${f}" == */99-secure-pi.conf ]] && continue
        if [[ ! -f "${f}.bak-secure-pi" ]]; then
            mv "${f}" "${f}.bak-secure-pi"
            echo "[*] Disabled $(basename "${f}") — using 99-secure-pi.conf instead."
        fi
    done
}

function skip_if_keys_exist() {
    if ssh_user_has_keys "${ADMIN_USER}" 2>/dev/null; then
        echo "[*] ${ADMIN_USER} already has SSH key(s) — will not prompt for password change unless you want to."
        echo '[*] Skipping password prompt (keys present). Set FORCE_PASSWORD_PROMPT=true to force.'
        [[ "${FORCE_PASSWORD_PROMPT:-false}" == "true" ]] || return 0
    fi
    return 1
}

function fix_home_permissions_for_ssh() {
    local user="$1" home_dir
    home_dir=$(eval echo "~${user}")
    # sshd rejects keys if home or .ssh is group/world writable.
    chmod go-w "${home_dir}" 2>/dev/null || true
    ensure_ssh_dir_permissions "${user}"
}

function ask_for_hostname() {
    local current
    current=$(hostnamectl --static 2>/dev/null || hostname -s)
    echo "[*] Current hostname: ${current}"
    read -r -p '[*] New hostname (required for cluster nodes, e.g. pi-master): ' user_requested_hostname
    while [[ -z "${user_requested_hostname}" ]]; do
        read -r -p '[*] Hostname cannot be empty. Enter hostname: ' user_requested_hostname
    done
    hostnamectl set-hostname "${user_requested_hostname}"
    echo "[*] Hostname set to ${user_requested_hostname}"
}

function update_etc_hosts() {
    local ip hostname_short
    hostname_short=$(hostnamectl --static 2>/dev/null || hostname -s)
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -z "${ip}" ]]; then
        ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    fi
    sed -i '/raspberrypi/d' /etc/hosts
    if [[ -n "${ip}" && -n "${hostname_short}" ]]; then
        if ! grep -qE "[[:space:]]${hostname_short}([[:space:]]|$)" /etc/hosts; then
            echo "${ip} ${hostname_short}" >> /etc/hosts
        fi
        echo "[*] /etc/hosts: ${ip} ${hostname_short}"
    else
        echo '[*] Warning: could not update /etc/hosts with IP (no network yet?).'
    fi
}

function handle_legacy_pi_user() {
    if id pi &>/dev/null; then
        echo '[*] Found legacy "pi" user — locking account and denying SSH.'
        passwd -l pi 2>/dev/null || true
        SSH_DENY_USERS+=("pi")
    else
        echo '[*] No "pi" user on this system (normal for current Pi OS Lite images).'
    fi
}

function disable_swap() {
    echo '[*] Disabling swap (required for Kubernetes).'
    swapoff -a 2>/dev/null || true
    sed -i.bak-secure-pi '/[[:space:]]swap[[:space:]]/s/^\([^#]\)/#\1/' /etc/fstab
    if [[ -f /etc/dphys-swapfile ]]; then
        systemctl disable dphys-swapfile 2>/dev/null || true
        systemctl stop dphys-swapfile 2>/dev/null || true
    fi
    echo '[*] Swap disabled.'
}

function ensure_cgroup_memory() {
    local cmdline_files=("/boot/firmware/cmdline.txt" "/boot/cmdline.txt")
    local cgroup_opts='cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory'
    local f changed=0 found=0

    for f in "${cmdline_files[@]}"; do
        [[ -f "${f}" ]] || continue
        found=1
        if grep -q 'cgroup_enable=memory' "${f}"; then
            echo "[*] cgroup memory already enabled in ${f}"
        else
            sed -i "s/$/ ${cgroup_opts}/" "${f}"
            echo "[*] Added cgroup options to ${f}"
            changed=1
        fi
    done

    if [[ ${found} -eq 0 ]]; then
        echo '[*] Warning: cmdline.txt not found — add cgroup params manually for k3s.'
        return
    fi

    if [[ ${changed} -eq 1 ]]; then
        echo '[*] cgroup boot parameters changed — reboot required before k3s install.'
        NEEDS_REBOOT=true
    fi
}

function enable_usb_max_current() {
    local config_files=("/boot/firmware/config.txt" "/boot/config.txt")
    local f found=0

    for f in "${config_files[@]}"; do
        [[ -f "${f}" ]] || continue
        found=1
        if grep -qE '^[[:space:]]*usb_max_current_enable=1' "${f}"; then
            echo "[*] usb_max_current_enable=1 already present in ${f}"
        else
            echo 'usb_max_current_enable=1' >> "${f}"
            echo "[*] Added usb_max_current_enable=1 to ${f}"
            NEEDS_REBOOT=true
        fi
    done

    if [[ ${found} -eq 0 ]]; then
        echo '[*] Warning: config.txt not found — skip USB max current setting.'
    fi
}

function enable_ip_forwarding() {
    tee /etc/sysctl.d/99-kubernetes.conf >/dev/null <<EOF
net.ipv4.ip_forward = 1
EOF
    sysctl --system >/dev/null
    echo '[*] IPv4 forwarding enabled.'
}

function set_keyboard_english() {
    if [[ -f /etc/default/keyboard ]]; then
        sed -i 's/gb/us/g; s/GB/us/g' /etc/default/keyboard 2>/dev/null || true
    fi
}

function prompt_admin_password() {
    if skip_if_keys_exist; then
        return 0
    fi
    echo "[*] Set a login password for ${ADMIN_USER}."
    passwd "${ADMIN_USER}"
}

function create_node_user_if_requested() {
    [[ "${CREATE_NODE_USER}" == "true" ]] || return 0
    if id node &>/dev/null; then
        echo '[*] User "node" already exists.'
    else
        echo '[*] Creating user "node".'
        useradd -m -s /bin/bash -U node
        passwd node
        usermod -aG adm,dialout,cdrom,sudo,audio,video,plugdev,users,input,netdev,gpio,i2c,spi node 2>/dev/null \
            || usermod -aG adm,dialout,cdrom,sudo,audio,video,plugdev,users,netdev node
    fi
    SSH_ALLOW_USERS+=("node")
}

function ssh_user_has_keys() {
    local user="$1"
    local auth_keys
    auth_keys=$(eval echo "~${user}")/.ssh/authorized_keys
    [[ -s "${auth_keys}" ]] || return 1
    grep -qE '^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp256) ' "${auth_keys}" 2>/dev/null
}

function ensure_ssh_dir_permissions() {
    local user="$1"
    local home_dir ssh_dir
    home_dir=$(eval echo "~${user}")
    ssh_dir="${home_dir}/.ssh"
    mkdir -p "${ssh_dir}"
    touch "${ssh_dir}/authorized_keys"
    chmod 700 "${ssh_dir}"
    chmod 600 "${ssh_dir}/authorized_keys"
    chown -R "${user}:${user}" "${ssh_dir}"
}

function add_ssh_pubkey() {
    local user="$1"
    ensure_ssh_dir_permissions "${user}"

    if ssh_user_has_keys "${user}"; then
        local count
        count=$(grep -cE '^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp256) ' "$(eval echo "~${user}")/.ssh/authorized_keys" 2>/dev/null || echo 0)
        echo "[*] SSH key(s) already present for '${user}' (${count}) — skipping prompt."
        fix_home_permissions_for_ssh "${user}"
        return 0
    fi

    echo "[*] No SSH public key found for '${user}'."
    echo '[*] Paste your public key (one line, starts with ssh-ed25519 or ssh-rsa), then Enter:'
    read -r key_line
    if [[ -n "${key_line}" ]]; then
        if ! grep -qF "${key_line}" "$(eval echo "~${user}")/.ssh/authorized_keys" 2>/dev/null; then
            echo "${key_line}" >> "$(eval echo "~${user}")/.ssh/authorized_keys"
        fi
        ensure_ssh_dir_permissions "${user}"
        fix_home_permissions_for_ssh "${user}"
        echo "[*] SSH key saved for '${user}'."
    else
        echo "[*] Error: no key provided for '${user}'."
        return 1
    fi
}

function setup_ssh_keys() {
    SSH_ALLOW_USERS=("${ADMIN_USER}")
    create_node_user_if_requested
    add_ssh_pubkey "${ADMIN_USER}" || exit 1
    if id node &>/dev/null; then
        add_ssh_pubkey node || exit 1
    fi
}

function verify_admin_ssh_key() {
    if ssh_user_has_keys "${ADMIN_USER}"; then
        return 0
    fi
    echo "[*] Error: ${ADMIN_USER} has no SSH public key in ~/.ssh/authorized_keys."
    exit 1
}

function require_sudo_password() {
    echo '[*] Requiring a password for sudo (removing NOPASSWD rules).'
    local f
    for f in /etc/sudoers.d/*; do
        [[ -f "${f}" ]] || continue
        sed -i 's/NOPASSWD: ALL/PASSWD: ALL/g; s/NOPASSWD:ALL/PASSWD:ALL/g' "${f}"
    done
    if ! grep -rq "^${ADMIN_USER} " /etc/sudoers.d/ 2>/dev/null \
        && ! grep -q "^${ADMIN_USER} " /etc/sudoers 2>/dev/null; then
        echo "${ADMIN_USER} ALL=(ALL) PASSWD:ALL" > "/etc/sudoers.d/090-${ADMIN_USER}"
        chmod 440 "/etc/sudoers.d/090-${ADMIN_USER}"
    fi
}

function user_is_ssh_allowed() {
    local user="$1" allowed
    for allowed in "${SSH_ALLOW_USERS[@]}"; do
        [[ "${allowed}" == "${user}" ]] && return 0
    done
    return 1
}

function append_deny_users_to_sshd_config() {
    local deny_list=() u
    for u in "${SSH_DENY_USERS[@]}"; do
        user_is_ssh_allowed "${u}" && continue
        deny_list+=("${u}")
    done
    # Only deny ubuntu when it is a leftover cloud image account, not our admin user.
    if id ubuntu &>/dev/null && ! user_is_ssh_allowed ubuntu; then
        deny_list+=("ubuntu")
    fi
    if [[ ${#deny_list[@]} -gt 0 ]]; then
        echo "DenyUsers $(IFS=,; echo "${deny_list[*]}")" >> /etc/ssh/sshd_config.d/99-secure-pi.conf
    fi
}

function write_ssh_banner() {
    cat >/etc/issue.net <<'EOF'

  #####################################################################
  #  Unauthorized access to this system is prohibited.                #
  #####################################################################

EOF
}

function configure_sshd() {
    write_ssh_banner
    handle_legacy_pi_user

    ensure_sshd_reads_dropins
    comment_main_sshd_conflicts
    backup_other_sshd_dropins

    local allow_users_line=""
    if [[ ${#SSH_ALLOW_USERS[@]} -gt 0 ]]; then
        allow_users_line="AllowUsers $(IFS=,; echo "${SSH_ALLOW_USERS[*]}")"
    fi

    mkdir -p /etc/ssh/sshd_config.d
    # NOTE: Server settings go in sshd_config.d — NOT ssh_config.d (client only).
    cat >/etc/ssh/sshd_config.d/99-secure-pi.conf <<EOF
# Managed by secure_pi.sh — sshd (server) configuration
PermitRootLogin no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
UsePAM yes
X11Forwarding no
Banner /etc/issue.net
${allow_users_line}
EOF

    append_deny_users_to_sshd_config

    if ! validate_sshd_config; then
        echo '    See errors above. To restore other drop-ins: mv /etc/ssh/sshd_config.d/*.bak-secure-pi /etc/ssh/sshd_config.d/'
        exit 1
    fi

    enable_ssh_on_boot || exit 1

    echo '[*] SSH hardened (public-key login). Effective settings:'
    sshd -T 2>/dev/null | grep -iE '^(pubkeyauthentication|passwordauthentication|permitrootlogin|allowusers|authorizedkeysfile) ' || true
    echo "[*] Key file: ~${ADMIN_USER}/.ssh/authorized_keys"
    echo "    Login as: ssh ${ADMIN_USER}@<pi-ip>"
}

function install_unattended_upgrades() {
    echo '[*] Enabling unattended security upgrades.'
    apt-get install -y unattended-upgrades apt-listchanges
    dpkg-reconfigure -plow unattended-upgrades 2>/dev/null || true
}

function maybe_reboot() {
    if [[ "${SKIP_REBOOT}" == "true" ]]; then
        echo '[*] SKIP_REBOOT=true — not rebooting.'
        print_next_steps
        return
    fi
    print_next_steps
    echo '[*] Rebooting in 10 seconds (Ctrl+C to cancel)...'
    sleep 10
    reboot
}

function print_next_steps() {
    echo ''
    echo '================================================================================'
    if [[ "${NEEDS_REBOOT:-false}" == "true" ]]; then
        echo '[*] Reboot REQUIRED (boot config changed).'
    else
        echo '[*] Reboot recommended before k3s install.'
    fi
    echo "    Test SSH from another machine:  ssh ${ADMIN_USER}@<pi-ip>"
    echo '    Then run:  sudo bash rpi_container_toolkit.sh --master-k3s'
    echo '               (or --worker-k3s on workers)'
    echo '================================================================================'
    echo ''
}

function secure_pi_os() {
    SSH_DENY_USERS=()
    NEEDS_REBOOT=false

    run_as_root
    update_apt
    detect_admin_user
    ask_for_hostname
    update_etc_hosts
    disable_swap
    ensure_cgroup_memory
    enable_usb_max_current
    enable_ip_forwarding
    set_keyboard_english
    install_ssh_server
    prompt_admin_password
    setup_ssh_keys
    fix_home_permissions_for_ssh "${ADMIN_USER}"
    require_sudo_password
    verify_admin_ssh_key
    configure_sshd
    install_unattended_upgrades
    maybe_reboot
}

function secure_ubuntu() {
    SSH_DENY_USERS=()
    NEEDS_REBOOT=false

    run_as_root
    update_apt
    detect_admin_user
    ask_for_hostname
    update_etc_hosts
    disable_swap
    ensure_cgroup_memory
    enable_ip_forwarding
    install_ssh_server
    prompt_admin_password
    setup_ssh_keys
    fix_home_permissions_for_ssh "${ADMIN_USER}"
    require_sudo_password
    verify_admin_ssh_key
    configure_sshd
    install_unattended_upgrades
    maybe_reboot
}

case "$1" in
    --pi-os|--raspbian)
        secure_pi_os
        ;;
    --ubuntu)
        secure_ubuntu
        ;;
    -h|--help)
        _help_menu
        ;;
    *)
        _help_menu
        ;;
esac
