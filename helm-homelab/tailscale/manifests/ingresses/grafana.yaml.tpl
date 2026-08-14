apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-tailscale
  namespace: ${PROMETHEUS_NAMESPACE}
  labels:
    app.kubernetes.io/managed-by: homelab
    homelab.panev.cloud/access: tailscale
spec:
  ingressClassName: tailscale
  defaultBackend:
    service:
      name: ${PROMETHEUS_RELEASE}-grafana
      port:
        number: 80
  tls:
    - hosts:
        - ${GRAFANA_HOSTNAME}
