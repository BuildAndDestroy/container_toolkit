#!/bin/bash
#
# Ubuntu kubeadm + containerd + Calico installer.
# Run as root on each node; use --master-calico on the control plane and
# --worker-node on additional nodes, then join workers with the printed command.
#

set -o pipefail

K8S_MINOR="${K8S_MINOR:-v1.32}"
CALICO_VERSION="${CALICO_VERSION:-v3.31.2}"
POD_NETWORK_CIDR="${POD_NETWORK_CIDR:-192.168.0.0/16}"
CRI_SOCKET="${CRI_SOCKET:-unix:///var/run/containerd/containerd.sock}"

function _run_as_root() {
    if [[ $(id -u) != 0 ]]; then
        echo '[*] Must be run as root (sudo bash container_toolkit.sh ...).'
        exit 1
    fi
}

function _help_menu() {
    echo '[*] Help Menu:'
    echo ''
    echo '[*] --master-calico   Control plane + Calico (schedules workloads on this node).'
    echo '                      sudo bash container_toolkit.sh --master-calico'
    echo ''
    echo '[*] --worker-node     Prepare a worker; join with the command printed on the master.'
    echo '                      sudo bash container_toolkit.sh --worker-node'
    echo ''
    echo '[*] --docker          Install Docker only (get.docker.com).'
    echo '                      sudo bash container_toolkit.sh --docker'
    echo ''
    echo '[*] --rancher         Run Rancher in Docker (standalone, not in-cluster).'
    echo '                      sudo bash container_toolkit.sh --rancher'
    echo ''
    echo '[*] --helm            Install Helm 3.'
    echo '                      sudo bash container_toolkit.sh --helm'
    echo ''
    echo '[*] --clean           Reset node Kubernetes/Docker state (destructive).'
    echo '                      sudo bash container_toolkit.sh --clean'
    echo ''
    echo "Environment overrides: K8S_MINOR=${K8S_MINOR} CALICO_VERSION=${CALICO_VERSION} POD_NETWORK_CIDR=${POD_NETWORK_CIDR}"
    exit 0
}

function cleanup_docker() {
    echo '[*] Removing conflicting Docker/containerd packages.'
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
}

function install_dependencies() {
    echo '[*] Installing base packages.'
    apt-get update -y
    apt-get install -y apt-transport-https ca-certificates curl gnupg software-properties-common nfs-common ethtool
}

function docker_install_script() {
    echo '[*] Installing Docker via get.docker.com.'
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh
}

function set_hostname() {
    local node_ip
    node_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -z "${node_ip}" ]]; then
        node_ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    fi
    if [[ -n "${node_ip}" ]]; then
        local hostname_short
        hostname_short=$(hostnamectl --static 2>/dev/null || hostname -s)
        if ! grep -qE "[[:space:]]${hostname_short}([[:space:]]|$)" /etc/hosts; then
            echo "${node_ip} ${hostname_short}" >> /etc/hosts
        fi
        echo "[*] /etc/hosts: ${node_ip} ${hostname_short}"
    else
        echo '[*] Warning: could not detect node IP for /etc/hosts.'
    fi
}

function disable_swap() {
    echo '[*] Disabling swap (required for kubelet).'
    swapoff -a 2>/dev/null || true
    sed -i.bak-k8s '/[[:space:]]swap[[:space:]]/s/^\([^#]\)/#\1/' /etc/fstab
    # Prevent cloud images from re-enabling swap on boot (common on Ubuntu 22.04+).
    if [[ -f /etc/cloud/cloud.cfg ]]; then
        sed -i.bak-k8s 's/^\([[:space:]]*- swap\)/#\1/' /etc/cloud/cloud.cfg 2>/dev/null || true
    fi
}

function load_kernel_modules() {
    tee /etc/modules-load.d/kubernetes.conf >/dev/null <<EOF
overlay
br_netfilter
EOF
    modprobe overlay 2>/dev/null || true
    modprobe br_netfilter 2>/dev/null || true
}

function update_bridge() {
    tee /etc/sysctl.d/kubernetes.conf >/dev/null <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
    sysctl --system >/dev/null
}

function enable_containerd_repo() {
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
        | tee /etc/apt/sources.list.d/docker.list >/dev/null
    apt-get update -y
}

function install_containerd_package() {
    echo '[*] Installing containerd.'
    apt-get install -y containerd.io
}

function configure_containerd() {
    echo '[*] Configuring containerd (systemd cgroups + Kubernetes pause image).'
    mkdir -p /etc/containerd
    containerd config default | tee /etc/containerd/config.toml >/dev/null
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    local pause_image
    pause_image=$(kubeadm config images list 2>/dev/null | grep pause | head -n1 || true)
    if [[ -n "${pause_image}" ]]; then
        sed -i "s|sandbox_image = \".*\"|sandbox_image = \"${pause_image}\"|" /etc/containerd/config.toml
    fi
}

function restart_enable_containerd() {
    systemctl restart containerd
    systemctl enable containerd
}

function add_kubernetes_repo() {
    echo "[*] Adding Kubernetes apt repo (${K8S_MINOR})."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
        | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
        | tee /etc/apt/sources.list.d/kubernetes.list
    chmod 644 /etc/apt/sources.list.d/kubernetes.list
}

function install_kube_commands() {
    apt-get update -y
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
}

function restart_kubelet_services() {
    systemctl restart kubelet
    systemctl enable kubelet
}

