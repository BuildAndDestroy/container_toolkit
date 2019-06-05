Automate the install of Kubernetes and Docker.
Rancher will deploy on the Master node but connecting workers currently fails.


# Help Menu


```./centos_7_container_toolkit.sh -h
[*] Help Menu:

[*] -m Install Kubernetes MASTER NODE, Docker, and Rancher.
        bash centos_7_container_toolkit.sh -m

[*] -n Install Kubernetes WORKER NODE and Docker
        bash centos_7_container_toolkit.sh -n

[*] -d Install ONLY Docker
        bash centos_7_container_toolkit.sh -d

[*] -c Clean up Kubernetes WORKER NODES. Typically we should not need this.
        bash centos_7_container_toolkit.sh -c
```


# Deploy Master:

```./centos_7_container_toolkit.sh -m```

# Deploy Workers:

```./centos_7_container_toolkit.sh -n```

* You can verify all is working by running on Master:

```kubectl get nodes

NAME         STATUS   ROLES    AGE     VERSION
k8s-master   Ready    master   4m25s   v1.14.2
k8s-node1    Ready    <none>   46s     v1.14.2
```

```kubectl get pods --all-namespaces

NAMESPACE     NAME                                 READY   STATUS    RESTARTS   AGE
kube-system   coredns-fb8b8dccf-7bhk8              1/1     Running   0          11m
kube-system   coredns-fb8b8dccf-pbj96              1/1     Running   0          11m
kube-system   etcd-k8s-master                      1/1     Running   0          10m
kube-system   kube-apiserver-k8s-master            1/1     Running   0          10m
kube-system   kube-controller-manager-k8s-master   1/1     Running   0          10m
kube-system   kube-flannel-ds-amd64-7svnh          1/1     Running   0          8m9s
kube-system   kube-flannel-ds-amd64-ftq5d          1/1     Running   0          10m
kube-system   kube-proxy-gdj2k                     1/1     Running   0          8m9s
kube-system   kube-proxy-r5bw2                     1/1     Running   0          11m
kube-system   kube-scheduler-k8s-master            1/1     Running   0          10m
```
