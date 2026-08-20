# ARGOCD_ENABLED

Installs **Argo CD** (GitOps controller). Apps are separate GitLab repos
under the group prefix (`HomeLab-GitOps/*`); this repo only installs Argo CD
and the group `repo-creds` token.

## Enable

```bash
ARGOCD_ENABLED=true
ARGOCD_HOSTNAME=argocd
```

## Behavior

- Helm release in namespace `argocd`
- HTTPRoute when Gateway is enabled
- Parallel MagicDNS HTTPS Ingress when Tailscale is enabled
- ServiceMonitors for Grafana dashboard **19993** (needs Prometheus)

## GitLab repositories (tokens)

Argo CD Applications only list a `repoURL`. Credentials are a Secret in
namespace `argocd` labeled `argocd.argoproj.io/secret-type: repo-creds`.
The `url` is a **prefix** — one Group Access Token covers every project
under that group (helm-dashboard and the rest of HomeLab-GitOps).

```bash
ARGOCD_GITLAB_URL=https://gitlab.com/your-group
ARGOCD_GITLAB_TOKEN=glpat-...
ARGOCD_GITLAB_USERNAME=oauth2
```

Applied by `deploy_argocd()` when both URL and token are set. Public Helm
chart repos need no token.

Manual equivalent is documented in `HomeLab-GitOps/helm-dashboard/README.md`.

## Configuration

| Variable | Description |
|----------|-------------|
| `ARGOCD_HOSTNAME` | Subdomain label |
| `ARGOCD_GITLAB_URL` | GitLab group/repo URL prefix for repo-creds |
| `ARGOCD_GITLAB_TOKEN` | Group Access Token (`read_repository`) or Deploy Token |
| `ARGOCD_GITLAB_USERNAME` | `oauth2` for PAT; deploy-token username otherwise |
| Helm values | `helm-homelab/argocd/values.yaml` |

Initial admin password: standard Argo CD secret
`argocd-initial-admin-secret` (unless chart overrides).

## Verify

```bash
kubectl get pods -n argocd
kubectl get ingress argocd-server -n argocd
# LAN: https://argocd.<GATEWAY_DOMAIN>
# VPN: https://argocd.<TAILSCALE_TAILNET>
```

## Related

- [sealed-secrets.md](sealed-secrets.md)
