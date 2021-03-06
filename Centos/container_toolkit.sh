#!/bin/bash


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
    echo '                      bash centos7_container_toolkit.sh -m'
    echo ''
    echo '[*] --worker-node     Install Kubernetes WORKER NODE and Docker'
    echo '                      bash centos7_container_toolkit.sh --node'
    echo ''
    echo '[*] --docker     Install ONLY Docker.'
    echo '                 bash centos7_container_toolkit.sh --docker'
    echo ''
    echo '[*] --rancher    Install a ONLY Rancher constainer.'
    echo '                 bash centos7_container_toolkit.sh --rancher'
    echo ''
    echo '[*] --helm       Apply this option to install helm.'
    echo '                 bash centos7_container_toolkit.sh --helm'
    echo ''
    echo '[*] --PSO-init   After Kubernetes is up, run this first to install Pure Storage PSO.'
    echo '                 bash centos7_container_toolkit.sh --PSO-init'
    echo ''
    echo '    >>> --PSO-kube OR --PSO-helm, not both.'
    echo ''
    echo '[*] --PSO-kube   After PSO-init ws ran, run this to install PSO into kubectl.'
    echo '                 bash centos7_container_toolkit.sh --PSO-kube'
    echo ''
    echo '[*] --PSO-helm   After PSO-init ws ran run this to install PSO into helm.'
    echo '                 bash centos7_container_toolkit.sh --PSO-helm'
    echo ''
    echo '[*] --clean      Clean up Kubernetes WORKER NODES. Typically we should not need this.'
    echo '                 bash centos7_container_toolkit.sh --clean'
    echo ''
    exit
}


function cleanup_docker() {
    # Cleanup any currently installed docker package.
    echo '[*] Removing old Docker packages.'
    yum remove docker \
        docker-client \
        docker-client-latest \
        docker-common \
        docker-latest \
        docker-latest-logrotate \
        docker-logrotate \
        docker-engine
}

function setup_repo() {
    # Setup packages for docker.
    echo '[*] Installing packages to support Docker.'
    yum install -y yum-utils device-mapper-persistent-data lvm2 wget
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
}


function install_docker() {
    # Install docker. Retry until the key imports.
    echo '[*] Installing Docker.'
    while [ "$(/usr/bin/which docker)" == "" ]; do
        yum install -y docker-ce docker-ce-cli containerd.io
        sleep 5
    done
}

function start_enable_docker() {
    # Start and enable docker in systemd.
    echo '[*] Starting and enabling Docker.'
    systemctl start docker
    systemctl enable docker
}

function test_docker() {
    # Verify docker is running
    echo '[*] Testing Docker.'
    docker run hello-world
}

function set_hostname() {
    echo "$(ifconfig | grep eth0 -A1 | grep inet | awk '{print $2}')" "$(hostnamectl --static)" >> /etc/hosts
}

function disable_selinux() {
    # Disable SELinux since kubernetes does nto support.
    echo '[*] Disabling SELinux'
    setenforce 0
    sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
    echo '[*] Status for SELinux:'
    getenforce
}

function enable_br_netfilter() {
    # Kernel module enabled so packets traversing the bridge
    # are processed through iptables. Allows nodes to communicate.
    echo '[*] Enabling br_netfilter kernel module.'
    modprobe br_netfilter
}

function enable_bridge_iptables() {
    # Reboots do not like this, run after the reboot.
    echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables
}

function disable_swap() {
    # Disable swap and comment out from /etc/fstab
    echo '[*] Disabling SWAP and commenting out fstab.'
    /sbin/swapoff -av
    edit_swap=$(cat /etc/fstab | awk '{print $1}' | grep swap)
    sed -i "s|$edit_swap|#$edit_swap|g" /etc/fstab
    cat /etc/fstab | grep swap
}

function install_kubernetes() {
    # Set kubernetes repo and install kubernetes
    cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
        https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
    yum install -y kubelet kubeadm kubectl
    systemctl start docker && systemctl enable docker
    systemctl start kubelet && systemctl enable kubelet
}

function configure_master_firewall() {
    # Update firewall to allow inbound traffic.
    firewall-cmd --permanent --add-port=80/tcp
    firewall-cmd --permanent --add-port=443/tcp
    firewall-cmd --permanent --add-port=22/tcp
    firewall-cmd --permanent --add-port=2376/tcp
    firewall-cmd --permanent --add-port=2379/tcp
    firewall-cmd --permanent --add-port=2380/tcp
    firewall-cmd --permanent --add-port=4789/udp
    firewall-cmd --permanent --add-port=6443/tcp
    firewall-cmd --permanent --add-port=6783-6784/udp
    firewall-cmd --permanent --add-port=8472/udp
    firewall-cmd --permanent --add-port=9099/tcp
    firewall-cmd --permanent --add-port=10250/tcp
    firewall-cmd --permanent --add-port=10251/tcp
    firewall-cmd --permanent --add-port=10252/tcp
    firewall-cmd --permanent --add-port=10254/tcp
    firewall-cmd --permanent --add-port=10255/tcp
    firewall-cmd --permanent --add-port=30000-32767/tcp
    firewall-cmd --permanent --add-port=30000-32767/udp
    firewall-cmd --add-masquerade --permanent
    firewall-cmd --reload
}

