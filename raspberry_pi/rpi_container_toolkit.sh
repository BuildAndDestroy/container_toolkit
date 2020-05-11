#!/bin/bash

############################################
# Prepare and install k8's on raspberry pi #
#            Tested on Pi4b                #
############################################

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
    echo '[*] --init       Run first on every pi! Then move on to --master OR --worker. TURNED OFF FOR NOW.'
    echo '                      bash rpi_container_toolkit.sh --init'
    echo ''
    echo '[*] --master     Install full Kubernetes k8s MASTER NODE Calico and Docker. DOES NOT WORK'
    echo '                      bash rpi_container_toolkit.sh --master'
    echo ''
    echo '[*] --worker     Install full Kubernetes k8s WORKER NODE and Docker. DOES NOT WORK'
    echo '                      bash rpi_container_toolkit.sh --worker'
    echo ''
    echo '[*] --rancherk3s-master    The generic k3s install for Master.'
    echo '                     bash rpi_container_toolkit.sh --rancherk3s-master'
    echo ''
    echo '[*] --rancherk3s-worker    The generic k3s install for Worker.'
    echo '                     bash rpi_container_toolkit.sh --rancherk3s-worker'
    echo ''
    echo '[*] --rancherk3s-master-docker    K3s install for Master but with Docker instead of containerd.'
    echo '                     bash rpi_container_toolkit.sh --rancherk3s-master-docker'
    echo ''
    echo '[*] --rancherk3s-worker-docker    K3s install for Worker but with Docker instead of containerd.'
    echo '                     bash rpi_container_toolkit.sh --rancherk3s-worker-docker'
    echo ''
    echo '[*] --helm       Install Helm3 to Master'
    echo '                      bash rpi_container_toolkit.sh --helm'
    echo ''
    exit
}

function update_apt() { #  Update apt repo for up to date packaging
    /usr/bin/sudo apt-get update -y
    /usr/bin/sudo apt-get upgrade -y
    /usr/bin/sudo apt-get dist-upgrade -y
    /usr/bin/sudo apt-get autoclean -y
    /usr/bin/sudo apt-get autoremove -y
}

function enable_traffic_forwarding() {
    /bin/echo "[*] Allowing traffic forwarding."
    /bin/sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
    /bin/sed -i '/^net.ipv4.ip_forward=1/a net.ipv4.ip_nonlocal_bind=1' /etc/sysctl.conf
}

function disable_swap() {
    /bin/echo "[*] Disabling Swap"
    /sbin/swapoff -av
    /usr/bin/free
}

function install_docker() { #  Use docker's shell script to install.
    /bin/echo "[*] Installing Docker"
    /usr/bin/curl -sSL get.docker.com | /bin/sh && /usr/sbin/usermod node -aG docker
}

function ufw_ports_allowed() { #  Enable NAT forwarding, masquerade, and reqired ports.
    /bin/echo "[*] Enabling required ports."
    /usr/bin/sudo apt-get install ufw -y
    /usr/bin/sudo /usr/sbin/ufw enable
    /bin/sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/g' /etc/default/ufw
    /bin/sed -i 's@#net/ipv4/ip_forward=1@net/ipv4/ip_forward=1@g' /etc/ufw/sysctl.conf
    #     sed -i '/^*filter/i # NAT table rules
    #     *nat
    # :PREROUTING ACCEPT [0:0]
    # :POSTROUTING ACCEPT [0:0]

    # # Port Forwardings
    # -A PREROUTING -i eth0 -p tcp --dport 22 -j DNAT --to-destination 10.96.0.0

    # # Forward traffic through eth0 - Change to match you out-interface
    # -A POSTROUTING -s 10.96.0.0/16 -o eth0 -j MASQUERADE

    # # don't delete the 'COMMIT' line or these nat table rules won't
    # # be processed
    # COMMIT' /etc/ufw/before.rules
    /usr/bin/sudo /usr/sbin/ufw allow 22/tcp
    /usr/bin/sudo /usr/sbin/ufw allow 80/tcp
    /usr/bin/sudo /usr/sbin/ufw allow 443/tcp
    /usr/bin/sudo /usr/sbin/ufw allow 2376/tcp
    /usr/bin/sudo /usr/sbin/ufw allow 2379/tcp
    /usr/bin/sudo /usr/sbin/ufw allow 2380/tcp
    /usr/bin/sudo /usr/sbin/ufw allow 4789/udp
    /usr/bin/sudo /usr/sbin/ufw allow 6443/tcp
    /usr/bin/sudo /usr/sbin/ufw allow 6783:6784/udp
    /usr/bin/sudo /usr/sbin/ufw allow 8472/udp
    /usr/bin/sudo /usr/sbin/ufw allow 9099/tcp
    /usr/bin/sudo /usr/sbin/ufw allow 10250/tcp
    /usr/bin/sudo /usr/sbin/ufw allow 10251/tcp
    /usr/bin/sudo /usr/sbin/ufw allow 10252/tcp
    /usr/bin/sudo /usr/sbin/ufw allow 10254/tcp
    /usr/bin/sudo /usr/sbin/ufw allow 10255/tcp
    /usr/bin/sudo /usr/sbin/ufw allow 30000:32767/tcp
    /usr/bin/sudo /usr/sbin/ufw allow 30000:32767/udp
    /usr/bin/sudo /usr/sbin/ufw reload
}

