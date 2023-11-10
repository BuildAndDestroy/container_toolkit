Install Traefik first, then move forward with cert-manager

helm repo add jetstack https://charts.jetstack.io

helm install cert-manager jetstack/cert-manager \
--namespace cert-manager \
--create-namespace \
--version v1.13.2 \
--set installCRDs=true

Now define cluster issuers for certs:

kubectl apply -f selfsigned-cluster-issuer.yaml
kubectl apply -f letsencrypt-staging-issuer.yaml
kubectl apply -f letsencrypt-prod-issuer.yaml


If using on AWS, expect this to fail if using a custom CNI (anything other than AWS' CNI). Just use AWS CNI if you need Let's Encrypt
