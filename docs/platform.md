# Platform sizing & hostnames

Per-component sizing, storage layout, ingress hostnames, and the credentials for
Grafana and Datadog.

```bash
ARGOCD_HOSTNAME=argocd
WORKER_DATA_DISK_GB=30
LONGHORN_MOUNT_PATH=/var/mnt/longhorn-data
LONGHORN_DATA_DISK_FSTYPE=xfs
LONGHORN_HOSTNAME=longhorn
KASTEN_HOSTNAME=kasten
GRAFANA_HOSTNAME=grafana
PROMETHEUS_HOSTNAME=prometheus
GRAFANA_ADMIN_PASSWORD=homelab-grafana-test-2026
PROMETHEUS_RETENTION=15d
PROMETHEUS_WAIT_TIMEOUT=15m
DATADOG_API_KEY=...
DATADOG_SITE=datadoghq.eu
DATADOG_CLUSTER_NAME=k8s-homelab
```

## Hostnames

These are the **subdomain labels** for each service's HTTPRoute. The full FQDN is
`<hostname>.<GATEWAY_DOMAIN>` (e.g. `grafana.homelab.panev.cloud`). external-dns
creates the matching Cloudflare A record. See
[cloudflare-gateway.md](cloudflare-gateway.md).

| Variable | Resulting URL (with `GATEWAY_DOMAIN=homelab.panev.cloud`) |
|----------|-----------------------------------------------------------|
| `ARGOCD_HOSTNAME` | `argocd.homelab.panev.cloud` |
| `LONGHORN_HOSTNAME` | `longhorn.homelab.panev.cloud` |
| `KASTEN_HOSTNAME` | `kasten.homelab.panev.cloud/k10/` |
| `GRAFANA_HOSTNAME` | `grafana.homelab.panev.cloud` |
| `PROMETHEUS_HOSTNAME` | `prometheus.homelab.panev.cloud` |

## Storage (Longhorn)

| Variable | Description |
|----------|--------------|
| `WORKER_DATA_DISK_GB` | Size (GB) of the dedicated data disk attached to each worker VM. Longhorn uses this disk, not the OS disk. |
| `LONGHORN_MOUNT_PATH` | Where the data disk is mounted on the worker and where Longhorn stores replicas. |
| `LONGHORN_DATA_DISK_FSTYPE` | Filesystem for that disk (`xfs` or `ext4`). |

Longhorn is **runtime** PVC storage. App **backups** are Kasten (or Velero) —
see [backup.md](backup.md).

## Monitoring (Prometheus / Grafana)

| Variable | Description |
|----------|--------------|
| `GRAFANA_ADMIN_PASSWORD` | Admin password for Grafana. **Set a strong value.** Injected into the kube-prometheus-stack release at deploy. |
| `PROMETHEUS_RETENTION` | How long Prometheus keeps metrics (e.g. `15d`). Balance against disk size (`retentionSize` in the Helm values). |
| `PROMETHEUS_WAIT_TIMEOUT` | How long the deploy waits for the monitoring stack to become ready (Helm `--timeout`). |

> Grafana has no "how to generate" step — you choose the password. After deploy
> log in at `https://<GRAFANA_HOSTNAME>.<GATEWAY_DOMAIN>` as `admin`.

## Datadog (optional)

Only used when `DATADOG_ENABLED=true` (see [toggles/datadog.md](toggles/datadog.md)).

| Variable | Description |
|----------|--------------|
| `DATADOG_API_KEY` | Datadog ingestion API key. |
| `DATADOG_SITE` | Datadog region/site (`datadoghq.eu`, `datadoghq.com`, …). Must match where your org lives. |
| `DATADOG_CLUSTER_NAME` | Cluster name shown in the Datadog UI. |

### How to get the Datadog API key

Datadog → **Organization Settings → API Keys → New Key**. Copy the key into
`DATADOG_API_KEY`. Pick `DATADOG_SITE` to match your account's region (visible in
the browser URL, e.g. `app.datadoghq.eu`).

---

## Related sizing variables

Defined in other groups but conceptually part of sizing:

- `LEADER_COUNT`, `WORKER_COUNT` (cluster size) — number of control-plane and
  worker VMs to clone. See `secrets.env`.
- Kasten NFS / policy (`KASTEN_NFS_*`, `KASTEN_POLICY_*`, `KASTEN_DR_POLICY_*`) —
  see [toggles/kasten.md](toggles/kasten.md) and [backup.md](backup.md).
- Velero backup retention (`VELERO_BACKUP_TTL`, `VELERO_SCHEDULE_CRON`) — see
  [toggles/velero.md](toggles/velero.md) (keep off when Kasten is enabled).
