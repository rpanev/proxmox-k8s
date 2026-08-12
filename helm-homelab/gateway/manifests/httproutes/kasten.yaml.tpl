apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: kasten
  namespace: ${KASTEN_NAMESPACE}
  annotations:
    external-dns.alpha.kubernetes.io/target: "${GATEWAY_LB_IP}"
spec:
  parentRefs:
    - name: homelab
      namespace: ${GATEWAY_NAMESPACE}
      sectionName: https
  hostnames:
    - "kasten.${GATEWAY_DOMAIN}"
  rules:
    # K10 dashboard lives under /k10/ (root returns 404)
    - matches:
        - path:
            type: Exact
            value: /
      filters:
        - type: RequestRedirect
          requestRedirect:
            path:
              type: ReplaceFullPath
              replaceFullPath: /k10/
            statusCode: 302
    - matches:
        - path:
            type: PathPrefix
            value: /k10
      backendRefs:
        - name: gateway
          port: 80
