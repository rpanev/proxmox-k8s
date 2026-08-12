apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: prometheus
  namespace: ${PROMETHEUS_NAMESPACE}
  annotations:
    external-dns.alpha.kubernetes.io/target: "${GATEWAY_LB_IP}"
spec:
  parentRefs:
    - name: homelab
      namespace: ${GATEWAY_NAMESPACE}
      sectionName: https
  hostnames:
    - "prometheus.${GATEWAY_DOMAIN}"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: ${PROMETHEUS_RELEASE}-kube-prometheus-prometheus
          port: 9090
