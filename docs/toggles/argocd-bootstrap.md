# ARGOCD_BOOTSTRAP_ENABLED

Applies the **app-of-apps** root Application so Argo CD syncs from git.

## Enable

```bash
ARGOCD_ENABLED=true
ARGOCD_BOOTSTRAP_ENABLED=true
GITOPS_REPO_URL=https://github.com/you/homelab.git
GITOPS_REPO_BRANCH=main
GITOPS_APPS_PATH=gitops/apps
```

## Behavior

Applies `gitops/bootstrap/appproject.yaml` and rendered
`root-application.yaml.tpl` pointing at `GITOPS_*`.

Without `ARGOCD_ENABLED`, this flag is a no-op.

Many homelab envs keep this **`false`** and manage the cluster imperatively
(`./deploy-infra.sh --helm-only`).

## Configuration

| Variable | Description |
|----------|-------------|
| `GITOPS_REPO_URL` | Git repository URL |
| `GITOPS_REPO_BRANCH` | Branch |
| `GITOPS_APPS_PATH` | Path to apps (default `gitops/apps`) |

Manifests: `gitops/bootstrap/`, examples under `gitops/examples/`.

## Verify

```bash
kubectl get applications -n argocd
```

## Related

- [argocd.md](argocd.md)
- [sealed-secrets.md](sealed-secrets.md)
