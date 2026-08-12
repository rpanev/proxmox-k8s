# TAILSCALE_EXPORTER_ENABLED

Exports Tailscale **API metrics** for Prometheus / Grafana dashboard **24177**.

## Enable

```bash
TAILSCALE_ENABLED=true
PROMETHEUS_ENABLED=true
TAILSCALE_EXPORTER_ENABLED=true
TAILSCALE_TAILNET=...
TAILSCALE_OAUTH_CLIENT_ID=...
TAILSCALE_OAUTH_CLIENT_SECRET=...   # needs Devices/Routes read
```

## Behavior

- Helm chart `tailscale-exporter` + OAuth secret
- ServiceMonitor scraped by kube-prometheus-stack
- Dashboard provisioned when Prometheus Homelab dashboards are enabled

## Configuration

| Variable | Description |
|----------|-------------|
| Same OAuth as operator | Or a read-only client |
| Helm | `helm-homelab/tailscale-exporter/values.yaml` |

## Verify

```bash
kubectl get pods -n tailscale-exporter
# Grafana → Homelab → Tailscale / Overview
```

## Related

- [tailscale.md](tailscale.md)
- [prometheus.md](prometheus.md)
- [../tailscale.md](../tailscale.md)
