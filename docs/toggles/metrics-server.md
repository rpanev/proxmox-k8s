# METRICS_SERVER_ENABLED

**metrics-server** — Kubernetes Metrics API (`metrics.k8s.io`). Needed for
`kubectl top` and Homepage Kubernetes widgets. This is not Prometheus;
kube-prometheus-stack does not provide this API.

## Enable

```bash
METRICS_SERVER_ENABLED=true
```

## Behavior

Helm install into `kube-system`. Values add `--kubelet-insecure-tls` so
Talos kubelets work (chart defaultArgs stay in place).

## Configuration

| Item | Location |
|------|----------|
| Helm values | `helm-homelab/metrics-server/values.yaml` |
| Chart | `metrics-server/metrics-server` |
| No extra secrets | — |

## Verify

```bash
kubectl -n kube-system rollout status deploy/metrics-server
kubectl top nodes
```

## Related

- Homepage RBAC in `HomeLabApps/homepage/homepage-rbac.yaml` (`metrics.k8s.io`)
- [prometheus.md](prometheus.md) — cluster metrics in Grafana, not `kubectl top`
