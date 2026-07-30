# VELERO_ENABLED

Cluster backup/restore via **Velero** to an S3-compatible store (e.g. MinIO).

## Enable

```bash
VELERO_ENABLED=true
VELERO_S3_URL=http://172.16.33.50:29990
VELERO_S3_BUCKET=k8s-homelab
VELERO_S3_ACCESS_KEY=CHANGE_ME
VELERO_S3_SECRET_KEY=CHANGE_ME
VELERO_S3_INSECURE=true
VELERO_SCHEDULE_ENABLED=true
VELERO_SCHEDULE_CRON=0 2 * * *
VELERO_BACKUP_TTL=720h
```

## Behavior

- Helm Velero + credentials secret
- Optional scheduled backups
- ServiceMonitor → Grafana dashboard **23838** when Prometheus is on

Deploy fails if the S3 endpoint is unreachable while the toggle is true.

## Configuration

| Variable | Description |
|----------|-------------|
| `VELERO_S3_*` | Endpoint, bucket, keys, insecure TLS |
| `VELERO_SCHEDULE_*` | Cron schedule enable + expression |
| `VELERO_BACKUP_TTL` | Retention of backups |
| Helm | `helm-homelab/velero/values.yaml` |

## Verify

```bash
kubectl get pods -n velero
kubectl get backupstoragelocation -A
kubectl get schedule -A
```

## Related

- [prometheus.md](prometheus.md) — Velero Overview dashboard
- [longhorn.md](longhorn.md) — volume backups are separate from PBS / Velero scope
