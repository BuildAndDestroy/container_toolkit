#!/bin/bash

# https://linuxconfig.org/how-to-install-kubernetes-on-ubuntu-20-04-focal-fossa-linux

#########################################################################
#                  Automate the container install process.              #
#                                                                       #
#                 Install Kubernetes, Docker, and Rancher               #
#########################################################################

function _run_as_root() {
    # Run as root
    if [[ $(id -u) != 0 ]]; then
        echo 'Must be ran as root.'
        exit
    fi
}

function _help_menu() {
    # Help menu
    echo '[*] Help Menu:'
    echo ''
    echo '[*] --master-calico   Install Kubernetes MASTER NODE Calico and Docker.'
    echo '                      bash container_toolkit.sh --master-calico'
    echo ''
    echo '[*] --worker-node     Install Kubernetes WORKER NODE and Docker'
    echo '                      bash container_toolkit.sh --worker-node'
    echo ''
    echo '[*] --docker     Install ONLY Docker.'
    echo '                 bash container_toolkit.sh --docker'
    echo ''
    echo '[*] --rancher    Install a ONLY Rancher constainer.'
    echo '                 bash container_toolkit.sh --rancher'
    echo ''
    echo '[*] --helm       Apply this option to install helm.'
    echo '                 bash container_toolkit.sh --helm'
    echo ''
    echo '[*] --clean      Clean up Kubernetes WORKER NODES. Typically we should not need this.'
    echo '                 bash container_toolkit.sh --clean'
    echo ''
    exit
}


function cleanup_docker() {
    # Cleanup any currently installed docker package.
    echo '[*] Removing old Docker packages.'
    sudo apt remove docker docker-engine docker.io containerd runc -y
}

function install_dependencies() {
    # Setup packages for docker.
    echo '[*] Installing packages to support Docker.'
    sudo apt update -y
    sudo apt install apt-transport-https ca-certificates curl gnupg gnupg2 software-properties-common nfs-common -y
}

function docker_install_script(){
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh ./get-docker.sh --dry-run
}

function set_hostname() {
    echo "$(ip a | grep enp -A1 | grep inet | awk '{print $2}' | sed 's/\/24//g')" "$(hostnamectl --static)" >> /etc/hosts
}

function disable_swap() {
    # Disable swap and comment out from /etc/fstab
    echo '[*] Disabling SWAP and commenting out fstab.'
    /sbin/swapoff -av
    edit_swap=$(cat /etc/fstab | awk '{print $1}' | grep swap)
    sed -i "s|$edit_swap|#$edit_swap|g" /etc/fstab
    cat /etc/fstab | grep swap
}

function load_kernel_modules() {
    sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF
    sudo modprobe overlay
    sudo modprobe br_netfilter
}

function update_bridge() {
    sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
    sudo sysctl --system
}

function enable_docker_repo(){
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmour -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -y
}

function install_docker_packages(){
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
    sudo docker run hello-world
}

function install_containerd(){
    sudo apt update -y
    sudo apt install -y containerd.io
}

function containerd_use_systemd(){
    containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
    sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
}

function restart_enable_containerd(){
    sudo systemctl restart containerd
    sudo systemctl enable containerd
}

function add_kubernetes_repo(){
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list
}

function install_kube_commands(){
    sudo apt update -y
    sudo apt install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
}

function restart_kubelet_services(){
    sudo systemctl restart kubelet.service
    sudo systemctl enable kubelet.service
}

function init_kubernetes_images(){
    sudo kubeadm config images pull
}

function api_server_master_calico() {
    # Beginning of Master node setup.
    echo '[*] Starting Master node.'
    #kubeadm init --pod-network-cidr=192.168.0.0/16
    kubeadm init --pod-network-cidr=10.96.0.0/16
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
}

function install_calico_network_policy() {
    # Install the calico pod network.
    #curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml -O
    #sed -i -e "s?192.168.0.0?10.96.0.0?g" calico.yaml
    #kubectl apply -f calico.yaml
    #echo '[*] Check pods with "kubectl get pods --all-namespaces". Once done, install --helm.'
    #kubectl get pods --all-namespaces
    curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.3/manifests/tigera-operator.yaml -O
    curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.3/manifests/custom-resources.yaml -O
    kubectl create -f tigera-operator.yaml
    sed -i 's/cidr: 192\.168\.0\.0\/16/cidr: 10.96.0.0\/16/g' custom-resources.yaml
    kubectl create -f custom-resources.yaml
}

function install_calicoctl() {
    echo '[*] Installing calicoctl as a pod'
    # etcd:
    #kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.3/manifests/calicoctl-etcd.yaml
    # K8s API datastore:
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.3/manifests/calicoctl.yaml
    kubectl exec -ti -n kube-system calicoctl -- /calicoctl get profiles -o wide
}

function set_felix_loose_true() {
    echo '[*] Ignoring loose RPF for Felix.'
    kubectl -n kube-system set env daemonset/calico-node FELIX_IGNORELOOSERPF=true
}

function install_rancher() {
    # Install Rancher on master kubernetes host.
    sudo docker run --privileged -d --restart=unless-stopped -p 80:80 -p 443:443 rancher/rancher
}

function cleanup_workers() {
    # Cleanup workers for Rancher.
    docker rm -f $(docker ps -qa)
    docker volume rm $(docker volume ls -q)
    cleanupdirs="/var/lib/etcd /etc/kubernetes /etc/cni /opt/cni /var/lib/cni /var/run/calico /opt/rke"
    for dir in $cleanupdirs; do
      echo "Removing $dir"
      rm -rf $dir
    done
}

function install_helm_three(){
    curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
    sudo apt-get install apt-transport-https -y
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
    sudo apt-get update -y
    sudo apt-get install helm -y
}

################################
# ***Notes
# Patch a Service to external Node port like so: (Good for on prem)
#     kubectl patch service nginx-ingress-controller -p '{"spec":{"externalIPs":["192.168.1.101"]}}'
# This will not be HA though

############################
# Functions to be executed #
############################


case "$1" in
    --docker)
        _run_as_root
        cleanup_docker
        install_dependencies
	docker_install_script
        ;;
    --master-calico)
        _run_as_root
        cleanup_docker
        install_dependencies
	set_hostname
	disable_swap
	load_kernel_modules
	update_bridge
	enable_docker_repo
	install_docker_packages
	install_containerd
	containerd_use_systemd
	restart_enable_containerd
	add_kubernetes_repo
	install_kube_commands
	restart_kubelet_services
	init_kubernetes_images
	api_server_master_calico
	install_calico_network_policy
	install_calicoctl
	set_felix_loose_true
        ;;
    --worker-node)
        _run_as_root
        cleanup_docker
        install_dependencies
	set_hostname
	disable_swap
	load_kernel_modules
	update_bridge
	enable_docker_repo
	install_docker_packages
	install_containerd
	containerd_use_systemd
	restart_enable_containerd
	add_kubernetes_repo
	install_kube_commands
        ;;
    --helm)
        _run_as_root
        install_helm_three
        ;;
    --rancher)
        _run_as_root
        cleanup_docker
        install_dependencies
        set_hostname
	docker_install_script
        install_rancher
        ;;
    --clean)
        echo 'Needs Testing'
        exit
        _run_as_root
        cleanup_workers
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
