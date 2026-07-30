# RELOADER_ENABLED

**Stakater Reloader** — restarts Deployments/StatefulSets when watched
ConfigMaps or Secrets change.

## Enable

```bash
RELOADER_ENABLED=true
```

## Behavior

Helm install of Reloader. Annotate workloads (e.g.
`reloader.stakater.com/auto: "true"`) so pods roll on config updates.

## Configuration

| Item | Location |
|------|----------|
| Helm values | `helm-homelab/reloader/values.yaml` |
| No extra secrets | — |

## Verify

```bash
kubectl get pods -A | grep reloader
```

## Related

- [argocd.md](argocd.md) — often used together for config-driven restarts