function configure_node_firewall () {
    # Update firewall to allow inbound traffic.
    firewall-cmd --permanent --add-port=80/tcp
    firewall-cmd --permanent --add-port=443/tcp
    firewall-cmd --permanent --add-port=22/tcp
    firewall-cmd --permanent --add-port=2376/tcp
    firewall-cmd --permanent --add-port=2379/tcp
    firewall-cmd --permanent --add-port=2380/tcp
    firewall-cmd --permanent --add-port=4789/udp
    firewall-cmd --permanent --add-port=6443/tcp
    firewall-cmd --permanent --add-port=6783-6784/udp
    firewall-cmd --permanent --add-port=8472/udp
    firewall-cmd --permanent --add-port=9099/tcp
    firewall-cmd --permanent --add-port=10250/tcp
    firewall-cmd --permanent --add-port=10251/tcp
    firewall-cmd --permanent --add-port=10252/tcp
    firewall-cmd --permanent --add-port=10254/tcp
    firewall-cmd --permanent --add-port=10255/tcp
    firewall-cmd --permanent --add-port=30000-32767/tcp
    firewall-cmd --permanent --add-port=30000-32767/udp
    firewall-cmd --add-masquerade --permanent
    firewall-cmd --reload
}

function update_bridge() {
    echo 'net.bridge.bridge-nf-call-ip6tables = 1' >> /etc/sysctl.conf
    echo 'net.bridge.bridge-nf-call-iptables = 1' >> /etc/sysctl.conf
    sysctl -p
}

function set_cgroup_driver() {
    # Update cgroup driver for kubernetes
    echo '[*] Verify Docker cgroupfs'
    docker info | grep -i cgroup
    echo '[*] Updating Docker to use same cgroup.'
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF
    mkdir -p /etc/systemd/system/docker.service.d
    systemctl daemon-reload
    systemctl restart docker
    systemctl restart kubelet
}


function api_server_master_calico() {
    # Beginning of Master node setup.
    echo '[*] Starting Master node.'
    kubeadm init #--pod-network-cidr=192.168.0.0/16
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
}


function install_calico_network_policy() {
    # Install the calico pod network.
    curl https://docs.projectcalico.org/v3.9/manifests/calico.yaml -O
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

function install_tiller() {
    # Install for Tiller and Helm from https://devopscube.com/install-configure-helm-kubernetes/
    helm init --service-account=tiller --history-max 30
    sleep 5
    kubectl get deployment tiller-deploy -n kube-system
}

function install_helm_chart() {
    echo '[*] Updating firewall and installing helm dashboard.'
    firewall-cmd --permanent --add-port=8443/tcp
    echo '[*] Add nodes to your cluster, this will allow Tiller to deploy.'
    echo '[*] Once the tiller container deploys, run both commands:'
    echo '        helm install stable/kubernetes-dashboard --name dashboard-demo'
    echo '        helm upgrade dashboard-demo stable/kubernetes-dashboard --set fullnameOverride="dashboard"'
}

function install_helm_three(){
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    helm repo add stable https://kubernetes-charts.storage.googleapis.com/
    helm repo update
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
    mv centos7_container_toolkit.sh helm-charts/operator-csi-plugin
    echo "Then run centos7_container_toolkit.sh --PSO-kube OR --PSO-helm, not both."
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
        setup_repo
        install_docker
        start_enable_docker
        test_docker
        ;;
    --master-calico)
        _run_as_root
        cleanup_docker
        setup_repo
        install_docker
        start_enable_docker
        test_docker
        set_hostname
        disable_selinux
        enable_br_netfilter
        enable_bridge_iptables
        disable_swap
        install_kubernetes
        configure_master_firewall
        update_bridge
        set_cgroup_driver
        api_server_master_calico
        install_calico_network_policy
        install_calicoctl
        ;;
    --worker-node)
        _run_as_root
        cleanup_docker
        setup_repo
        install_docker
        start_enable_docker
        test_docker
        set_hostname
        disable_selinux
        enable_br_netfilter
        enable_bridge_iptables
        disable_swap
        install_kubernetes
        configure_node_firewall
        update_bridge
        set_cgroup_driver
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
        _run_as_root
        cleanup_docker
        setup_repo
        install_docker
        start_enable_docker
        test_docker
        set_hostname
        configure_master_firewall
        install_rancher
        ;;
    --clean)
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
