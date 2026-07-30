apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: longhorn
  namespace: longhorn-system
  annotations:
    external-dns.alpha.kubernetes.io/target: "${GATEWAY_LB_IP}"
spec:
  parentRefs:
    - name: homelab
      namespace: ${GATEWAY_NAMESPACE}
      sectionName: https
  hostnames:
    - "longhorn.${GATEWAY_DOMAIN}"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: longhorn-frontend
          port: 80
