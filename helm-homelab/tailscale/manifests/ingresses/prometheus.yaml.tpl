apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-tailscale
  namespace: ${PROMETHEUS_NAMESPACE}
  labels:
    app.kubernetes.io/managed-by: homelab
    homelab.panev.cloud/access: tailscale
spec:
  ingressClassName: tailscale
  defaultBackend:
    service:
      name: ${PROMETHEUS_RELEASE}-kube-prometheus-prometheus
      port:
        number: 9090
  tls:
    - hosts:
        - ${PROMETHEUS_HOSTNAME}
