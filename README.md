Automate the install of Kubernetes and Docker.
All works except Flannel Networking. Please use Calico for now.


# Help Menu


```
./centos_7_container_toolkit.sh -h
[*] Help Menu:

[*] -mf Install Kubernetes MASTER NODE Flannel and Docker.
        bash centos_7_container_toolkit.sh -m

[*] -mc Install Kubernetes MASTER NODE Calico and Docker.
        bash centos_7_container_toolkit.sh -m

[*] -n Install Kubernetes WORKER NODE and Docker
        bash centos_7_container_toolkit.sh -n

[*] --helm Apply this option to install helm.
        bash centos_7_container_toolkit.sh --helm

[*] -d Install ONLY Docker
        bash centos_7_container_toolkit.sh -d

[*] -r Install a ONLY Rancher host.
        bash centos_7_container_toolkit.sh -r

[*] -c Clean up Kubernetes WORKER NODES. Typically we should not need this.
        bash centos_7_container_toolkit.sh -c
```


# Deploy Kubernetes Master With The Calico Network:

* Run on a CentOS 7 hosts or VM that you want dedicated as Master

```./centos_7_container_toolkit.sh -mc```

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

# Deploy Kubernetes Master With The Flannel Network

* Run on a CentOS 7 hosts or VM that you want dedicated as Master

```./centos_7_container_toolkit.sh -mf```

* Once done, check your pods:

```
kubectl get pods --all-namespaces
NAMESPACE     NAME                                     READY   STATUS    RESTARTS   AGE
kube-system   coredns-5644d7b6d9-bj7cn                 1/1     Running   0          2m26s
kube-system   coredns-5644d7b6d9-qd8k9                 1/1     Running   0          2m26s
kube-system   etcd-container-host                      1/1     Running   0          81s
kube-system   kube-apiserver-container-host            1/1     Running   0          97s
kube-system   kube-controller-manager-container-host   1/1     Running   0          100s
kube-system   kube-flannel-ds-amd64-6fwx6              1/1     Running   2          96s
kube-system   kube-flannel-ds-amd64-6kwx8              1/1     Running   1          73s
kube-system   kube-flannel-ds-amd64-mr8ml              1/1     Running   0          86s
kube-system   kube-flannel-ds-amd64-zc9wb              1/1     Running   0          2m26s
kube-system   kube-proxy-dtq5z                         1/1     Running   0          2m26s
kube-system   kube-proxy-grsps                         1/1     Running   0          86s
kube-system   kube-proxy-kbfpf                         1/1     Running   0          96s
kube-system   kube-proxy-qhqpp                         1/1     Running   0          73s
kube-system   kube-scheduler-container-host            1/1     Running   0          80s

```

# Deploy Kubernetes Workers:

* Run on a CentOS 7 hosts or VM that you want dedicated as a Worker

```./centos_7_container_toolkit.sh -n```


* You can verify all is working by running on Master:

```
kubectl get nodes
NAME             STATUS   ROLES    AGE     VERSION
container-host   Ready    master   5m57s   v1.16.2
k8-node1         Ready    <none>   2m58s   v1.16.2
k8-node2         Ready    <none>   2m55s   v1.16.2
k8-node3         Ready    <none>   2m55s   v1.16.2
```

* Obtain your secret from master and add to each worker node.


## Install Helm On Master

* This currently only works for Calico, run on Master.

```./centos_7_container_toolkit.sh --helm```

```
kubectl get deployment tiller-deploy -n kube-system
NAME            READY   UP-TO-DATE   AVAILABLE   AGE
tiller-deploy   1/1     1            1           32s
```


## Install Dockerfile
```
docker build -t container_toolkit
docker run -it container_toolkit /opt/container_toolkit/centos_7_container_toolkit.sh -h
```
