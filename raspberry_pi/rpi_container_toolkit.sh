#!/bin/bash
#
# Raspberry Pi k3s + Calico cluster installer (Pi 4, 64-bit OS recommended).
# Run as root on each node: one --master-k3s, then --worker-k3s on the others.
#

set -o pipefail

K3S_VERSION="${K3S_VERSION:-}"   # empty = latest stable from get.k3s.io
CALICO_VERSION="${CALICO_VERSION:-v3.31.2}"
CLUSTER_CIDR="${CLUSTER_CIDR:-192.168.0.0/16}"
K3S_SERVER_URL="${K3S_SERVER_URL:-}"
K3S_TOKEN="${K3S_TOKEN:-}"

function run_as_root() {
    if [[ $(id -u) != 0 ]]; then
        echo '[*] Must be run as root (sudo bash rpi_container_toolkit.sh ...).'
        exit 1
    fi
}

function _help_menu() {
    echo '[*] Help Menu — Raspberry Pi k3s cluster'
    echo ''
    echo '[*] --master-k3s       Control plane + Calico (runs workloads on this node).'
    echo '                      sudo bash rpi_container_toolkit.sh --master-k3s'
    echo ''
    echo '[*] --worker-k3s       Join cluster as agent (provide token + server IP).'
    echo '                      sudo bash rpi_container_toolkit.sh --worker-k3s --server 192.168.1.10 --token <token>'
    echo '                      Or set K3S_SERVER_URL and K3S_TOKEN before running.'
    echo ''
    echo '[*] --master-k3s-docker   Same as master but use Docker as the runtime.'
    echo '[*] --worker-k3s-docker   Same as worker but use Docker as the runtime.'
    echo ''
    echo '[*] --helm             Install Helm 3 on this node.'
    echo '[*] --openfaas-master  Install OpenFaaS (optional, on master).'
    echo '[*] --arkade-master    Install arkade CLI (optional, on master).'
    echo '[*] --clean            Remove k3s from this node (destructive).'
    echo ''
    echo 'Legacy aliases: --rancherk3s-master, --rancherk3s-worker, --rancherk3s-*-docker'
    echo ''
    echo "Defaults: CALICO_VERSION=${CALICO_VERSION} CLUSTER_CIDR=${CLUSTER_CIDR}"
    echo '          K3S_VERSION=(latest if unset)'
    exit 0
}

function node_ip() {
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -z "${ip}" ]]; then
        ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    fi
    echo "${ip}"
}

function set_hostname_in_hosts() {
    local ip hostname_short
    ip=$(node_ip)
    hostname_short=$(hostnamectl --static 2>/dev/null || hostname -s)
    if [[ -n "${ip}" && -n "${hostname_short}" ]]; then
        if ! grep -qE "[[:space:]]${hostname_short}([[:space:]]|$)" /etc/hosts; then
            echo "${ip} ${hostname_short}" >> /etc/hosts
        fi
        echo "[*] /etc/hosts: ${ip} ${hostname_short}"
    fi
}

function disable_swap() {
    echo '[*] Disabling swap.'
    swapoff -a 2>/dev/null || true
    sed -i.bak-k3s '/[[:space:]]swap[[:space:]]/s/^\([^#]\)/#\1/' /etc/fstab
    if [[ -f /etc/dphys-swapfile ]]; then
        systemctl disable dphys-swapfile 2>/dev/null || true
        systemctl stop dphys-swapfile 2>/dev/null || true
    fi
}

function enable_traffic_forwarding() {
    echo '[*] Enabling IPv4 forwarding.'
    tee /etc/sysctl.d/99-kubernetes.conf >/dev/null <<EOF
net.ipv4.ip_forward = 1
net.ipv4.ip_nonlocal_bind = 1
EOF
    sysctl --system >/dev/null
}

function ensure_cgroup_memory() {
    local cmdline_files=("/boot/firmware/cmdline.txt" "/boot/cmdline.txt")
    local cgroup_opts='cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory'
    local f opts_file changed=0

    for f in "${cmdline_files[@]}"; do
        [[ -f "${f}" ]] || continue
        opts_file="${f}"
        if grep -q 'cgroup_enable=memory' "${f}"; then
            echo "[*] cgroup memory already enabled in ${f}"
            return 0
        fi
        sed -i "s/$/ ${cgroup_opts}/" "${f}"
        echo "[*] Added cgroup options to ${f}"
        changed=1
    done

    if [[ ${changed} -eq 1 ]]; then
        echo '[*] REBOOT REQUIRED for cgroup boot parameters to take effect.'
        echo '    Run: sudo reboot'
        echo '    Then re-run this script on the node.'
        exit 0
    fi

    if [[ -z "${opts_file:-}" ]]; then
        echo '[*] Warning: could not find cmdline.txt; ensure cgroup memory is enabled for k3s.'
    fi
}

