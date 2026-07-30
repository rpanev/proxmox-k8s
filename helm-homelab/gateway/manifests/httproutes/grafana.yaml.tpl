apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
  namespace: ${PROMETHEUS_NAMESPACE}
  annotations:
    external-dns.alpha.kubernetes.io/target: "${GATEWAY_LB_IP}"
spec:
  parentRefs:
    - name: homelab
      namespace: ${GATEWAY_NAMESPACE}
      sectionName: https
  hostnames:
    - "grafana.${GATEWAY_DOMAIN}"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: ${PROMETHEUS_RELEASE}-grafana
          port: 80
