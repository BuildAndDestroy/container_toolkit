# Traefik

Helm chart install notes for this cluster (k3s + MetalLB). Values match **chart 41+** (`accessLog`, `providers.file.content` as an object).

**Pinned version: chart `42.4.0` → Traefik `v3.7.18`.** Always pass `--version`. Without it, Helm installs whatever is newest on the day you run it.

| Traefik | Status |
|---|---|
| ≤ v3.7.13 (chart ≤ 41.6.x) | Vulnerable: GHSA-qm9f-w54v-q2qh, GHSA-53qr-784g-cj35 (Negotiate/NTLM pool contamination), GHSA-fh26-gfpp-7xxx (SNI check bypass), plus the Ingress-NGINX provider advisories |
| v3.7.14 – v3.7.16 (chart 41.7.0 – 42.2.0) | Vulnerable: **GHSA-xv5x-242w-7hf7**, unauthenticated DoS via `Authorization: NTLM/Negotiate`, no special config needed. Do not stop here. |
| v3.7.17 (chart 42.3.0 – 42.3.2) | Vulnerable: GHSA-ccgh-9g52-6vwg, GHSA-cp28-5662-543f, GHSA-p956-6gvv-mxqp, GHSA-x5pf-cqh3-2gv8, GHSA-rr42-h8r2-f28g |
| **v3.7.18** (chart 42.4.0+) | Patched for all of the above |

Chart 42 needs Kubernetes ≥ 1.30. Its other breaking changes only touch Traefik Hub values, which this cluster doesn't set. With `values.cluster.yaml`, 42.3.1 and 42.4.0 render the same manifests except for labels, the image tag, and a new default `--entryPoints.{web,websecure}.transport.lifeCycle.requestAcceptGraceTimeout=5s` (pod shutdown takes 5s longer so the Service drops the endpoint before Traefik stops accepting). The 42.4.0 CRD changes touch only Traefik Hub CRDs.

