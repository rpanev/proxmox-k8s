# ARGOCD_ENABLED

Installs **Argo CD** (GitOps controller). Does not bootstrap apps unless
[argocd-bootstrap.md](argocd-bootstrap.md) is also enabled.

## Enable

```bash
ARGOCD_ENABLED=true
ARGOCD_HOSTNAME=argocd
```

## Behavior

- Helm release in namespace `argocd`
- HTTPRoute when Gateway is enabled
- ServiceMonitors for Grafana dashboard **19993** (needs Prometheus)

## Configuration

| Variable | Description |
|----------|-------------|
| `ARGOCD_HOSTNAME` | Subdomain label |
| Helm values | `helm-homelab/argocd/values.yaml` |

Initial admin password: standard Argo CD secret
`argocd-initial-admin-secret` (unless chart overrides).

## Verify

```bash
kubectl get pods -n argocd
# https://argocd.<GATEWAY_DOMAIN>
```

## Related

- [argocd-bootstrap.md](argocd-bootstrap.md)
- [sealed-secrets.md](sealed-secrets.md)
