Automate the install of Kubernetes and Docker.
Calico networking is here to stay.


# Help Menu - Centos 7 and Ubuntu 20.04


```
./container_toolkit.sh -h
[*] Help Menu:

[*] --master-calico   Install Kubernetes MASTER NODE Calico and Docker.
                      ./container_toolkit.sh --master-calico

[*] --worker-node     Install Kubernetes WORKER NODE and Docker
                      ./container_toolkit.sh --worker-node

[*] --docker     Install ONLY Docker.
                 ./container_toolkit.sh --docker

[*] --rancher    Install a ONLY Rancher constainer.
                 ./container_toolkit.sh --rancher

[*] --helm       Apply this option to install helm.
                 ./container_toolkit.sh --helm

[*] --PSO-init   After Kubernetes is up, run this first to install Pure Storage PSO.
                 ./container_toolkit.sh --PSO-init

    >>> --PSO-kube OR --PSO-helm, not both.

[*] --PSO-kube   After PSO-init ws ran, run this to install PSO into kubectl.
                 ./container_toolkit.sh --PSO-kube

[*] --PSO-helm   After PSO-init ws ran run this to install PSO into helm.
                 ./container_toolkit.sh --PSO-helm

[*] --clean      Clean up Kubernetes WORKER NODES. Typically we should not need this.
                 ./container_toolkit.sh --clean
```


# Deploy Kubernetes Master With The Calico Network:

* Run on a CentOS 7 hosts or VM that you want dedicated as Master

```./container_toolkit.sh --master-calico```

* Once done, check your pods:

```
kubectl get pods --all-namespaces

NAMESPACE     NAME                                      READY   STATUS    RESTARTS   AGE
kube-system   calico-kube-controllers-7b9dcdcc5-dsm52   1/1     Running   0          74s
kube-system   calico-node-q9g9f                         1/1     Running   0          75s
kube-system   coredns-5644d7b6d9-k5z7x                  1/1     Running   0          75s
kube-system   coredns-5644d7b6d9-q2464                  1/1     Running   0          75s
kube-system   etcd-container-host                       1/1     Running   0          15s
kube-system   kube-apiserver-container-host             1/1     Running   0          23s
kube-system   kube-controller-manager-container-host    1/1     Running   0          17s
kube-system   kube-proxy-z4fqq                          1/1     Running   0          75s
kube-system   kube-scheduler-container-host             1/1     Running   0          19s
```


# Deploy Kubernetes Workers:

* Run on a CentOS 7 hosts or VM that you want dedicated as a Worker

```./container_toolkit.sh --worker-node```

* Obtain your secret from master and add to each worker node.
* You can verify all is working by running on Master:

```
kubectl get nodes
NAME             STATUS   ROLES    AGE     VERSION
container-host   Ready    master   5m57s   v1.16.2
k8-node1         Ready    <none>   2m58s   v1.16.2
k8-node2         Ready    <none>   2m55s   v1.16.2
k8-node3         Ready    <none>   2m55s   v1.16.2
```


## Install Dockerfile
```
docker build -t container_toolkit .
docker run --rm -it container_toolkit /opt/container_toolkit/Ubuntu/container_toolkit.sh -h
docker run --rm -it container_toolkit /opt/container_toolkit/Centos/container_toolkit.sh -h
```


# Help Menu - Raspberry Pi

```
bash rpi_container_toolkit.sh 
[*] Help Menu:

[*] --rancherk3s-master    The generic k3s install for Master.
                             bash rpi_container_toolkit.sh --rancherk3s-master

[*] --rancherk3s-worker    The generic k3s install for Worker.
                             bash rpi_container_toolkit.sh --rancherk3s-worker


    ###### FOR THE DOCKER USERS - use below options to install Docker instead of containerd ######


[*] --rancherk3s-master-docker    K3s install for Master but with Docker instead of containerd.
                                    bash rpi_container_toolkit.sh --rancherk3s-master-docker

[*] --rancherk3s-worker-docker    K3s install for Worker but with Docker instead of containerd.
                                    bash rpi_container_toolkit.sh --rancherk3s-worker-docker


       >>> Use below to install frameworks known to work on k3s.

[*] --helm-master          Install Helm3 to Master
                               bash rpi_container_toolkit.sh --helm

[*] --openfaas-master      Install on master - openfaas repo and cli tools.
                               bash rpi_container_toolkit.sh --openfaas-master

[*] --arkade-master         Install on master - arkade repo and cli tools.
                               bash rpi_container_toolkit.sh --arkade-master
```

