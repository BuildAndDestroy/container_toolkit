#!/bin/bash

###########################
#        Secure Pi        #
# Secure the Raspberry Pi #
###########################

function run_as_root() { #  Best to run as root
    if [[ $(/usr/bin/id -u) != 0 ]]; then
        /bin/echo '[*] Must be ran as root.'
        exit
    fi
}

function _help_menu() {
    # Help menu
    echo '[*] Help Menu:'
    echo ''
    echo '[*] --ubuntu     If running Ubuntu 21.10 ARM, run this to secure Ubuntu.'
    echo '                      bash secure_pi.sh --ubuntu'
    echo ''
    echo '[*] --raspbian   If running Raspbian, run this to secure Raspbian.'
    echo '                      bash secure_pi.sh --raspbian'
    echo ''
    exit
}

function set_keyboard_english() { #  Update keyboard to English US
    /bin/echo -e '[*] Setting Keyboard to English (US)'
    /bin/sed -i 's/gb/us/g' /etc/default/keyboard
}

function create_pi_password() { #  Create a new pi user password
    /bin/echo '[*] Type in user "pi" password.'
    read -sp "Password: " password_pi_variable
}

function set_pi_password() { #  Set the new password for the pi user.
    /bin/echo -e '[*] Changing user "pi" password'
    /bin/echo -e "$password_pi_variable\n$password_pi_variable\n" | /usr/bin/sudo /usr/bin/passwd pi
}

function create_node_password() { #  Ask for the new user password for node
    /bin/echo '[*] Type in user "node" password.'
    read -sp "Password: " password_node_variable
}

function create_node_user() { #  Set the new password for node
    /bin/echo -e '[*] Creating user node'
    /usr/bin/sudo /usr/sbin/useradd node -m -s /bin/bash -U
    /bin/echo -e "$password_node_variable\n$password_node_variable\n" | /usr/bin/passwd node
}

function raspbian_node_user_groups() { #  Add the correct groups for the node user.
    /usr/bin/sudo usermod -a -G adm,dialout,cdrom,sudo,audio,video,plugdev,games,users,input,netdev,gpio,i2c,spi node
}

function ubuntu_node_user_groups() { #  Add the correct groups for the node user.
    /usr/bin/sudo usermod -a -G ubuntu,adm,dialout,cdrom,floppy,sudo,audio,dip,video,plugdev,lxd,netdev node
}

function config_node_ssh_keys() { #  Create Admin User Secure File Structure SSH
    if [ ! -d /home/node/.ssh ]; then
        /bin/mkdir /home/node/.ssh
        /usr/bin/touch /home/node/.ssh/authorized_keys
    fi

    if [ ! -f /home/node/.ssh/authorized_keys ]; then
        /usr/bin/touch /home/node/.ssh/authorized_keys
    fi
    /bin/echo "Please copy/paste your authorized key for 'node' user:"
    read -r -p ">>> " keyValue
    /bin/echo "$keyValue" >> /home/node/.ssh/authorized_keys

    /bin/chmod 700 /home/node/.ssh
    /bin/chmod 600 /home/node/.ssh/authorized_keys
    /bin/chown -R node:node /home/node
}

function create_root_password() { #  Ask for the users new root password
    /bin/echo '[*] Type in user "root" password.'
    read -sp "Password: " password_root_variable
}

function set_root_password() { #  Set the new password for the root user.
    /bin/echo -e '[*] Changing user "root" password'
    /bin/echo -e "$password_root_variable\n$password_root_variable\n" | /usr/bin/sudo /usr/bin/passwd root
}

function config_root_ssh_keys() { #  Create Admin User Secure File Structure SSH
    if [ ! -d /root/.ssh ]; then
        /bin/mkdir /root/.ssh
        /usr/bin/touch /root/.ssh/authorized_keys
    fi

    if [ ! -f /root/.ssh/authorized_keys ]; then
        /usr/bin/touch /root/.ssh/authorized_keys
    fi
    /bin/echo "Please copy/paste your authorized key for 'root' user:"
    read -r -p ">>> " keyValue
    /bin/echo "$keyValue" >> /root/.ssh/authorized_keys

    /bin/chmod 700 /root/.ssh
    /bin/chmod 600 /root/.ssh/authorized_keys
    /bin/chown -R root:root /root
}

function ask_for_hostname() { #  Ask for the users new root password
    /bin/echo '[*] Changing hostname for this pi.'
    read -r -p "New Hostname: " user_requested_hostname
}

function set_hostname() { #  Request hostname.
    /bin/echo "[*] Setting hostname to "$user_requested_hostname""
    /usr/bin/hostnamectl set-hostname $user_requested_hostname
}

function cleanup_etc_hosts() { #  Remove the raspberrypi hostname from /etc/hosts
    /bin/sed -i '/raspberrypi/d' /etc/hosts
}

function set_etc_hosts_manually() { #  Add new hostname to /etc/hosts.
    /bin/echo "$(ifconfig | grep eth0 -A1 | grep inet | awk '{print $2}')" "$(hostnamectl --static)" >> /etc/hosts
}

function secure_sudo_raspbian() { #  Require password when using /usr/bin/sudo for pi and node users.
    /bin/sed -i 's/NOPASSWD/PASSWD/g' /etc/sudoers.d/010_pi-nopasswd
    mv /etc/sudoers.d/010_pi-nopasswd /etc/sudoers.d/010_pi-passwd
    /usr/bin/touch /etc/sudoers.d/010_node-passwd
    cat /etc/sudoers.d/010_pi-passwd > /etc/sudoers.d/010_node-passwd
    /bin/sed -i 's/pi/node/g' /etc/sudoers.d/010_node-passwd
}

