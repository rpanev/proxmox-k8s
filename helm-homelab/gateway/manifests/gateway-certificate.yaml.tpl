apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: homelab-gateway-wildcard
  namespace: ${GATEWAY_NAMESPACE}
spec:
  secretName: homelab-gateway-tls
  issuerRef:
    name: letsencrypt-cloudflare
    kind: ClusterIssuer
  dnsNames:
    - "${GATEWAY_DOMAIN}"
    - "*.${GATEWAY_DOMAIN}"
