# ALERTMANAGER_ENABLED

Optional Alertmanager sub-chart inside kube-prometheus-stack.

## Enable

```bash
PROMETHEUS_ENABLED=true
ALERTMANAGER_ENABLED=true
```

## Behavior

Turns on Alertmanager when Prometheus is deployed. Default in many envs is
`false` so you can run metrics without alert routing.

Deploy passes `--set alertmanager.enabled=…` and toggles related default rules.

## Configuration

No extra secrets required for a basic install. Customize routes/receivers later
via Helm values or AlertmanagerConfig CRs.

## Verify

```bash
kubectl get pods -n monitoring | grep alertmanager
```

## Related

- [prometheus.md](prometheus.md)