function secure_sudo_ubuntu() { #  Require password when using /usr/bin/sudo for ubuntu or node users.
    /bin/sed -i 's/NOPASSWD/PASSWD/g' /etc/sudoers.d/90-cloud-init-users
    /bin/echo "# User rules for node" >> /etc/sudoers.d/90-cloud-init-users
    /bin/echo "node ALL=(ALL) PASSWD:ALL" >> /etc/sudoers.d/90-cloud-init-users
}

function configure_sshd() { #  Add a Banner to ssh requiring permission to get into the Pi.
    /bin/echo "" > /etc/issue.net
    /bin/echo "               #####################################################" >> /etc/issue.net
    /bin/echo "               # Unauthorized access to this machine is prohibited #" >> /etc/issue.net
    /bin/echo "               #  Speak with the owner first to obtain Permission  #" >> /etc/issue.net
    /bin/echo "               #####################################################" >> /etc/issue.net
    /bin/echo "" >> /etc/issue.net
    /bin/echo "" >> /etc/issue.net
    /bin/echo "" >> /etc/issue.net
    /bin/echo "" >> /etc/issue.net
    /bin/sed -i 's/#Banner\ none/Banner\ \/etc\/issue.net/g' /etc/ssh/sshd_config
    /bin/sed -i 's/#PermitRootLogin\ prohibit-password/PermitRootLogin\ yes/g' /etc/ssh/sshd_config
    /bin/sed -i 's/#PasswordAuthentication\ yes/PasswordAuthentication\ no/g' /etc/ssh/sshd_config
    /bin/sed -i 's/#AuthorizedKeysFile/AuthorizedKeysFile/g' /etc/ssh/sshd_config
    #/bin/echo -e "AllowUsers node" >> /etc/ssh/sshd_config
}

function deny_default_user() { #  If default users exist, blacklist them from ssh.
    if [ $(/bin/cat /etc/passwd | /bin/grep pi | /usr/bin/wc -l) -eq 1 ]; then
        /bin/echo -e "DenyUsers pi" >> /etc/ssh/sshd_config
    elif [ $(/bin/cat /etc/passwd | /bin/grep ubuntu | /usr/bin/wc -l) -eq 1 ]; then
        /bin/echo -e "DenyUsers ubuntu" >> /etc/ssh/sshd_config
    fi
}

function enable_restart_ssh() { # Enable and restart ssh.
    /usr/bin/sudo systemctl enable ssh
    /usr/bin/sudo systemctl restart ssh
}

function update_apt() { #  Update apt repo for up to date packaging
    /usr/bin/sudo apt-get update -y
    /usr/bin/sudo apt-get upgrade -y
    /usr/bin/sudo apt-get dist-upgrade -y
    /usr/bin/sudo apt-get autoclean -y
    /usr/bin/sudo apt-get autoremove -y
}

function install_iptables() { #  Install persisent iptables
    /usr/bin/sudo apt-get install iptables-persistent -y
}

function cgroup_to_bootfile() { #  Must use cgroup memory, needed in boot file
    sed -i 's/$/\ cgroup_enable=cpuset\ cgroup_memory=1\ cgroup_enable=memory/' /boot/firmware/cmdline.txt
}

function enable_iptables_for_k3s() {
    /usr/bin/sudo /usr/sbin/iptables -F
    /usr/bin/sudo /usr/bin/update-alternatives --set iptables /usr/sbin/iptables-legacy
    /usr/bin/sudo /usr/bin/update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
}

function install_firewall() { #  Install the firewall and allow port 22
    /usr/bin/sudo apt-get install ufw -y
    /usr/bin/sudo ufw enable
    /usr/bin/sudo ufw allow 22/tcp
    /usr/bin/sudo ufw status
}

function reboot_pi() { #  Reboot the pi
    /bin/echo '[*] Rebooting the pi in 5 seconds.'
    sleep 5
    reboot
}

################################
# Functions to run on execute. #
################################

############################
# Functions to be executed #
############################


case "$1" in
    --ubuntu)
        run_as_root
        create_node_password
        create_node_user
        ubuntu_node_user_groups
        config_node_ssh_keys
        create_root_password
        set_root_password
        config_root_ssh_keys
        ask_for_hostname
        set_hostname
        set_etc_hosts_manually
        secure_sudo_ubuntu
        configure_sshd
        deny_default_user
        enable_restart_ssh
        enable_iptables_for_k3s
        cgroup_to_bootfile
        update_apt
        reboot_pi
        ;;
    --raspbian)
        run_as_root
        set_keyboard_english
        create_pi_password
        set_pi_password
        create_node_password
        create_node_user
        raspbian_node_user_groups
        config_node_ssh_keys
        create_root_password
        set_root_password
        config_root_ssh_keys
        ask_for_hostname
        set_hostname
        cleanup_etc_hosts
        set_etc_hosts_manually
        secure_sudo_raspbian
        configure_sshd
        deny_default_user
        enable_restart_ssh
        update_apt
        install_iptables
        install_firewall
        reboot_pi
        ;;
    -h)
        _help_menu
        ;;
    --help)
        _help_menu
        ;;
    *)
        _help_menu
        ;;
esac