function install_base_packages() {
    apt-get update -y
    apt-get install -y curl wget apt-transport-https ca-certificates
}

function k3s_install_env() {
    export K3S_KUBECONFIG_MODE="${K3S_KUBECONFIG_MODE:-644}"
    if [[ -n "${K3S_VERSION}" ]]; then
        export INSTALL_K3S_VERSION="${K3S_VERSION}"
    fi
}

function k3s_master_exec_args() {
    local use_docker="${1:-false}"
    local args ip
    args=(
        server
        --flannel-backend=none
        --disable-network-policy
        --cluster-cidr="${CLUSTER_CIDR}"
        --disable=traefik
    )
    if [[ "${use_docker}" == "true" ]]; then
        args+=(--docker)
    fi
    ip=$(node_ip)
    if [[ -n "${ip}" ]]; then
        args+=(--tls-san="${ip}" --node-ip="${ip}" --advertise-address="${ip}")
    fi
    echo "${args[*]}"
}

function install_k3s_master() {
    local use_docker="${1:-false}"
    k3s_install_env
    local exec_args
    exec_args=$(k3s_master_exec_args "${use_docker}")
    echo "[*] Installing k3s server (${exec_args})"
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="${exec_args}" sh -
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
}

function install_k3s_worker() {
    local use_docker="${1:-false}"
    shift
    resolve_worker_credentials "$@"

    k3s_install_env
    local pi_hostname
    pi_hostname=$(hostname -s)
    local exec_args="agent"
    if [[ "${use_docker}" == "true" ]]; then
        exec_args="agent --docker"
    fi

    echo "[*] Joining k3s cluster at ${K3S_SERVER_URL} as ${pi_hostname}"
    curl -sfL https://get.k3s.io | \
        K3S_URL="${K3S_SERVER_URL}" \
        K3S_TOKEN="${K3S_TOKEN}" \
        K3S_NODE_NAME="${pi_hostname}" \
        INSTALL_K3S_EXEC="${exec_args}" \
        sh -
}

