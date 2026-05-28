# Docker registry (Kubernetes)

## Local overrides (not committed)

Copy the template and edit your real values (NFS server, domain, htpasswd, issuer):

```bash
cp full_deployment.yaml full_deployment.local.yaml
```

Apply the local file:

```bash
kubectl apply -f full_deployment.local.yaml
```

`*.local.yaml` is listed in the repo root `.gitignore`.

## htpasswd

```bash
sudo apt install -y apache2-utils
htpasswd -Bbn registry YOUR_PASSWORD
```

Put the full `registry:$2y$...` line in `stringData.htpasswd` in your **local** manifest (or in the Secret via `kubectl create secret generic`).
