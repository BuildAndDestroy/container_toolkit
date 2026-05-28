Install Metallb, then Traefik first, then move forward with cert-manager

helm install \
  cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.20.2 \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true

Now define cluster issuers for certs (edit email in the YAML files, or use a local copy):

```bash
cp letsencrypt-prod-issuer.yaml letsencrypt-prod-issuer.local.yaml
# edit email in *.local.yaml — those files are gitignored
kubectl apply -f selfsigned-cluster-issuer.yaml
kubectl apply -f letsencrypt-staging-issuer.yaml
kubectl apply -f letsencrypt-prod-issuer.yaml
```


If using on AWS, expect this to fail if using a custom CNI (anything other than AWS' CNI). Just use AWS CNI if you need Let's Encrypt