v3.7.18 behavior changes ([migration guide](https://doc.traefik.io/traefik/v3.7/migrate/v3/#v3718)) don't affect this cluster: BasicAuth now rejects passwords over 1024 bytes (no BasicAuth middlewares here), the Ingress-NGINX provider's TLS options changed (that provider is off), and dot-segments carrying path parameters (`/foo/..;bar/baz`) are resolved like plain dot-segments.

## New deployment

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

kubectl create ns traefik-v2

helm upgrade --install traefik traefik/traefik \
  --namespace traefik-v2 \
  --version 42.4.0 \
  --values values.cluster.yaml
```

A fresh install creates the CRDs from the chart's `crds/` directory, so there is no extra step.

## Upgrading an existing release to v3.7.18

Check what is running first:

```bash
helm -n traefik-v2 list
kubectl -n traefik-v2 get deploy traefik -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
helm -n traefik-v2 get values traefik   # should match values.cluster.yaml only
```

### Option A: chart upgrade to 42.4.0 (recommended)

Helm never upgrades CRDs on `helm upgrade`, so apply the 42.4.0 CRDs first. The changes only add fields (42.3 added an optional `respondingTimeouts` on IngressRoute; 42.4 only touches Hub CRDs), so existing objects stay valid.

```bash
helm repo update traefik

# 1. CRDs from the exact chart version
helm pull traefik/traefik --version 42.4.0 --untar -d /tmp/traefik-42.4.0
kubectl apply --server-side --force-conflicts -f /tmp/traefik-42.4.0/traefik/crds/

# 2. Preview (optional, needs the helm-diff plugin)
helm diff upgrade traefik traefik/traefik -n traefik-v2 \
  --version 42.4.0 --reset-values --values values.cluster.yaml

# 3. Upgrade
helm upgrade traefik traefik/traefik \
  --namespace traefik-v2 \
  --version 42.4.0 \
  --reset-values \
  --values values.cluster.yaml

# 4. Verify
kubectl -n traefik-v2 rollout status deploy/traefik
kubectl -n traefik-v2 get deploy traefik -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'   # docker.io/traefik:v3.7.18
curl -sI https://<a-site-host>/ | head -1
```

Middlewares, IngressRoutes and Ingresses are Kubernetes objects. They survive the upgrade, so nothing in `traefik/sites/` needs to be reapplied. For about 2 seconds after the new pod starts, the log shows `middleware "<ns>-<name>@kubernetescrd" does not exist` for every Ingress, because the Ingress provider loads before the CRD provider has synced. That is expected. Worry only if those errors keep appearing afterwards.

Tested 2026-11-09 on the k3s cluster, 41.6.0 → 42.3.1: all 51 Middlewares kept, every host returned the same status, redirect and security headers as before, the site rate limit still returns 429, and `/.env` still returns 403.

Tested 2026-11-13 on the k3s cluster, 42.3.1 → 42.4.0 (helm revision 8): all 52 Middlewares kept, all 10 Ingress hosts returned the same status as before, `/.env` still returns 403, the registry still redirects HTTP → HTTPS (308), and no errors in the Traefik log after rollout.

`--reset-values` together with `values.cluster.yaml` is safe here because the live release has no other user values. If you added overlays since then, pass those files too.

Rollback: `helm -n traefik-v2 rollback traefik <previous-revision>`. Leave the newer CRDs in place, since they only add fields.

### Option B: image-only hotfix (stay on chart 42.3.x)

Use this to get the patched binary out right away without a chart bump, for example during a change freeze. The chart templates stay as they are and only the container tag changes. CRDs are untouched.

```bash
helm upgrade traefik traefik/traefik \
  --namespace traefik-v2 \
  --version 42.3.1 \
  --reset-values \
  --values values.cluster.yaml \
  --set image.tag=v3.7.18
```

This is a stopgap. The chart's `appVersion` no longer matches the image, and a later upgrade without `--set image.tag` drops back to the chart default. Follow up with Option A.

### Option C: in-place `kubectl set image` (not recommended)

`kubectl -n traefik-v2 set image deploy/traefik traefik=docker.io/traefik:v3.7.18` works in an emergency, but Helm doesn't know about it and the next `helm upgrade` reverts it. Use it only if Helm itself is broken, then run Option A.

`values.cluster.yaml` enables:

| Setting | Why |
|---|---|
| `accessLog.enabled: true` | Log every request (visitor IP, host, path, status) |
| `providers.file.content: {}` | Chart 41 schema; 40.x used an empty string |
| `service.spec.externalTrafficPolicy: Local` | Preserve real client IPs via MetalLB (otherwise logs show a node IP) |

**40.x → 41.x:** do **not** use `--reuse-values`. Helm would keep `logs:` and `providers.file.content: ""` from revision 4 and fail schema validation. Reset to chart defaults, then apply our files. Do **not** add an entrypoint rate-limit overlay:

```bash
helm upgrade traefik traefik/traefik \
  --namespace traefik-v2 \
  --reset-values \
  --values values.cluster.yaml
```

After that, later 41.x patches can use `--reuse-values` again:

```bash
helm upgrade traefik traefik/traefik \
  --namespace traefik-v2 \
  --reuse-values \
  --values values.cluster.yaml
```

> **Do not** apply a local/Gateway-API values file to this cluster blindly — that will change ingress behavior.

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

## Scanner paths and rate limits

Two different jobs. Do not put them on the same middleware.

| File | What it is |
|---|---|
| [`bot-defense.yaml`](bot-defense.yaml) | Cluster-wide 403 for probe paths (`/.env`, WordPress, phpinfo, …). No rate limit. |
| [`values.bot-defense.yaml`](values.bot-defense.yaml) | Empty on purpose. Does not attach anything to an entrypoint. |
| [`templates/ratelimit-site.yaml`](templates/ratelimit-site.yaml) | One person per public IP. 60/minute, burst 20, 8 in flight. |
| [`templates/ratelimit-venue.yaml`](templates/ratelimit-venue.yaml) | Hundreds of people on one Wi-Fi (one public IP). Room-sized ceiling, separate auth ceiling. |
| [`templates/ratelimit-registry.yaml`](templates/ratelimit-registry.yaml) | `docker push` / `docker pull`. 50/second, burst 100. Not the site or venue profile. |

An entrypoint middleware runs for every host. A 20-request burst there rejects a normal gallery load, and at a venue it rejects the whole room, because every phone is the same client IP. Attach a limit on that app's Ingress only.

Cross-namespace Middleware refs stay off. There is one Traefik replica, so in-memory buckets are enough. Do not set `ipStrategy.depth` behind MetalLB.

`templates/` is the source. Do not apply those files: `namespace` is still `app`. Copy the chosen template to `traefik/sites/<namespace>.yaml` and replace every `app` with the app namespace. `traefik/sites/` is gitignored, so the filled copies (real namespaces and hosts) stay on this machine.

```bash
kubectl apply -f traefik/sites/<namespace>.yaml
```

That creates the Middleware only. Add the annotation on that app's Ingress or the limit never runs. The name is `<namespace>-site-ratelimit@kubernetescrd` or `<namespace>-venue-ratelimit@kubernetescrd`.

### 1. Scanner-path drop

Stops probe URLs at Traefik so an SPA catch-all never returns 200 HTML for `/.env`.

```bash
kubectl apply -f bot-defense.yaml
```

```bash
curl -sI "https://harvestrangelabs.com/.env"
# expect HTTP/2 403
```

Login routes are not in that list. The venue or site template covers them.

```bash
kubectl delete -f bot-defense.yaml
```

### 2. Detach the old global chain

Releases that applied the previous `values.bot-defense.yaml` still run `traefik-v2-bot-defense` (60/minute, burst 20, 8 in flight) on `web` and `websecure`. `--reuse-values` will not remove it. `--reset-values` drops Helm keys that are not in the files you pass, so include any other overlay this release still needs.

```bash
helm upgrade traefik traefik/traefik \
  --namespace traefik-v2 \
  --reset-values \
  --values values.cluster.yaml

kubectl apply -f bot-defense.yaml

kubectl -n traefik-v2 delete middleware bot-defense per-ip-ratelimit per-ip-inflight --ignore-not-found
```

Delete those middlewares only after the upgrade. Traefik will not start if an entrypoint still names a missing middleware.

### 3. Pick a per-app template

**Site** — home and cellular visitors, each with their own IP. Brochure sites and admin tools. Copy `templates/ratelimit-site.yaml` into `traefik/sites/`.

**Venue** — a room, a hotel, a conference. Hundreds of phones, one public IP. Copy `templates/ratelimit-venue.yaml` into `traefik/sites/`.

**Registry** — `docker push` and `docker pull`. One build machine opens many layer requests at once. Copy `templates/ratelimit-registry.yaml` into `traefik/sites/`. The site burst of 20 makes the client report `toomanyrequests`. The venue ceiling is for a crowded Wi-Fi, not for the registry host.

| | Site | Venue (the room) | Venue auth routes | Registry |
|---|---|---|---|---|
| Average | 60 / minute | 500 / second | 40 / second | 50 / second |
| Burst | 20 | 8000 | 800 | 100 |
| In flight | 8 | 4000 | (none; the rate bucket is the cap) | none |

Venue burst 8000 is one opening wave of about 400 people loading a page (document, assets, API), not 400 people each pulling every file in a gallery. Apps that fan out one request per photo have to cap concurrency in the browser and retry 429. Raising this burst until an unbounded gallery fits also lets one Wi-Fi flood the nodes.

Auth burst 800 is the same room submitting login and a second factor. The steady 40/second stops a high-speed password dump from that Wi-Fi. It does not replace per-account lockout in the app.

Put `venue-ratelimit` on the main Ingress (`path: /`). Put `venue-auth-ratelimit` on a second Ingress with only the credential prefixes, and the same TLS secret. The longer path is chosen first, so login does not spend the room bucket. File downloads stay on the room ceiling.

```yaml
metadata:
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: app-venue-ratelimit@kubernetescrd
spec:
  rules:
    - host: example.com
      http:
        paths:
          - path: /
            pathType: Prefix
---
metadata:
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: app-venue-auth-ratelimit@kubernetescrd
spec:
  rules:
    - host: example.com
      http:
        paths:
          - path: /api/auth
            pathType: Prefix
          - path: /api/totp
            pathType: Prefix
```

Change the prefixes to match the app. A site Ingress uses `app-site-ratelimit@kubernetescrd` and does not need the second Ingress.

### Follow-up: CrowdSec

Rate limits do not ban repeat scanners. If dumps continue from many IPs, add the [CrowdSec Traefik bouncer](https://github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin) (log-based `http-probing` + community blocklists). That is a separate agent + plugin install.

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
    traefik.ingress.kubernetes.io/router.middlewares: docker-registry-namespace-site-ratelimit@kubernetescrd
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
        - name: site-ratelimit
      services:
        - name: docker-registry-service
          port: 5000
  tls:
    certResolver: letsencrypt
```

## TODO

* Prefer `apiVersion: traefik.io/v1alpha1` for IngressRoute (not `traefik.containo.us`)
* Keep scanner drops in `bot-defense.yaml`; copy `templates/` into `traefik/sites/` and attach that chain on each Ingress
* CrowdSec Traefik bouncer if rotating-IP scanners bypass per-IP limits
