Create unsigned certs:
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=traefik-ui.minikube"
Creat base64 and add them to the traefik-deployment.yaml:
    cat tls.crt | base64
    cat tls.key | base64
    rm tls.crt
    rm tls.key
Now deploy:
    kubectl apply -f traefik-rbac.yaml -f traefik-ds.yaml -f ui.yaml -f traefik-deployment.yaml
You can access the ingress url by adding an A record to your zone file or spoof by adding the FQDN and ip to your /etc/hosts file.
The ip will be the node your pod is running on. A better way is to add an haproxy to the environment. Still working on a config though
