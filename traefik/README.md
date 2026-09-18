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
- **backend** (e.g. `http://10.42.0.15:8080`): Kubernetes pod IP Traefik proxied to — ignore for visitor tracking

If ClientAddr looks like a cluster node IP instead of the visitor, `externalTrafficPolicy` is not `Local`.

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

## Bot defense / rate limiting (scanners / abuse)

Public sites already have a per-app `per-ip-ratelimit` at **25 req/s, burst 50**. That is too loose for credential dumps: Traefik logs show one IP hitting `/.env`, `.aws`, phpinfo, WordPress, and `/auth/login` fast enough to 499/500 the app.

Cluster-wide draft (not applied until you choose to):

| File | What it is |
|---|---|
| [`bot-defense.yaml`](bot-defense.yaml) | Scanner-path drop (403) + tighter per-IP `rateLimit` / `inFlightReq` chain in `traefik-v2` |
| [`values.bot-defense.yaml`](values.bot-defense.yaml) | Optional Helm overlay that attaches the chain on `web` and `websecure` |

### 1. Scanner-path drop (apply first)

Stops probe URLs at Traefik so SPA catch-alls never return 200 HTML for `/.env`.

```bash
kubectl apply -f bot-defense.yaml
```

Check with a host that already has a cert:

```bash
curl -sI "https://harvestrangelabs.com/.env"
# expect HTTP/2 403
```

Legitimate app paths such as `/auth/login` are **not** blocked. Rate-limit those.

To undo just the drop + unused middlewares:

```bash
kubectl delete -f bot-defense.yaml
```

### 2. Global per-IP rate limit + in-flight cap (optional helm)

Creates the `bot-defense` chain (`60 req/min`, burst `20`, **8** concurrent requests per client IP) and, after this overlay, runs it on every request. Over-limit → **HTTP 429**.

Requires `externalTrafficPolicy: Local` (already in `values.cluster.yaml`) so buckets key off the real visitor IP, not a node IP. Do **not** set `ipStrategy.depth` behind MetalLB.

```bash
# bot-defense.yaml must already be applied
helm upgrade traefik traefik/traefik \
  --namespace traefik-v2 \
  --reuse-values \
  --values values.cluster.yaml \
  --values values.bot-defense.yaml
```

If a real SPA page load 429s, raise `burst` on `per-ip-ratelimit` in `bot-defense.yaml`. There is one Traefik replica, so in-memory buckets are enough (no Redis).

Per-app 25 req/s limits can stay; the entrypoint chain is the tighter cap.

### 3. Per-app copy (new Ingresses, or no global overlay)

Cross-namespace Middleware refs are still off unless you enable `providers.kubernetesCRD.allowCrossNamespace`. `docker-registry/` shows the per-namespace copy. Prefer attaching `traefik-v2-bot-defense@kubernetescrd` at the entrypoint (step 2) instead of duplicating.

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: per-ip-ratelimit
  namespace: <app-namespace>
spec:
  rateLimit:
    average: 60
    period: 1m
    burst: 20
    sourceCriterion:
      ipStrategy: {}
```

```yaml
metadata:
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: >-
      <namespace>-per-ip-ratelimit@kubernetescrd,<namespace>-security-headers@kubernetescrd
```

### Follow-up: CrowdSec

Rate limits do not ban repeat scanners. If dumps continue from many IPs, add the [CrowdSec Traefik bouncer](https://github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin) (log-based `http-probing` + community blocklists). That is a separate agent + plugin install, not in this draft.

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
* Apply `bot-defense.yaml` when ready; add `values.bot-defense.yaml` on helm upgrade for the global chain
* CrowdSec Traefik bouncer if rotating-IP scanners bypass per-IP limits
