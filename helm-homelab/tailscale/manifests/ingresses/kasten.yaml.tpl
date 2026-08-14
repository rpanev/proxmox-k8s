apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kasten-tailscale
  namespace: ${KASTEN_NAMESPACE}
  labels:
    app.kubernetes.io/managed-by: homelab
    homelab.panev.cloud/access: tailscale
spec:
  ingressClassName: tailscale
  defaultBackend:
    service:
      name: gateway
      port:
        number: 80
  tls:
    - hosts:
        - ${KASTEN_HOSTNAME}
