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
    echo '[*] --PSO-init   After Kubernetes is up, run this first to install Pure Storage PSO.'
    echo '                 bash container_toolkit.sh --PSO-init'
    echo ''
    echo '    >>> --PSO-kube OR --PSO-helm, not both.'
    echo ''
    echo '[*] --PSO-kube   After PSO-init ws ran, run this to install PSO into kubectl.'
    echo '                 bash container_toolkit.sh --PSO-kube'
    echo ''
    echo '[*] --PSO-helm   After PSO-init ws ran run this to install PSO into helm.'
    echo '                 bash container_toolkit.sh --PSO-helm'
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
    sudo apt install apt-transport-https ca-certificates curl gnupg2 software-properties-common nfs-common -y
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
    #echo 'net.bridge.bridge-nf-call-ip6tables = 1' >> /etc/sysctl.conf
    #echo 'net.bridge.bridge-nf-call-iptables = 1' >> /etc/sysctl.conf
    #sysctl -p
    sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
    sudo sysctl --system
}

#function install_containerd_runtime_dependencies() {
#    sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates
#}

#function restart_containerd() {
#    # Bug workaround for v1.24.0
#    mv /etc/containerd/config.toml /etc/containerd/config.toml.bak
#    systemctl restart containerd
#}

function enable_docker_repo(){
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
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
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/kubernetes-xenial.gpg
    sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
}

function install_kube_commands(){
    sudo apt update -y
    sudo apt install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
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
    curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml -O
    sed -i -e "s?192.168.0.0?10.96.0.0?g" calico.yaml
    kubectl apply -f calico.yaml
    echo '[*] Check pods with "kubectl get pods --all-namespaces". Once done, install --helm.'
    kubectl get pods --all-namespaces
}

function install_calicoctl() {
    echo '[*] Installing calicoctl as a pod'
    kubectl apply -f https://docs.projectcalico.org/manifests/calicoctl.yaml
    kubectl exec -ti -n kube-system calicoctl -- /calicoctl get profiles -o wide
}

function set_felix_loose_true() {
    echo '[*] Ignoring loose RPF for Felix.'
    kubectl -n kube-system set env daemonset/calico-node FELIX_IGNORELOOSERPF=true
}

function install_rancher() {
    # Install Rancher on master kubernetes host.
    docker run -d --restart=unless-stopped -p 80:80 -p 443:443 -v /opt/rancher:/var/lib/rancher rancher/rancher
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

function tiller_permissions_yaml() {
    # Install tiller permissions for kubernetes RBAC.
    cat <<EOF > helm-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tiller
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tiller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: tiller
    namespace: kube-system
EOF
    kubectl apply -f helm-rbac.yaml
}

function install_helm() {
    # Install helm once.
    echo "[*] Installing helm."
    curl -L https://git.io/get_helm.sh > install-helm.sh
    chmod 755 install-helm.sh
    ./install-helm.sh
}

function install_helm_chart() {
    echo '[*] Updating firewall and installing helm dashboard.'
    echo '[*] Add nodes to your cluster, this will allow Tiller to deploy.'
    echo '[*] Once the tiller container deploys, run both commands:'
    echo '        helm install stable/kubernetes-dashboard --name dashboard-demo'
    echo '        helm upgrade dashboard-demo stable/kubernetes-dashboard --set fullnameOverride="dashboard"'
}

function install_helm_three(){
    curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
    sudo apt-get install apt-transport-https --yes
    echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
    sudo apt-get update -y
    sudo apt-get install helm -y
}

function install_pure_storage_pso() { #  Install the Pure Storage Orchestrator for Kubernetes.
    helm repo add pure http://purestorage.github.io/helm-charts
    helm repo update
    helm search repo pure-csi
}

function clone_helm_chart() { #  Create the values.yaml file, then tell end user to update.
    yum install git rsync -y
    git clone https://github.com/purestorage/helm-charts.git
    echo "[*] Change directory to helm-charts/operator-csi-plugin and update the values.yaml file with:"
    echo "        Your FlashArray and FlashBlade API credentials and IPv4s"
    echo "        fexPath: /usr/libexec/kubernetes/kubelet-plugins/volume/exec"
    echo "        sanType: ISCSI or FC"
    echo "        pureBackend: block or file"
    echo "        Delete anything not being used."
    echo ""
    mv container_toolkit.sh helm-charts/operator-csi-plugin
    echo "Then run container_toolkit.sh --PSO-kube OR --PSO-helm, not both."
}

function install_pso_plugin_kube() { #  Install the plugin using values.yaml
    if [ $(pwd | sed 's#/#\ #g' | awk '{print $NF}') != "operator-csi-plugin" ]; then 
        echo "Please change working directory to /path/to/helm-charts/operator-csi-plugin"
        exit
    fi
    ./install.sh --namespace=pure-csi-operator --orchestrator=k8s -f values.yaml
    echo "Kubernetes install done."
}

function install_pso_plugin_helm() {
    if [ $(pwd | sed 's#/#\ #g' | awk '{print $NF}') != "operator-csi-plugin" ]; then 
        echo "Please change working directory to /path/to/helm-charts/operator-csi-plugin"
        exit
    fi
    helm install --name pure-storage-driver pure/pure-csi --namespace pso-operator -f values.yaml
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
        #install_docker
        start_enable_docker
        test_docker
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
	install_containerd
	containerd_use_systemd
	restart_enable_containerd
	add_kubernetes_repo
	install_kube_commands
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
    --PSO-init)
        _run_as_root
        install_pure_storage_pso
        clone_helm_chart
        ;;
    --PSO-kube)
        _run_as_root
        install_pso_plugin_kube
        ;;
    --PSO-helm)
        _run_as_root
        install_pso_plugin_helm
        ;;
    --rancher)
        echo 'Needs Testing'
        exit
        _run_as_root
        cleanup_docker
        install_dependencies
        #install_docker
        start_enable_docker
        test_docker
        set_hostname
        configure_master_firewall
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
