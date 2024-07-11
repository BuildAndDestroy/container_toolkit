helm repo add traefik https://helm.traefik.io/traefik
kubectl create ns traefik-v2
helm install --namespace=traefik-v2 traefik traefik/traefik

# Use this to access the dashboard. If on a remote host, just ssh port forward to your local machine
ssh -i ~/.ssh/id_rsa -L 9000:127.0.0.1:9000 user@master-ip -N
kubectl port-forward $(kubectl -n traefik-v2 get pods --selector "app.kubernetes.io/name=traefik" --output=name) 9000:9000
# Now visit 127.0.0.1:9000/dashboard/



Create unsigned certs:
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=traefik-ui.minikube"
Creat base64 and add them to the traefik-deployment.yaml:
    cat tls.crt | base64
    cat tls.key | base64
    rm tls.crt
    rm tls.key

These can be used for self signed certs. Let use letsencrypt for CA signed certs

Just add ingress and ingressroutes to your deployment files


TODO:
* Update with middleware, the below does not work with newer versions of Traefik and Let's Encrypt
* Found that the apiVersion needs to be updated (under IngressRoute):


---
apiVersion: v1
kind: Service
metadata:
  name: docker-registry-service
  namespace: docker-registry-namespace
spec:
  selector:
    app: docker-registry
  ports:
    - protocol: TCP
      port: 5000
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: docker-registry-ingress
  namespace: docker-registry-namespace
  annotations:
    kubernetes.io/ingress.class: "traefik"
    acme.cert-manager.io/http01-edit-in-place: "true"
    # cert-manager.io/cluster-issuer: letsencrypt-prod
    cert-manager.io/cluster-issuer: letsencrypt-staging
    traefik.ingress.kubernetes.io/frontend-entry-points: http, https
    traefik.ingress.kubernetes.io/redirect-entry-point: https
spec:
  rules:
  - host: registry.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: docker-registry-service
            port:
              number: 5000
  tls:
  - hosts:
    - registry.example.com
    secretName: docker-registry-tls
---
#apiVersion: traefik.containo.us/v1alpha1
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: registry-example-ingressroute
  namespace: docker-registry-namespace
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`registry.example.com`)
      kind: Rule
      services:
        - name: docker-registry-service
          port: 5000
  tls:
    certResolver: letsencrypt

