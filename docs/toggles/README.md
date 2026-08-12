# Platform toggles

Each flag is `true` / `false` in `secrets.env`. Re-running deploy with a flag set
to `false` **skips** that component — it does **not** uninstall it.

Platform OS is **not** a toggle: use `./deploy-infra.sh --os=linux|talos`
(or fallback `TALOS_ENABLED`). See [../platform-os-bg.md](../platform-os-bg.md).

## Index

| Flag | Page |
|------|------|
| `CEPH_STORAGE` | [ceph-storage.md](ceph-storage.md) |
| `LONGHORN_ENABLED` | [longhorn.md](longhorn.md) |
| `SNAPSHOT_CONTROLLER_ENABLED` | [snapshot-controller.md](snapshot-controller.md) |
| `GATEWAY_ENABLED` | [gateway.md](gateway.md) |
| `EXTERNAL_DNS_ENABLED` | [external-dns.md](external-dns.md) |
| `PROMETHEUS_ENABLED` | [prometheus.md](prometheus.md) |
| `ALERTMANAGER_ENABLED` | [alertmanager.md](alertmanager.md) |
| `LOKI_ENABLED` | [loki.md](loki.md) |
| `ARGOCD_ENABLED` | [argocd.md](argocd.md) |
| `ARGOCD_BOOTSTRAP_ENABLED` | [argocd-bootstrap.md](argocd-bootstrap.md) |
| `SEALED_SECRETS_ENABLED` | [sealed-secrets.md](sealed-secrets.md) |
| `RELOADER_ENABLED` | [reloader.md](reloader.md) |
| `VELERO_ENABLED` | [velero.md](velero.md) |
| `KASTEN_ENABLED` | [kasten.md](kasten.md) |
| `DATADOG_ENABLED` | [datadog.md](datadog.md) |
| `TAILSCALE_ENABLED` | [tailscale.md](tailscale.md) |
| `TAILSCALE_EXPORTER_ENABLED` | [tailscale-exporter.md](tailscale-exporter.md) |
| `TRIVY_OPERATOR_ENABLED` | [trivy-operator.md](trivy-operator.md) |

## Dependency chains

```
LONGHORN_ENABLED / KASTEN_ENABLED
  └── SNAPSHOT_CONTROLLER_ENABLED   (CSI VolumeSnapshot CRDs — default on with either)

KASTEN_ENABLED
  ├── LONGHORN_ENABLED              (PVC data)
  ├── SNAPSHOT_CONTROLLER_ENABLED   (VolumeSnapshotClass longhorn, type=snap)
  └── KASTEN_NFS_*                  (Location Profile export; ≠ Proxmox SSD-storage)

CEPH_STORAGE=false + PROXMOX_SHARED_STORAGE
  └── PROXMOX_DATASTORE_ID          (e.g. SSD-storage — Proxmox VM disks / live migrate)

GATEWAY_ENABLED
  └── EXTERNAL_DNS_ENABLED   (HTTPRoute → Cloudflare A records)

PROMETHEUS_ENABLED
  ├── LOKI_ENABLED           (Grafana Loki datasource)
  ├── ALERTMANAGER_ENABLED
  ├── TRIVY_OPERATOR_ENABLED
  └── TAILSCALE_EXPORTER_ENABLED

ARGOCD_ENABLED
  └── ARGOCD_BOOTSTRAP_ENABLED

TAILSCALE_ENABLED
  └── TAILSCALE_EXPORTER_ENABLED (also needs Prometheus)
```

Backup layers (Proxmox / Longhorn / Kasten): [../backup.md](../backup.md).

## Where logic lives

| Concern | Location |
|---------|----------|
| Toggle parsing | `scripts/lib/common.sh` → `apply_platform_toggles` |
| Helm install | `deploy_*` functions in `common.sh` |
| Values | `helm-homelab/<component>/values.yaml` |
| HTTPRoutes | `helm-homelab/gateway/manifests/httproutes/` |
| Kasten NFS + policies | `helm-homelab/kasten/manifests/`, `apply_kasten_*` in `common.sh` |

Also listed in: [../feature-flags.md](../feature-flags.md).
