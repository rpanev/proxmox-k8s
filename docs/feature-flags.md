# Platform feature flags

Per-flag notes: [toggles/](toggles/README.md).

Toggles are `true` / `false` in `secrets.env`. `false` skips that `deploy_*`
step on the next run; it normally does not uninstall something already deployed.
The managed Tailscale Connector is removed when
`TAILSCALE_SUBNET_ROUTER_ENABLED=false`.

## Platform OS

Not a `secrets.env` toggle — use CLI:

```bash
./deploy-infra.sh -y --os=linux
./deploy-infra.sh -y --os=talos
```

Fallback when `--os` is omitted: `TALOS_ENABLED`.

## Quick list

| Flag | Doc |
|------|-----|
| `CEPH_STORAGE` | [toggles/ceph-storage.md](toggles/ceph-storage.md) |
| `LONGHORN_ENABLED` | [toggles/longhorn.md](toggles/longhorn.md) |
| `SNAPSHOT_CONTROLLER_ENABLED` | [toggles/snapshot-controller.md](toggles/snapshot-controller.md) |
| `GATEWAY_ENABLED` | [toggles/gateway.md](toggles/gateway.md) |
| `EXTERNAL_DNS_ENABLED` | [toggles/external-dns.md](toggles/external-dns.md) |
| `PROMETHEUS_ENABLED` | [toggles/prometheus.md](toggles/prometheus.md) |
| `ALERTMANAGER_ENABLED` | [toggles/alertmanager.md](toggles/alertmanager.md) |
| `LOKI_ENABLED` | [toggles/loki.md](toggles/loki.md) |
| `ARGOCD_ENABLED` | [toggles/argocd.md](toggles/argocd.md) |
| `ARGOCD_BOOTSTRAP_ENABLED` | [toggles/argocd-bootstrap.md](toggles/argocd-bootstrap.md) |
| `SEALED_SECRETS_ENABLED` | [toggles/sealed-secrets.md](toggles/sealed-secrets.md) |
| `RELOADER_ENABLED` | [toggles/reloader.md](toggles/reloader.md) |
| `VELERO_ENABLED` | [toggles/velero.md](toggles/velero.md) |
| `KASTEN_ENABLED` | [toggles/kasten.md](toggles/kasten.md) |
| `DATADOG_ENABLED` | [toggles/datadog.md](toggles/datadog.md) |
| `TAILSCALE_ENABLED` | [toggles/tailscale.md](toggles/tailscale.md) |
| `TAILSCALE_SUBNET_ROUTER_ENABLED` | [toggles/tailscale.md](toggles/tailscale.md) (optional, default `false`) |
| `TAILSCALE_API_SERVER_PROXY` | [toggles/tailscale.md](toggles/tailscale.md) (optional, default `false`) |
| `TAILSCALE_EXPORTER_ENABLED` | [toggles/tailscale-exporter.md](toggles/tailscale-exporter.md) |
| `TRIVY_OPERATOR_ENABLED` | [toggles/trivy-operator.md](toggles/trivy-operator.md) |

Dependency chains and deploy locations: [toggles/README.md](toggles/README.md).

Storage vs backup (Longhorn / Kasten / Proxmox NFS): [backup.md](backup.md).
