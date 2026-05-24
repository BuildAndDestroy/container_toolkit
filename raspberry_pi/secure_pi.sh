#!/bin/bash
#
# Harden Raspberry Pi OS Lite (64-bit) or Ubuntu Server for ARM before k3s.
# Run once per node as root, BEFORE rpi_container_toolkit.sh.
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
    echo '[*] --raspbian     Alias for --pi-os (legacy flag name).'
    echo ''
    echo '[*] --ubuntu       Ubuntu Server for Raspberry Pi (ARM64).'
    echo '                 sudo bash secure_pi.sh --ubuntu'
    echo ''
    echo 'Options (environment):'
    echo '  ADMIN_USER=<name>       Admin account to harden (default: your Imager user).'
    echo '  CREATE_NODE_USER=true   Also create a "node" user with SSH keys.'
    echo '  SKIP_REBOOT=true        Do not reboot at the end.'
    echo ''
    echo 'If you added an SSH public key in Raspberry Pi Imager, it is detected'
    echo 'automatically and you will not be prompted again.'
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

    # User who invoked sudo, else first normal login user (uid >= 1000).
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

function set_keyboard_english() {
    if [[ -f /etc/default/keyboard ]]; then
        sed -i 's/gb/us/g; s/GB/us/g' /etc/default/keyboard 2>/dev/null || true
        echo '[*] Keyboard layout set to US (if configured).'
    fi
}

function prompt_admin_password() {
    echo "[*] Set a strong password for ${ADMIN_USER} (sudo will require it after this)."
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
    # Imager / cloud-init typically adds ssh-ed25519, ssh-rsa, or ecdsa keys.
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
        echo "[*] SSH key(s) already configured for '${user}' (${count} key(s), e.g. from Raspberry Pi Imager) — skipping."
        return 0
    fi

    echo "[*] No SSH public key found for '${user}'."
    echo "[*] Paste one SSH public key (single line), then press Enter:"
    read -r key_line
    if [[ -n "${key_line}" ]]; then
        if ! grep -qF "${key_line}" "$(eval echo "~${user}")/.ssh/authorized_keys" 2>/dev/null; then
            echo "${key_line}" >> "$(eval echo "~${user}")/.ssh/authorized_keys"
        fi
        ensure_ssh_dir_permissions "${user}"
        echo "[*] SSH key added for '${user}'."
    else
        echo "[*] Error: no key provided for '${user}'."
        echo '    Add a key in Raspberry Pi Imager or paste one here, then re-run secure_pi.sh.'
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
    echo '    Configure one in Raspberry Pi Imager (recommended) or re-run and paste a key.'
    exit 1
}

function ask_for_hostname() {
    local current
    current=$(hostnamectl --static 2>/dev/null || hostname -s)
    echo "[*] Current hostname: ${current}"
    read -r -p '[*] New hostname (Enter to keep current): ' user_requested_hostname
    if [[ -n "${user_requested_hostname}" ]]; then
        hostnamectl set-hostname "${user_requested_hostname}"
        echo "[*] Hostname set to ${user_requested_hostname}"
    fi
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
    fi
}

