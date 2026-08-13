# Traefik

Helm chart install notes for this cluster (k3s + MetalLB).

## Install / upgrade

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

kubectl create ns traefik-v2

# Fresh install or upgrade with access logs + real client IPs:
helm upgrade --install traefik traefik/traefik \
  --namespace traefik-v2 \
  --values values.cluster.yaml
```

`values.cluster.yaml` enables:

| Setting | Why |
|---|---|
| `logs.access.enabled: true` | Log every request (visitor IP, host, path, status) |
| `service.spec.externalTrafficPolicy: Local` | Preserve real client IPs via MetalLB (otherwise logs show a node IP) |

On an **existing** release, you can also layer just these settings:

```bash
helm upgrade traefik traefik/traefik \
  --namespace traefik-v2 \
  --reuse-values \
  --values values.cluster.yaml
```

> **Do not** apply the full `values.yaml` to this cluster blindly — that file is oriented toward local/Gateway API / dashboard settings and will change ingress behavior.

## View visitor IPs

```bash
kubectl -n traefik-v2 logs -f deploy/traefik
```

Access log line shape:

```text
<ClientAddr> - - [<time>] "<method> <path> <proto>" <status> <size> "..." "..." <id> "<router>" "<backend>" <duration>
```

- **ClientAddr** (first field): visitor IP — this is what you want
- **backend** (e.g. `http://192.168.0.156:8080`): Kubernetes pod IP Traefik proxied to — ignore for visitor tracking

If ClientAddr looks like a node IP (`10.0.20.99`–`101`), `externalTrafficPolicy` is not `Local`.

## Dashboard (optional)

SSH port-forward to the machine, then:

```bash
ssh -i ~/.ssh/id_rsa -L 9000:127.0.0.1:9000 user@master-ip -N
kubectl -n traefik-v2 port-forward $(kubectl -n traefik-v2 get pods --selector "app.kubernetes.io/name=traefik" --output=name) 9000:9000
```

Visit `http://127.0.0.1:9000/dashboard/`

## Self-signed certs (optional / local)

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=traefik-ui.minikube"
cat tls.crt | base64
cat tls.key | base64
rm tls.crt tls.key
```

Prefer Let's Encrypt / cert-manager for real hosts.

## Rate limiting (scanners / abuse)

Rate limits live in **each website repo** (not here), as a `per-ip-ratelimit` Middleware next to that app’s security-headers middleware. Traefik cross-namespace middlewares are disabled, so each namespace needs its own copy.

| Site | Repo | Middleware / Ingress |
|---|---|---|
| harvestrangelabs.com | `../harvestrangelabs.com` | `k3s/traefik-security-middleware.yaml`, `k3s/ingress.yaml` |
| interest-rates | `../interest-rates.harvestrangelabs.com` | `deploy/kubernetes/middleware.yaml`, `ingress.yaml` |
| eagle-mountain budget | `../eaglemountain-cc-budget` | `k3s-web/middleware.yaml`, `ingress.yaml` |
| manage-vendors | `../manage-vendors.harvestrangelabs.com` | `k3s/traefik-security-middleware.yaml`, `k3s/ingress.yaml` |
| wedding-photos | `../wedding-photos.harvestrangelabs.com` | `k3s/traefik-security-middleware.yaml`, `k3s/ingress.yaml` |
| docker registry | `../container_toolkit/docker-registry` | `full_deployment.yaml` / `.local.yaml` |

Typical defaults: **25 req/s**, burst **50** (registry: **50**/s, burst **100**). Over-limit → **HTTP 429**.

Pattern for a new public site:

```yaml
# Middleware (same namespace as the Ingress)
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: per-ip-ratelimit
  namespace: <app-namespace>
spec:
  rateLimit:
    average: 25
    period: 1s
    burst: 50
```

```yaml
# HTTPS Ingress — rate-limit first, then security headers
metadata:
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: >-
      <namespace>-per-ip-ratelimit@kubernetescrd,<namespace>-security-headers@kubernetescrd
```

Requires Traefik `service.spec.externalTrafficPolicy: Local` (see `values.cluster.yaml`) so limits key off the real client IP.

## Example Ingress / IngressRoute

Add Ingress and IngressRoute objects to your app deployment files. Example:

```yaml
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
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.middlewares: docker-registry-ns-per-ip-ratelimit@kubernetescrd
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  ingressClassName: traefik
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
      middlewares:
        - name: per-ip-ratelimit
      services:
        - name: docker-registry-service
          port: 5000
  tls:
    certResolver: letsencrypt
```

## TODO

* Prefer `apiVersion: traefik.io/v1alpha1` for IngressRoute (not `traefik.containo.us`)
* When adding a new public site, ship `per-ip-ratelimit` in that app’s repo and wire it on the HTTPS Ingress
