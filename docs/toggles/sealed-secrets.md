# SEALED_SECRETS_ENABLED

Deploys the **Sealed Secrets** controller so secrets can be encrypted into git
safely (typical with Argo CD).

## Enable

```bash
SEALED_SECRETS_ENABLED=true
```

## Behavior

Helm install of Bitnami Sealed Secrets controller. Encrypt locally with
`kubeseal`; cluster decrypts to normal Secrets.

Example notes: `gitops/examples/sealed-secret.md`.

## Configuration

| Item | Location |
|------|----------|
| Helm values | `helm-homelab/sealed-secrets/values.yaml` |
| No required secrets.env keys | beyond the toggle |

## Verify

```bash
kubectl get pods -n kube-system | grep sealed-secrets
# or the chart's namespace if customized
kubectl get crd sealedsecrets.bitnami.com
```

## Related

- [argocd.md](argocd.md)
- [argocd-bootstrap.md](argocd-bootstrap.md)
