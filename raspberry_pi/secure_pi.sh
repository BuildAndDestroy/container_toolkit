#!/bin/bash

###########################
#        TemperPi         #
# Secure the Raspberry Pi #
###########################

function run_as_root() { #  Best to run as root
    if [[ $(id -u) != 0 ]]; then
        echo '[*] Must be ran as root.'
        exit
    fi
}

function set_keyboard_english() { #  Update keyboard to English US
    echo -e '[*] Setting Keyboard to English (US)'
    sed -i 's/gb/us/g' /etc/default/keyboard
}

function create_pi_password() { #  Create a new pi user password
    echo '[*] Type in user "pi" password.'
    read -sp "Password: " password_pi_variable
}

function set_pi_password() { #  Set the new password for the pi user.
    echo -e '[*] Changing user "pi" password'
    echo -e "$password_pi_variable\n$password_pi_variable\n" | sudo passwd pi
}

function create_root_password() { #  Ask for the users new root password
    echo '[*] Type in user "root" password.'
    read -sp "Password: " password_root_variable
}

function set_root_password() { #  Set the new password for the root user.
    echo -e '[*] Changing user "root" password'
    echo -e "$password_root_variable\n$password_root_variable\n" | sudo passwd root
}

function config_root_ssh_keys() { #  Create Admin User Secure File Structure SSH
    if [ ! -d /home/root/.ssh ]; then
        mkdir /home/root/.ssh
        touch /home/root/.ssh/authorized_keys
    fi

    if [ ! -f /home/root/.ssh/authorized_keys ]; then
        touch /home/root/.ssh/authorized_keys
    fi
    echo "Please copy/paste your authorized key for 'root' user:"
    read -r -p ">>> " keyValue
    echo "$keyValue" >> /home/root/.ssh/authorized_keys

    chmod 700 /home/root/.ssh
    chmod 600 /home/root/.ssh/authorized_keys
    chown -R root:root /home/root
}

function create_node_password() { #  Ask for the new user password for node
    echo '[*] Type in user "node" password.'
    read -sp "Password: " password_node_variable
}

function create_node_user() { #  Set the new password for node
    echo -e '[*] Creating user node'
    sudo /usr/sbin/useradd node -m -s /bin/bash -U
    echo -e "$password_node_variable\n$password_node_variable\n" | passwd node
    sudo usermod -a -G adm,dialout,cdrom,sudo,audio,video,plugdev,games,users,input,netdev,gpio,i2c,spi node
}

function config_node_ssh_keys() { #  Create Admin User Secure File Structure SSH
    if [ ! -d /home/node/.ssh ]; then
        mkdir /home/node/.ssh
        touch /home/node/.ssh/authorized_keys
    fi

    if [ ! -f /home/node/.ssh/authorized_keys ]; then
        touch /home/node/.ssh/authorized_keys
    fi
    echo "Please copy/paste your authorized key for 'node' user:"
    read -r -p ">>> " keyValue
    echo "$keyValue" >> /home/node/.ssh/authorized_keys

    chmod 700 /home/node/.ssh
    chmod 600 /home/node/.ssh/authorized_keys
    chown -R node:node /home/node
}

function secure_sudo() { #  Require password when using sudo for pi and node
    sed -i 's/NOPASSWD/PASSWD/g' /etc/sudoers.d/010_pi-nopasswd
    mv /etc/sudoers.d/010_pi-nopasswd /etc/sudoers.d/010_pi-passwd
    touch /etc/sudoers.d/010_node-passwd
    cat /etc/sudoers.d/010_pi-passwd > /etc/sudoers.d/010_node-passwd
    sed -i 's/pi/node/g' /etc/sudoers.d/010_node-passwd
}

function configure_sshd() { #  Add a Banner to ssh requiring permission to get into the Pi.
    echo "" > /etc/issue.net
    echo "               #####################################################" >> /etc/issue.net
    echo "               # Unauthorized access to this machine is prohibited #" >> /etc/issue.net
    echo "               #  Speak with the owner first to obtain Permission  #" >> /etc/issue.net
    echo "               #####################################################" >> /etc/issue.net
    echo "" >> /etc/issue.net
    echo "" >> /etc/issue.net
    echo "" >> /etc/issue.net
    echo "" >> /etc/issue.net
    sed -i 's/#Banner\ none/Banner\ \/etc\/issue.net/g' /etc/ssh/sshd_config
    echo -e "AllowUsers node" >> /etc/ssh/sshd_config
    echo -e "DenyUsers pi" >> /etc/ssh/sshd_config
    sudo systemctl enable ssh
    sudo systemctl restart ssh
}

function update_apt() { #  Update apt repo for up to date packaging
    sudo apt-get update -y
    sudo apt-get upgrade -y
    sudo apt-get dist-upgrade -y
    sudo apt-get autoclean -y
    sudo apt-get autoremove -y
}

function install_firewall() { #  Install the firewall and allow port 22
    sudo apt-get install ufw -y
    sudo ufw enable
    sudo ufw allow 22/tcp
    sudo ufw status
}

function install_iptables() { #  Install persisent iptables
    sudo apt-get install iptables-persistent -y
}

function reboot_pi() { #  Reboot the pi
    echo '[*] Rebooting the pi in 5 seconds.'
    sleep 5
    reboot
}

################################
# Functions to run on execute. #
################################

run_as_root
set_keyboard_english
create_pi_password
set_pi_password
create_node_password
create_node_user
config_node_ssh_keys
create_root_password
set_root_password
config_root_ssh_keys
configure_sshd
secure_sudo
update_apt
install_iptables
install_firewall
reboot_pi