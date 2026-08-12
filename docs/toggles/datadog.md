# DATADOG_ENABLED

Optional **Datadog Agent** Helm chart for external SaaS observability.

## Enable

```bash
DATADOG_ENABLED=true
DATADOG_API_KEY=CHANGE_ME
DATADOG_SITE=datadoghq.eu
DATADOG_CLUSTER_NAME=k8s-homelab
DATADOG_WAIT_TIMEOUT=15m
```

## Behavior

Deploys the Datadog Agent (and related chart components) into the cluster.
Off by default in many envs when Prometheus/Grafana cover local needs.

## Configuration

| Variable | Description |
|----------|-------------|
| `DATADOG_API_KEY` | Ingestion API key |
| `DATADOG_SITE` | Region site (`datadoghq.eu`, `datadoghq.com`, …) |
| `DATADOG_CLUSTER_NAME` | Name shown in Datadog UI |
| Helm | `helm-homelab/datadog/values.yaml` |

### API key

Datadog → Organization Settings → API Keys → New Key. Match `DATADOG_SITE` to
your account URL region.

## Verify

```bash
kubectl get pods -A | grep datadog
```

## Related

- [../platform.md](../platform.md)
- [prometheus.md](prometheus.md) — in-cluster alternative