function install_kubernetes() { #  Install Kubernetes
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
    /usr/bin/sudo apt-key add - && echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | \
    /usr/bin/sudo tee /etc/apt/sources.list.d/kubernetes.list && /usr/bin/sudo apt-get update -q
    /usr/bin/sudo apt-get -y install kubelet kubectl kubeadm
}

# function set_cgroup_driver() {
#     # Update cgroup driver for kubernetes
#     echo '[*] Verify Docker cgroupfs'
#     docker info | grep -i cgroup
#     echo '[*] Updating Docker to use same cgroup.'
# cat > /etc/docker/daemon.json <<EOF
# {
#   "exec-opts": ["native.cgroupdriver=systemd"],
#   "log-driver": "json-file",
#   "log-opts": {
#     "max-size": "100m"
#   },
#   "storage-driver": "overlay2",
#   "storage-opts": [
#     "overlay2.override_kernel_check=true"
#   ]
# }
# EOF
#     mkdir -p /etc/systemd/system/docker.service.d
#     systemctl daemon-reload
#     systemctl restart docker
#     systemctl restart kubelet
# }

function cgroup_to_bootfile() { #  Must use cgroup memory, needed in boot file
    sed -i 's/$/\ cgroup_enable=cpuset\ cgroup_memory=1\ cgroup_enable=memory/' /boot/firmware/nobtcmd.txt
}

function reboot_the_pi() {
    echo '[*] Rebooting the pi in 5 seconds'
    sleep 5
    /sbin/reboot
}

#################
# Master node

function kubernetes_api_server() {
    # Beginning of Master node setup.
    echo '[*] Starting Master node.'
    kubeadm init #--pod-network-cidr=192.168.0.0/16
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
}

function install_calico_network_policy() {
    # Install the calico pod network.
    # curl https://docs.projectcalico.org/v3.11/manifests/calico.yaml -O
    curl https://docs.projectcalico.org/master/manifests/calico.yaml -O
    sed -i -e "s?192.168.0.0?10.96.0.0?g" calico.yaml
    kubectl apply -f calico.yaml
    echo '[*] Check pods with "kubectl get pods --all-namespaces".'
    kubectl get pods --all-namespaces
}

function install_calicoctl() {
    echo '[*] Installing calicoctl as a pod'
    kubectl apply -f https://docs.projectcalico.org/manifests/calicoctl.yaml
    kubectl exec -ti -n kube-system calicoctl -- /calicoctl get profiles -o wide
}

#############
# Worker

function join_worker_node() {
    echo '[*] Use the kubeadm join tool to join the master. If you lost this, then run on Master to get the join command:'
    echo '        kubeadm token create --print-join-command'
}

#############
# k3s Master

function k3s_master_kubernetes() {
    curl -sfL https://get.k3s.io | sh -
    /bin/cat /var/lib/rancher/k3s/server/node-token
}

function k3s_systemctl_docker() {
    /usr/local/bin/k3s-killall.sh
    /bin/sed -i 's@server\ \@@g' /etc/systemd/system/k3s.service
    /bin/sed -i 's@ExecStart=/usr/local/bin/k3s\ \@ExecStart=/usr/local/bin/k3s\ server\ --docker@g' /etc/systemd/system/k3s.service
    systemctl daemon-reload
    systemctl stop k3s
    systemctl start k3s
}

#############
# k3s Worker

function k3s_worker_kubernetes() {
    /bin/echo '[*] Type in the Master token file from /var/lib/rancher/k3s/server/node-token'
    read -r -p "Node Token: " k3s_token

    /bin/echo '[*] Type in the Master nodes IP Address.'
    read -r -p "Master's IP Address: " master_ip

    export K3S_URL="https://"$master_ip":6443"
    export K3S_TOKEN=""$k3s_token""
    curl -sfL https://get.k3s.io | sh -
}

#################
#  Helm charts  #
#################

############
# Helm

function install_helm_three(){
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    helm repo add stable https://kubernetes-charts.storage.googleapis.com/
    helm repo update
}

############
# traefik

function isntall_traefik_loadbalancer() { #  Install a loadbalancer for pi.
    helm install traefik stable/traefik
}


############################
# Functions to be executed #
############################

case "$1" in
    --init)
        echo 'Pending the full K8s build.'
        # run_as_root
        # update_apt
        # enable_traffic_forwarding
        # disable_swap
        # install_docker
        # ufw_ports_allowed
        # install_kubernetes
        # set_cgroup_driver
        # cgroup_to_bootfile
        # reboot_the_pi
        ;;
    --master)
        # kubernetes_api_server
        # install_calico_network_policy
        # install_calicoctl
        # If no join command, use "kubeadm token create --print-join-command"
        echo 'Still testing, full k8s not working'
        ;;
    --worker)
        # join_worker_node
        echo 'Still testing, full k8s not working'
        ;;
    --rancherk3s-master)
        cgroup_to_bootfile
        ufw_ports_allowed
        k3s_master_kubernetes
        reboot_the_pi
        ;;
    --rancherk3s-worker)
        cgroup_to_bootfile
        ufw_ports_allowed
        k3s_worker_kubernetes
        reboot_the_pi
        ;;
    --rancherk3s-master-docker)
        cgroup_to_bootfile
        install_docker
        ufw_ports_allowed
        k3s_master_kubernetes
        k3s_systemctl_docker
        reboot_the_pi
        ;;
    --rancherk3s-worker-docker)
        cgroup_to_bootfile
        install_docker
        ufw_ports_allowed
        k3s_worker_kubernetes
        reboot_the_pi
        ;;
    --helm)
        run_as_root
        install_helm_three
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