apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: homelab
  namespace: ${GATEWAY_NAMESPACE}
  annotations:
    external-dns.alpha.kubernetes.io/hostname: "${GATEWAY_DOMAIN},*.${GATEWAY_DOMAIN}"
    external-dns.alpha.kubernetes.io/target: "${GATEWAY_LB_IP}"
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "*.${GATEWAY_DOMAIN}"
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: homelab-gateway-tls
      allowedRoutes:
        namespaces:
          from: All
