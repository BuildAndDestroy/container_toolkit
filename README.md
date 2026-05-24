# container_toolkit

Scripts and manifests to stand up Kubernetes clusters on **Ubuntu servers** and **Raspberry Pi 4** boards. Both installers use **Calico** for pod networking (`192.168.0.0/16`) and configure the control-plane node to **run workloads**, not just the API.

## Choose your platform

| | Ubuntu | Raspberry Pi 4 |
|---|--------|----------------|
| **Script** | [`Ubuntu/container_toolkit.sh`](Ubuntu/container_toolkit.sh) | [`raspberry_pi/rpi_container_toolkit.sh`](raspberry_pi/rpi_container_toolkit.sh) |
| **Stack** | kubeadm + containerd + Calico | k3s + Calico |
| **OS** | Ubuntu 22.04 / 24.04 LTS (64-bit) | Raspberry Pi OS Lite **64-bit** |
| **Master flag** | `--master-calico` | `--master-k3s` |
| **Worker flag** | `--worker-node` then `kubeadm join` | `--worker-k3s --server … --token …` |
| **Kubeconfig** | `~/.kube/config` | `/etc/rancher/k3s/k3s.yaml` |

## Quick start

### Ubuntu (kubeadm)

```bash
git clone <this-repo>
cd container_toolkit/Ubuntu
sudo bash container_toolkit.sh --master-calico
# Save the printed kubeadm join command

# On each worker:
sudo bash container_toolkit.sh --worker-node
sudo kubeadm join ...   # paste command from master
```

### Raspberry Pi (k3s, 3-node example)

```bash
cd container_toolkit/raspberry_pi
# On pi-master (reboot if script asks for cgroup boot params, then re-run):
sudo bash rpi_container_toolkit.sh --master-k3s

# On pi-worker1 and pi-worker2:
sudo bash rpi_container_toolkit.sh --worker-k3s --server 192.168.1.10 --token '<from master>'
```

Verify on the control plane:

```bash
# Ubuntu
kubectl get nodes -o wide && kubectl get pods -A

# Raspberry Pi
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes -o wide && kubectl get pods -A
```

## Defaults (both platforms)

