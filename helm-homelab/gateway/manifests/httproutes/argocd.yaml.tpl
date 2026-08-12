apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd
  namespace: argocd
  annotations:
    external-dns.alpha.kubernetes.io/target: "${GATEWAY_LB_IP}"
spec:
  parentRefs:
    - name: homelab
      namespace: ${GATEWAY_NAMESPACE}
      sectionName: https
  hostnames:
    - "argocd.${GATEWAY_DOMAIN}"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: argocd-server
          port: 80