function init_kubernetes_images() {
    echo '[*] Pre-pulling Kubernetes images.'
    kubeadm config images pull --cri-socket="${CRI_SOCKET}"
}

function prepare_node_common() {
    cleanup_docker
    install_dependencies
    set_hostname
    disable_swap
    load_kernel_modules
    update_bridge
    enable_containerd_repo
    install_containerd_package
    add_kubernetes_repo
    install_kube_commands
    configure_containerd
    restart_enable_containerd
    restart_kubelet_services
    init_kubernetes_images
}

function api_server_master_calico() {
    echo "[*] Initializing control plane (pod CIDR ${POD_NETWORK_CIDR})."
    kubeadm init \
        --pod-network-cidr="${POD_NETWORK_CIDR}" \
        --cri-socket="${CRI_SOCKET}"

    mkdir -p "${HOME}/.kube"
    cp -i /etc/kubernetes/admin.conf "${HOME}/.kube/config"
    chown "$(id -u):$(id -g)" "${HOME}/.kube/config"
    export KUBECONFIG="${HOME}/.kube/config"
}

function allow_master_scheduling() {
    echo '[*] Allowing workloads on the control-plane node.'
    kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null \
        || kubectl taint nodes --all node-role.kubernetes.io/master:NoSchedule- 2>/dev/null \
        || true
}

function install_calico_network_policy() {
    local workdir
    workdir=$(mktemp -d)

    echo "[*] Installing Calico ${CALICO_VERSION}."
    curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml" \
        -o "${workdir}/tigera-operator.yaml"
    curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml" \
        -o "${workdir}/custom-resources.yaml"

    # Calico default pool is 192.168.0.0/16; keep it aligned with kubeadm --pod-network-cidr.
    if [[ "${POD_NETWORK_CIDR}" != "192.168.0.0/16" ]]; then
        sed -i "s|cidr: 192.168.0.0/16|cidr: ${POD_NETWORK_CIDR}|" "${workdir}/custom-resources.yaml"
    fi

    kubectl apply -f "${workdir}/tigera-operator.yaml"
    kubectl apply -f "${workdir}/custom-resources.yaml"

    echo '[*] Waiting for Calico pods to become ready (up to 10 minutes).'
    kubectl wait --for=condition=Ready pods -l k8s-app=calico-node -n calico-system --timeout=600s 2>/dev/null \
        || kubectl wait --for=condition=Ready pods -l k8s-app=calico-node -n kube-system --timeout=600s 2>/dev/null \
        || echo '[*] Warning: timed out waiting for calico-node; check: kubectl get pods -A'
    rm -rf "${workdir}"
}

function set_felix_loose_true() {
    echo '[*] Setting FELIX_IGNORELOOSERPF on calico-node (if present).'
    kubectl -n calico-system set env daemonset/calico-node FELIX_IGNORELOOSERPF=true 2>/dev/null \
        || kubectl -n kube-system set env daemonset/calico-node FELIX_IGNORELOOSERPF=true 2>/dev/null \
        || true
}

function print_join_instructions() {
  echo ''
  echo '================================================================================'
  echo '[*] Control plane is up. On each worker node, run:'
  echo ''
  kubeadm token create --print-join-command 2>/dev/null || true
  echo ''
  echo '[*] Verify on this node:'
  echo '    kubectl get nodes -o wide'
  echo '    kubectl get pods -A'
  echo '================================================================================'
  echo ''
}

function print_worker_ready() {
  echo ''
  echo '================================================================================'
  echo '[*] Worker prerequisites are installed.'
  echo '    On the MASTER, run:  kubeadm token create --print-join-command'
  echo '    Then run that full join command on THIS node as root.'
  echo '================================================================================'
  echo ''
}

function install_rancher() {
    echo '[*] Starting Rancher container (ports 80/443).'
    docker run --privileged -d --restart=unless-stopped -p 80:80 -p 443:443 rancher/rancher
}

function cleanup_workers() {
    echo '[*] Resetting Kubernetes and container runtime state.'
    kubeadm reset -f 2>/dev/null || true
    docker rm -f $(docker ps -qa) 2>/dev/null || true
    docker volume rm $(docker volume ls -q) 2>/dev/null || true
    local cleanupdirs="/var/lib/etcd /etc/kubernetes /etc/cni /opt/cni /var/lib/cni /var/run/calico /opt/rke"
    for dir in ${cleanupdirs}; do
        echo "Removing ${dir}"
        rm -rf "${dir}"
    done
    iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X 2>/dev/null || true
    ipvsadm --clear 2>/dev/null || true
}

function install_helm_three() {
    curl -fsSL https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg >/dev/null
    apt-get install -y apt-transport-https
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" \
        | tee /etc/apt/sources.list.d/helm-stable-debian.list
    apt-get update -y
    apt-get install -y helm
}

case "$1" in
    --docker)
        _run_as_root
        cleanup_docker
        install_dependencies
        docker_install_script
        ;;
    --master-calico)
        _run_as_root
        prepare_node_common
        api_server_master_calico
        install_calico_network_policy
        allow_master_scheduling
        set_felix_loose_true
        print_join_instructions
        ;;
    --worker-node)
        _run_as_root
        prepare_node_common
        print_worker_ready
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
        _run_as_root
        cleanup_workers
        ;;
    -h|--help)
        _help_menu
        ;;
    *)
        _help_menu
        ;;
esac
