After Traefik is up and running, clone and install prometheus with grafana. Make sure to update the service file to route through Traefik

git clone https://github.com/prometheus-operator/kube-prometheus.git

New service file kube-prometheus/manifests/grafana-service.yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app.kubernetes.io/component: grafana
    app.kubernetes.io/name: grafana
    app.kubernetes.io/part-of: kube-prometheus
    app.kubernetes.io/version: 8.3.4
  name: grafana
  namespace: monitoring
spec:
  ports:
  - name: http
    port: 3000
    targetPort: http
  selector:
    app.kubernetes.io/component: grafana
    app.kubernetes.io/name: grafana
    app.kubernetes.io/part-of: kube-prometheus
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
spec:
  rules:
  - host: grafana.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 3000
---
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: grafana-ingress-route
  namespace: monitoring
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`grafana.example.com`)
      kind: Rule
      services:
        - name: grafana
          port: 80
  #tls:
  #  certResolver: traefik



kubectl create -f manifests/setup
kubectl create -f manifests/

Watch your pods, update your /etc/hosts with your loadbalancer IP and grafana.example.com. You will be able to access and create your admin account.