function resolve_worker_credentials() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --server) K3S_SERVER_URL="https://$2:6443"; shift 2 ;;
            --token)  K3S_TOKEN="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "${K3S_SERVER_URL}" ]]; then
        local master_ip
        read -r -p '[*] Master node IP address: ' master_ip
        K3S_SERVER_URL="https://${master_ip}:6443"
    elif [[ "${K3S_SERVER_URL}" != https://* ]]; then
        K3S_SERVER_URL="https://${K3S_SERVER_URL}:6443"
    fi

    if [[ -z "${K3S_TOKEN}" ]]; then
        read -r -p '[*] Node token (from master /var/lib/rancher/k3s/server/node-token): ' K3S_TOKEN
    fi
}

function install_calico() {
    local workdir
    workdir=$(mktemp -d)
    export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

    echo "[*] Installing Calico ${CALICO_VERSION} for k3s."
    curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml" \
        -o "${workdir}/tigera-operator.yaml"
    curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml" \
        -o "${workdir}/custom-resources.yaml"

    if [[ "${CLUSTER_CIDR}" != "192.168.0.0/16" ]]; then
        sed -i "s|cidr: 192.168.0.0/16|cidr: ${CLUSTER_CIDR}|" "${workdir}/custom-resources.yaml"
    fi

    # Required for k3s + Calico (see Tigera k3s quickstart).
    if ! grep -q 'containerIPForwarding' "${workdir}/custom-resources.yaml"; then
        sed -i '/calicoNetwork:/a\    containerIPForwarding: Enabled' "${workdir}/custom-resources.yaml"
    fi

    kubectl apply -f "${workdir}/tigera-operator.yaml"
    kubectl apply -f "${workdir}/custom-resources.yaml"

    echo '[*] Waiting for Calico (up to 10 minutes on Pi hardware).'
    kubectl wait --for=condition=Ready pods -l k8s-app=calico-node -n calico-system --timeout=600s 2>/dev/null \
        || kubectl wait --for=condition=Ready pods -l k8s-app=calico-node -n kube-system --timeout=600s 2>/dev/null \
        || echo '[*] Warning: calico-node not Ready yet; check: kubectl get pods -A'

    rm -rf "${workdir}"
}

function print_master_join_info() {
    local token ip
    token=$(cat /var/lib/rancher/k3s/server/node-token 2>/dev/null || true)
    ip=$(node_ip)
    echo ''
    echo '================================================================================'
    echo '[*] k3s control plane is running.'
    echo ''
    echo '  Kubeconfig:  /etc/rancher/k3s/k3s.yaml'
    echo '  Node token:  /var/lib/rancher/k3s/server/node-token'
    echo ''
    if [[ -n "${token}" && -n "${ip}" ]]; then
        echo '  On each worker Pi, run:'
        echo "    sudo bash rpi_container_toolkit.sh --worker-k3s --server ${ip} --token ${token}"
        echo ''
        echo '  Or manually:'
        echo "    curl -sfL https://get.k3s.io | K3S_URL=https://${ip}:6443 K3S_TOKEN=${token} sh -"
    fi
    echo ''
    echo '  Verify on master:'
    echo '    kubectl get nodes -o wide'
    echo '    kubectl get pods -A'
    echo '================================================================================'
    echo ''
}

function install_docker() {
    echo '[*] Installing Docker.'
    curl -fsSL https://get.docker.com | sh
}

function k3s_uninstall() {
    echo '[*] Removing k3s from this node.'
    if [[ -x /usr/local/bin/k3s-uninstall.sh ]]; then
        /usr/local/bin/k3s-uninstall.sh
    fi
    if [[ -x /usr/local/bin/k3s-agent-uninstall.sh ]]; then
        /usr/local/bin/k3s-agent-uninstall.sh
    fi
}

function install_helm_three() {
    curl -fsSL https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg >/dev/null
    apt-get install -y apt-transport-https
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" \
        | tee /etc/apt/sources.list.d/helm-stable-debian.list
    apt-get update -y
    apt-get install -y helm
}

function install_openfaas() {
    export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
    echo '[*] Installing OpenFaaS (ARM manifests).'
    git clone --depth 1 https://github.com/openfaas/faas-netes.git /tmp/faas-netes 2>/dev/null \
        || true
    curl -sLS https://cli.openfaas.com | sh
    kubectl apply -f /tmp/faas-netes/namespaces.yml
    if [[ -d /tmp/faas-netes/yaml_arm64 ]]; then
        kubectl apply -f /tmp/faas-netes/yaml_arm64/
    elif [[ -d /tmp/faas-netes/yaml_armhf ]]; then
        kubectl apply -f /tmp/faas-netes/yaml_armhf/
    else
        kubectl apply -f /tmp/faas-netes/chart/
    fi
    echo '[*] OpenFaaS gateway often exposed on NodePort 31112 after pods are ready.'
}

function install_arkade() {
    curl -sLS https://dl.get-arkade.dev | sh
}

function prepare_node() {
    install_base_packages
    set_hostname_in_hosts
    disable_swap
    enable_traffic_forwarding
    ensure_cgroup_memory
}

function master_flow() {
    local use_docker="${1:-false}"
    prepare_node
    if [[ "${use_docker}" == "true" ]]; then
        install_docker
    fi
    install_k3s_master "${use_docker}"
    install_calico
    print_master_join_info
}

function worker_flow() {
    local use_docker="${1:-false}"
    shift
    prepare_node
    if [[ "${use_docker}" == "true" ]]; then
        install_docker
    fi
    install_k3s_worker "${use_docker}" "$@"
    echo '[*] Worker joined. Verify from master: kubectl get nodes -o wide'
}

# --- main ---

case "$1" in
    --master-k3s|--rancherk3s-master)
        run_as_root
        master_flow false
        ;;
    --worker-k3s|--rancherk3s-worker)
        run_as_root
        shift
        worker_flow false "$@"
        ;;
    --master-k3s-docker|--rancherk3s-master-docker)
        run_as_root
        master_flow true
        ;;
    --worker-k3s-docker|--rancherk3s-worker-docker)
        run_as_root
        shift
        worker_flow true "$@"
        ;;
    --helm|--helm-master)
        run_as_root
        install_helm_three
        ;;
    --openfaas-master)
        run_as_root
        install_openfaas
        ;;
    --arkade-master)
        run_as_root
        install_arkade
        ;;
    --clean)
        run_as_root
        k3s_uninstall
        ;;
    -h|--help)
        _help_menu
        ;;
    *)
        _help_menu
        ;;
esac
