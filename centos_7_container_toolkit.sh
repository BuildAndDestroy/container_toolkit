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
    echo '[*] -mf Install Kubernetes MASTER NODE Flannel and Docker.'
    echo '        bash centos_7_container_toolkit.sh -m'
    echo ''
    echo '[*] -mc Install Kubernetes MASTER NODE Calico and Docker.'
    echo '        bash centos_7_container_toolkit.sh -m'
    echo ''
    echo '[*] -n Install Kubernetes WORKER NODE and Docker'
    echo '        bash centos_7_container_toolkit.sh -n'
    echo ''
    echo '[*] --helm Apply this option to install helm.'
    echo '        bash centos_7_container_toolkit.sh --helm'
    echo ''
    echo '[*] -d Install ONLY Docker'
    echo '        bash centos_7_container_toolkit.sh -d'
    echo ''
    echo '[*] -r Install a ONLY Rancher host.'
    echo '        bash centos_7_container_toolkit.sh -r'
    echo ''
    echo '[*] -c Clean up Kubernetes WORKER NODES. Typically we should not need this.'
    echo '        bash centos_7_container_toolkit.sh -c'
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

function api_server_master() {
    # Beginning of Master node setup.
    echo '[*] Starting Master node.'
    kubeadm init --pod-network-cidr=10.244.0.0/16 # --authorization-mode=RBAC
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
}

function install_flannel_network() {
    # Install flannel network for kubernetes.
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
}

function install_calico_policy() {
    curl https://docs.projectcalico.org/v3.9/manifests/canal.yaml -O
    #POD_CIDR="<your-pod-cidr>" sed -i -e "s?10.244.0.0/16?$POD_CIDR?g" canal.yaml
    kubectl apply -f canal.yaml
}

function install_calico_network_policy() {
    curl https://docs.projectcalico.org/v3.9/manifests/calico.yaml -O
    # POD_CIDR="10.244.0.0" sed -i -e "s?192.168.0.0?$POD_CIDR?g" calico.yaml
    sed -i -e "s?192.168.0.0?10.244.0.0?g" calico.yaml 
    kubectl apply -f calico.yaml
    echo '[*] Check pods with "kubectl get pods --all-namespaces". Once done, install --helm.'
    kubectl get pods --all-namespaces
}

function join_node_to_master() {
    # Request mast ip and token to connect node to master.
    echo "Please copy/paste Master node IP:"
    read -r -p ">>> " ipValue
    echo "Please copy/paste Master token:"
    read -r -p ">>> " tokenValue
    echo 'Please copy/paste Master discovery-token-ca-cert-hash:'
    read -r -p ">>> " discoveryToken
    echo "kubeadm join --token "$tokenValue" "$ipValue":6443 --discovery-token-ca-cert-hash "$discoveryToken""
    kubeadm join --token $tokenValue $ipValue:6443 --discovery-token-ca-cert-hash $discoveryToken
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

function install_helm() {
    echo "[*] Installing helm."
    curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get > install-helm.sh
    chmod 755 install-helm.sh
    ./install-helm.sh
}

function install_tiller() {
    # kubectl -n kube-system create serviceaccount tiller
    kubectl create serviceaccount --namespace kube-system tiller
    kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
    kubectl patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'
    helm init --service-account=kube-system:tiller
    # kubectl taint nodes --all node-role.kubernetes.io/master-
}

function install_helm_chart() {
    echo '[*] Updating firewall and installing helm dashboard.'
    firewall-cmd --permanent --add-port=8443/tcp
    echo '[*] Add nodes to your cluster, this will allow Tiller to deploy.'
    echo '[*] Once the tiller container deploys, run both commands:'
    echo '        helm install stable/kubernetes-dashboard --name dashboard-demo'
    echo '        helm upgrade dashboard-demo stable/kubernetes-dashboard --set fullnameOverride="dashboard"'
}

################################################################################################
#    To Do List:                                                                               #
#      Enable RBAC                                                                             #
#        https://docs.bitnami.com/kubernetes/how-to/configure-rbac-in-your-kubernetes-cluster/ #
#      Install Tiller with correct role.                                                       #
#      Install Helm with correct role.                                                         #
################################################################################################


############################
# Functions to be executed #
############################


case "$1" in
    -d)
        _run_as_root
        cleanup_docker
        setup_repo
        install_docker
        start_enable_docker
        test_docker
        ;;
    -mf)
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
        api_server_master
        install_flannel_network
        ;;
    -mc)
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
        api_server_master
        install_calico_network_policy
        ;;
    -n)
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
        echo '[*] Currently needs work!'
        # install_helm
        # install_tiller
        # install_helm_chart
        ;;
    -r)
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
    -c)
        cleanup_workers
        ;;
    -h)
        _help_menu
        ;;
    *)
        _help_menu
        ;;
esac
