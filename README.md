Automate the install of Kubernetes and Docker.
Calico networking is here to stay.


# Help Menu


```
./centos7_container_toolkit.sh -h
[*] Help Menu:

[*] --master-calico   Install Kubernetes MASTER NODE Calico and Docker.
                      bash centos7_container_toolkit.sh -m

[*] --worker-node     Install Kubernetes WORKER NODE and Docker
                      bash centos7_container_toolkit.sh --node

[*] --docker     Install ONLY Docker.
                 bash centos7_container_toolkit.sh --docker

[*] --rancher    Install a ONLY Rancher constainer.
                 bash centos7_container_toolkit.sh --rancher

[*] --helm       Apply this option to install helm.
                 bash centos7_container_toolkit.sh --helm

[*] --PSO-init   After Kubernetes is up, run this first to install Pure Storage PSO.
                 bash centos7_container_toolkit.sh --PSO-init

    >>> --PSO-kube OR --PSO-helm, not both.

[*] --PSO-kube   After PSO-init ws ran, run this to install PSO into kubectl.
                 bash centos7_container_toolkit.sh --PSO-kube

[*] --PSO-helm   After PSO-init ws ran run this to install PSO into helm.
                 bash centos7_container_toolkit.sh --PSO-helm

[*] --clean      Clean up Kubernetes WORKER NODES. Typically we should not need this.
                 bash centos7_container_toolkit.sh --clean
```


# Deploy Kubernetes Master With The Calico Network:

* Run on a CentOS 7 hosts or VM that you want dedicated as Master

```./centos7_container_toolkit.sh --master-calico```

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

```./centos7_container_toolkit.sh --worker-node```

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


## Install Helm On Master

* This currently only works for Calico, run on Master.

```./centos7_container_toolkit.sh --helm```

```
kubectl get deployment tiller-deploy -n kube-system
NAME            READY   UP-TO-DATE   AVAILABLE   AGE
tiller-deploy   1/1     1            1           32s
```


## Install Dockerfile
```
docker build -t container_toolkit .
docker run --rm -it container_toolkit /opt/container_toolkit/centos7_container_toolkit.sh -h
```