| Setting | Ubuntu | Raspberry Pi |
|---------|--------|----------------|
| Kubernetes | `v1.32` via [pkgs.k8s.io](https://pkgs.k8s.io) | k3s latest from [get.k3s.io](https://get.k3s.io) |
| Calico | `v3.31.2` | `v3.31.2` |
| Pod CIDR | `192.168.0.0/16` | `192.168.0.0/16` (`cluster-cidr`) |

Override examples:

```bash
# Ubuntu
sudo K8S_MINOR=v1.32 CALICO_VERSION=v3.31.2 bash container_toolkit.sh --master-calico

# Raspberry Pi
sudo K3S_VERSION=v1.31.5+k3s1 CALICO_VERSION=v3.31.2 bash rpi_container_toolkit.sh --master-k3s
```

## Repository layout

| Path | Description |
|------|-------------|
| `Ubuntu/container_toolkit.sh` | kubeadm cluster installer |
| `raspberry_pi/rpi_container_toolkit.sh` | k3s cluster installer |
| `raspberry_pi/secure_pi.sh` | Optional Pi hardening (SSH, firewall, etc.) |
| `cert-manager/` | ClusterIssuer manifests for TLS |
| `metallb/` | MetalLB L2 config and sample service |
| `traefik/` | Traefik notes |
| `docker-registry/` | In-cluster registry deployment |
| `prometheus_grafana/` | Monitoring stack notes |
| `user_administration/` | User auth helper scripts |

---

# Ubuntu — `container_toolkit.sh`

Run as **root** (`sudo`). Calico networking is installed via the Tigera operator.

```bash
cd Ubuntu
sudo bash container_toolkit.sh --help
```

### Flags

| Flag | Description |
|------|-------------|
| `--master-calico` | Control plane + Calico; schedules pods on this node |
| `--worker-node` | Install prerequisites; join with `kubeadm join` from master |
| `--docker` | Install Docker only |
| `--rancher` | Run Rancher in Docker (standalone) |
| `--helm` | Install Helm 3 |
| `--clean` | Reset Kubernetes/container state (destructive) |

### Control plane

```bash
sudo bash container_toolkit.sh --master-calico
```

When finished, the script prints a **`kubeadm join ...`** command for workers.

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

Example:

```
NAME         STATUS   ROLES           AGE   VERSION
k8s-master   Ready    control-plane   10m   v1.32.x
```

### Workers

On each worker host:

```bash
sudo bash container_toolkit.sh --worker-node
```

On the master (if you need a new join command):

```bash
kubeadm token create --print-join-command
```

Run the full join output on each worker as root.

```
NAME          STATUS   ROLES           AGE   VERSION
k8s-master    Ready    control-plane   15m   v1.32.x
k8-worker-1   Ready    <none>          5m    v1.32.x
k8-worker-2   Ready    <none>          5m    v1.32.x
```

### Helm (optional)

```bash
sudo bash container_toolkit.sh --helm
```

### Reset a node

```bash
sudo bash container_toolkit.sh --clean
```

### Swap after reboot

Ubuntu sometimes re-enables swap after reboot. If nodes are `NotReady`:

```bash
sudo swapoff -a
sudo systemctl restart kubelet
```

### Docker image (help only)

```bash
docker build -t container_toolkit .
docker run --rm -it container_toolkit /opt/container_toolkit/Ubuntu/container_toolkit.sh -h
```

---

# Raspberry Pi — `rpi_container_toolkit.sh`

Use **k3s** on real hardware (not [k3d](https://k3d.io), which runs k3s inside Docker on a desktop). Recommended: **3× Pi 4** with **8 GB** RAM and **64-bit** Raspberry Pi OS Lite.

```bash
cd raspberry_pi
sudo bash rpi_container_toolkit.sh --help
```

### Flags

| Flag | Description |
|------|-------------|
| `--master-k3s` | k3s server + Calico; runs workloads on this node |
| `--worker-k3s` | Join as agent (`--server` + `--token`, or env vars) |
| `--master-k3s-docker` / `--worker-k3s-docker` | Use Docker as the runtime |
| `--helm` | Install Helm 3 |
| `--openfaas-master` | Optional OpenFaaS |
| `--arkade-master` | Optional arkade CLI |
| `--clean` | Uninstall k3s (destructive) |

Legacy aliases: `--rancherk3s-master`, `--rancherk3s-worker`, `--rancherk3s-*-docker`.

### Three-node layout (example)

| Node | Role | Example IP |
|------|------|------------|
| `pi-master` | k3s server | `192.168.1.10` |
| `pi-worker1` | k3s agent | `192.168.1.11` |
| `pi-worker2` | k3s agent | `192.168.1.12` |

Use static IPs or DHCP reservations.

### 1. Prepare each Pi

1. Flash **64-bit** Raspberry Pi OS Lite; enable SSH.
2. Set hostnames (`pi-master`, `pi-worker1`, `pi-worker2`).
3. Optional: `sudo bash secure_pi.sh --raspbian`
4. First install may require a **reboot** after cgroup boot params are added to `cmdline.txt`; re-run the script after reboot.

### 2. Control plane (`pi-master`)

```bash
sudo bash rpi_container_toolkit.sh --master-k3s
```

The script disables swap, installs k3s with Flannel off, applies Calico, and prints a worker join command.

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes -o wide
kubectl get pods -A
```

### 3. Workers

```bash
sudo bash rpi_container_toolkit.sh --worker-k3s \
  --server 192.168.1.10 \
  --token 'K10...::server:...'
```

Or:

```bash
export K3S_SERVER_URL=https://192.168.1.10:6443
export K3S_TOKEN='K10...::server:...'
sudo -E bash rpi_container_toolkit.sh --worker-k3s
```

Token on master: `/var/lib/rancher/k3s/server/node-token`

```
NAME         STATUS   ROLES                  AGE   VERSION
pi-master    Ready    control-plane,master   15m   v1.31.x+k3s1
pi-worker1   Ready    <none>                 5m    v1.31.x+k3s1
pi-worker2   Ready    <none>                 5m    v1.31.x+k3s1
```

### Optional add-ons (master)

```bash
sudo bash rpi_container_toolkit.sh --helm
sudo bash rpi_container_toolkit.sh --openfaas-master
sudo bash rpi_container_toolkit.sh --arkade-master
```

### Reset a Pi

```bash
sudo bash rpi_container_toolkit.sh --clean
```

### Pi notes

- **Reboot:** Script exits with instructions when cgroup lines are added; it does not force reboot.
- **Memory:** Calico on three Pi 4 nodes is fine; be cautious running heavy workloads on 4 GB boards.
- **Traefik:** Disabled by default (`--disable=traefik`); add your own ingress if needed.
- **Sample manifests:** `raspberry_pi/example_yaml_deployment.yaml`, `raspberry_pi/traefik.yaml`

---

## After the cluster is up

Install add-ons from this repo as needed:

- TLS: `cert-manager/README.md`
- LoadBalancer (on-prem): `metallb/`
- Registry: `docker-registry/README.md`
- Monitoring: `prometheus_grafana/README.md`