function require_sudo_password() {
    echo '[*] Requiring a password for sudo (removing NOPASSWD rules).'
    local f
    for f in /etc/sudoers.d/*; do
        [[ -f "${f}" ]] || continue
        sed -i 's/NOPASSWD: ALL/PASSWD: ALL/g; s/NOPASSWD:ALL/PASSWD:ALL/g' "${f}"
    done
    if ! grep -q "^${ADMIN_USER} " /etc/sudoers.d/* 2>/dev/null \
        && ! grep -q "^${ADMIN_USER} " /etc/sudoers 2>/dev/null; then
        echo "${ADMIN_USER} ALL=(ALL) PASSWD:ALL" > "/etc/sudoers.d/090-${ADMIN_USER}"
        chmod 440 "/etc/sudoers.d/090-${ADMIN_USER}"
    fi
}

function lock_legacy_users() {
    if id pi &>/dev/null; then
        echo '[*] Locking legacy "pi" account.'
        passwd -l pi 2>/dev/null || true
        SSH_DENY_USERS+=("pi")
    fi
}

function write_ssh_banner() {
    cat >/etc/issue.net <<'EOF'

  #####################################################################
  #  Unauthorized access to this system is prohibited.               #
  #####################################################################

EOF
}

function configure_sshd() {
    write_ssh_banner
    lock_legacy_users

    local allow_users deny_users
    allow_users=$(IFS=,; echo "${SSH_ALLOW_USERS[*]}")
    deny_users=""
    if [[ ${#SSH_DENY_USERS[@]} -gt 0 ]]; then
        deny_users=$(IFS=,; echo "${SSH_DENY_USERS[*]}")
    fi

    mkdir -p /etc/ssh/sshd_config.d
    cat >/etc/ssh/sshd_config.d/99-secure-pi.conf <<EOF
# Managed by secure_pi.sh — do not edit by hand; change secure_pi.sh and re-run.
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
X11Forwarding no
Banner /etc/issue.net
AllowUsers ${allow_users}
EOF

    if [[ -n "${deny_users}" ]]; then
        echo "DenyUsers ${deny_users}" >> /etc/ssh/sshd_config.d/99-secure-pi.conf
    fi

    if id ubuntu &>/dev/null; then
        echo "DenyUsers ubuntu" >> /etc/ssh/sshd_config.d/99-secure-pi.conf
    fi

    systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || true
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
    echo '[*] SSH configured: key-only login, root login disabled.'
    echo "    Allowed users: ${allow_users}"
}

function disable_swap() {
    echo '[*] Disabling swap (required for Kubernetes).'
    swapoff -a 2>/dev/null || true
    sed -i.bak-secure-pi '/[[:space:]]swap[[:space:]]/s/^\([^#]\)/#\1/' /etc/fstab
    if [[ -f /etc/dphys-swapfile ]]; then
        systemctl disable dphys-swapfile 2>/dev/null || true
        systemctl stop dphys-swapfile 2>/dev/null || true
    fi
}

function ensure_cgroup_memory() {
    local cmdline_files=("/boot/firmware/cmdline.txt" "/boot/cmdline.txt")
    local cgroup_opts='cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory'
    local f changed=0

    for f in "${cmdline_files[@]}"; do
        [[ -f "${f}" ]] || continue
        if grep -q 'cgroup_enable=memory' "${f}"; then
            echo "[*] cgroup memory already enabled in ${f}"
            return 0
        fi
        sed -i "s/$/ ${cgroup_opts}/" "${f}"
        echo "[*] Added cgroup options to ${f}"
        changed=1
    done

    if [[ ${changed} -eq 1 ]]; then
        echo '[*] cgroup boot parameters added — reboot required before k3s install.'
        NEEDS_REBOOT=true
    fi
}

function enable_ip_forwarding() {
    tee /etc/sysctl.d/99-kubernetes.conf >/dev/null <<EOF
net.ipv4.ip_forward = 1
EOF
    sysctl --system >/dev/null
}

function enable_iptables_legacy() {
    echo '[*] Setting iptables to legacy mode (k3s compatibility).'
    update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true
}

function install_k3s_firewall() {
    echo '[*] Configuring UFW for SSH + k3s cluster traffic.'
    apt-get install -y ufw

    # Allow outbound by default; restrict inbound.
    ufw default deny incoming
    ufw default allow outgoing

    ufw allow 22/tcp comment 'SSH'
    ufw allow 6443/tcp comment 'k3s API'
    ufw allow 10250/tcp comment 'kubelet'
    ufw allow 8472/udp comment 'Calico VXLAN'
    ufw allow 4789/udp comment 'VXLAN'
    ufw allow 51820/udp comment 'Calico Wireguard'
    ufw allow 30000:32767/tcp comment 'NodePort range'

    ufw --force enable
    ufw status verbose
}

function update_apt() {
    echo '[*] Updating packages.'
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    apt-get autoremove -y
    apt-get autoclean -y
}

function install_unattended_upgrades() {
    echo '[*] Enabling unattended security upgrades.'
    apt-get install -y unattended-upgrades apt-listchanges
    dpkg-reconfigure -plow unattended-upgrades 2>/dev/null || true
}

function maybe_reboot() {
    if [[ "${SKIP_REBOOT}" == "true" ]]; then
        echo '[*] SKIP_REBOOT=true — not rebooting.'
        return
    fi
    echo ''
    echo '================================================================================'
    if [[ "${NEEDS_REBOOT:-false}" == "true" ]]; then
        echo '[*] Reboot REQUIRED (cgroup boot parameters were changed).'
    else
        echo '[*] Reboot recommended to apply all changes.'
    fi
    echo '    Test SSH in a NEW terminal before closing this session:'
    echo "      ssh ${ADMIN_USER}@<pi-ip>"
    if ! ssh_user_has_keys "${ADMIN_USER}" 2>/dev/null; then
        echo ''
        echo '    WARNING: No SSH key detected for admin user — add a key before reboot'
        echo '      or you may be locked out when password auth is disabled.'
    fi
    echo ''
    echo '    Next step after reboot:'
    echo '      sudo bash rpi_container_toolkit.sh --master-k3s   # or --worker-k3s'
    echo '================================================================================'
    echo '[*] Rebooting in 10 seconds (Ctrl+C to cancel)...'
    sleep 10
    reboot
}

function secure_pi_os() {
    SSH_DENY_USERS=()
    NEEDS_REBOOT=false

    run_as_root
    detect_admin_user
    set_keyboard_english
    prompt_admin_password
    setup_ssh_keys
    ask_for_hostname
    update_etc_hosts
    require_sudo_password
    disable_swap
    ensure_cgroup_memory
    enable_ip_forwarding
    enable_iptables_legacy
    verify_admin_ssh_key
    configure_sshd
    update_apt
    install_unattended_upgrades
    install_k3s_firewall
    maybe_reboot
}

function secure_ubuntu() {
    SSH_DENY_USERS=()
    NEEDS_REBOOT=false

    run_as_root
    detect_admin_user
    prompt_admin_password
    setup_ssh_keys
    ask_for_hostname
    update_etc_hosts
    require_sudo_password
    disable_swap
    ensure_cgroup_memory
    enable_ip_forwarding
    enable_iptables_legacy
    verify_admin_ssh_key
    configure_sshd
    update_apt
    install_unattended_upgrades
    install_k3s_firewall
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
