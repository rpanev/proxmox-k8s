apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: homelab-gateway
  namespace: metallb-system
spec:
  addresses:
    - ${GATEWAY_LB_IP}/32
  autoAssign: true
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: homelab-gateway
  namespace: metallb-system
spec:
  ipAddressPools:
    - homelab-gateway
