# TRIVY_OPERATOR_ENABLED

**Aqua Trivy Operator** — continuous vulnerability and config audits in-cluster.

## Enable

```bash
PROMETHEUS_ENABLED=true
TRIVY_OPERATOR_ENABLED=true
```

## Behavior

- Helm install in `trivy-system`
- CRs: `VulnerabilityReport`, `ConfigAuditReport`, …
- ServiceMonitor → Grafana dashboard **16337**

## Configuration

| Item | Location |
|------|----------|
| Helm values | `helm-homelab/trivy-operator/values.yaml` |
| Talos overlay | `helm-homelab/trivy-operator/values-talos.yaml` (when `--os=talos`) |

First scans populate after workloads exist; dashboard fills once metrics scrape.

## Verify

```bash
kubectl get vulnerabilityreports -A
kubectl get pods -n trivy-system
# Grafana → Homelab → Trivy Operator - Vulnerabilities
```

## Related

- [prometheus.md](prometheus.md)