* Check your nodes

```
kubectl get nodes
NAME         STATUS   ROLES    AGE   VERSION
pi-master    Ready    master   37m   v1.18.2+k3s1
pi-worker1   Ready    <none>   27m   v1.18.2+k3s1
pi-worker2   Ready    <none>   25m   v1.18.2+k3s1
```

* Check your pods:
```
kubectl get pods --all-namespaces
NAMESPACE     NAME                                     READY   STATUS      RESTARTS   AGE
kube-system   helm-install-traefik-b5mzb               0/1     Completed   2          37m
kube-system   metrics-server-7566d596c8-5nqdn          1/1     Running     1          37m
kube-system   local-path-provisioner-6d59f47c7-blj9l   1/1     Running     1          37m
kube-system   svclb-traefik-kxhxw                      2/2     Running     2          36m
kube-system   traefik-758cd5fc85-shcm2                 1/1     Running     1          36m
kube-system   coredns-8655855d6-xh8p9                  1/1     Running     1          37m
kube-system   svclb-traefik-ftjzq                      2/2     Running     2          27m
kube-system   svclb-traefik-59p4l                      2/2     Running     0          25m
openfaas      nats-b988ccbfd-5zddw                     1/1     Running     0          22m
openfaas      queue-worker-5ffdf7b57-zssj6             1/1     Running     1          22m
openfaas      alertmanager-65fd77874c-xrmxx            1/1     Running     0          22m
openfaas      prometheus-9c9c8447b-dwnfz               1/1     Running     0          22m
openfaas      gateway-76fd4f4cf8-thdhb                 2/2     Running     0          22m
openfaas-fn   certinfo-68f7b4f848-db8nq                1/1     Running     0          21m
openfaas-fn   figlet-54647f7fc6-r789k                  1/1     Running     0          21m
openfaas-fn   nodeinfo-768577f7b5-6fg7x                1/1     Running     0          21m
openfaas      faas-idler-7579b574df-bzj66              1/1     Running     3          22m
```

## Test openfaas

* figlet
```
echo 'Got eem' | faas-cli invoke figlet --gateway http://127.0.0.1:31112
  ____       _                         
 / ___| ___ | |_    ___  ___ _ __ ___  
| |  _ / _ \| __|  / _ \/ _ \ '_ ` _ \ 
| |_| | (_) | |_  |  __/  __/ | | | | |
 \____|\___/ \__|  \___|\___|_| |_| |_|
                                       
```

* certinfo
```
curl http://127.0.0.1:31112/function/certinfo -d "google.com"
Host 172.217.1.206
Port 443
Issuer GTS CA 1O1
CommonName *.google.com
NotBefore 2020-04-28 07:43:41 +0000 UTC
NotAfter 2020-07-21 07:43:41 +0000 UTC
SANs [*.google.com *.android.com *.appengine.google.com *.bdn.dev *.cloud.google.com *.crowdsource.google.com *.g.co *.gcp.gvt2.com *.gcpcdn.gvt1.com *.ggpht.cn *.gkecnapps.cn *.google-analytics.com *.google.ca *.google.cl *.google.co.in *.google.co.jp *.google.co.uk *.google.com.ar *.google.com.au *.google.com.br *.google.com.co *.google.com.mx *.google.com.tr *.google.com.vn *.google.de *.google.es *.google.fr *.google.hu *.google.it *.google.nl *.google.pl *.google.pt *.googleadapis.com *.googleapis.cn *.googlecnapps.cn *.googlecommerce.com *.googlevideo.com *.gstatic.cn *.gstatic.com *.gstaticcnapps.cn *.gvt1.com *.gvt2.com *.metric.gstatic.com *.urchin.com *.url.google.com *.wear.gkecnapps.cn *.youtube-nocookie.com *.youtube.com *.youtubeeducation.com *.youtubekids.com *.yt.be *.ytimg.com android.clients.google.com android.com developer.android.google.cn developers.android.google.cn g.co ggpht.cn gkecnapps.cn goo.gl google-analytics.com google.com googlecnapps.cn googlecommerce.com source.android.google.cn urchin.com www.goo.gl youtu.be youtube.com youtubeeducation.com youtubekids.com yt.be]
```

* nodeinfo
```
echo -n verbose | faas-cli invoke nodeinfo --gateway 127.0.0.1:31112
Hostname: nodeinfo-768577f7b5-6fg7x

Arch: arm
CPUs: 4
Total mem: 3823MB
Platform: linux
Uptime: 1721
[
  {
..
..
```
