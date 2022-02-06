Install Traefik first, then move forward with cert-manager

helm install cert-manager jetstack/cert-manager \
--namespace cert-manager \
--create-namespace \
--version v1.7.0 \
--set installCRDs=true

Now define cluster issuers for certs:

kubectl apply -f selfsigned-cluster-issuer.yaml
kubectl apply -f letsencrypt-staging-issuer.yaml
kubectl apply -f letsencrypt-prod-issuer.yaml

