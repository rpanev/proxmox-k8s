# Tailscale

See also: [toggles/tailscale.md](toggles/tailscale.md),
[toggles/tailscale-exporter.md](toggles/tailscale-exporter.md).

Tailscale VPN into the cluster. Flag: `TAILSCALE_ENABLED`. Variables below.

The Kubernetes operator provides MagicDNS HTTPS ingress for enabled platform
UIs while the regular Gateway API HTTPRoutes remain active. These are parallel
access paths to the same Services; neither the subnet router nor the Kubernetes
API proxy is required for UI access.

```bash
TAILSCALE_TAILNET=tail9822c.ts.net
TAILSCALE_OAUTH_CLIENT_ID=kFFvrx2Ud411CNTRL
TAILSCALE_OAUTH_CLIENT_SECRET=tskey-client-kFFvrx2Ud411CNTRL-...
# tailscale-exporter → Tailscale API metrics for Grafana 24177.
# OAuth client above needs READ access to the tailnet (devices/routes:read).
TAILSCALE_EXPORTER_ENABLED=true
```

| Variable | Description |
|----------|--------------|
| `TAILSCALE_TAILNET` | Your tailnet name (e.g. `tail9822c.ts.net` or `example.com`). Found in the Tailscale admin console under DNS / the org name. |
| `TAILSCALE_OAUTH_CLIENT_ID` | OAuth client ID used by the Tailscale Kubernetes Operator and the exporter to authenticate to the Tailscale API. |
| `TAILSCALE_OAUTH_CLIENT_SECRET` | OAuth client secret (`tskey-client-…`). Treat as a secret. |
| `TAILSCALE_EXPORTER_ENABLED` | When `true`, deploys `tailscale-exporter` + a ServiceMonitor so Grafana dashboard **24177** shows tailnet device/route metrics. Requires `PROMETHEUS_ENABLED=true`. |

Additional flags available in `secrets.env.example` (defaults shown):

| Variable | Default | Description |
|----------|---------|--------------|
| `TAILSCALE_APPLY_ACL` | `true` | Apply the repo's Tailscale ACL fragment on deploy. |
| `TAILSCALE_SUBNET_ROUTER_ENABLED` | `false` | Advertise the LAN subnet through a Tailscale subnet router. Enable temporarily for testing or when routed LAN/K8s access is required. |
| `TAILSCALE_EXTRA_ROUTES` | _(unset)_ | Extra CIDRs to advertise (e.g. pod/service CIDRs `10.42.0.0/16,10.43.0.0/16`). |
| `TAILSCALE_API_SERVER_PROXY` | `false` | Expose the Kubernetes API server through Tailscale. |
| `TAILSCALE_LOGIN_SERVER` | _(unset)_ | Custom control server URL (e.g. Headscale). Empty = Tailscale SaaS. |

## Application ingress

When the corresponding workload is enabled, Tailscale publishes:

- `https://argocd.<TAILSCALE_TAILNET>`
- `https://longhorn.<TAILSCALE_TAILNET>`
- `https://grafana.<TAILSCALE_TAILNET>`
- `https://prometheus.<TAILSCALE_TAILNET>`
- `https://kasten.<TAILSCALE_TAILNET>/k10/`

These Ingresses coexist with the Gateway HTTPRoutes and do not require subnet
routing. Argo CD and Longhorn create their Ingresses through Helm values;
Grafana, Prometheus, and Kasten use templates under
`helm-homelab/tailscale/manifests/ingresses/`.

Setting `TAILSCALE_SUBNET_ROUTER_ENABLED=false` removes the managed Connector
while leaving the operator and all application Ingress proxies running.

### Deploy paths

| Path | Installs operator | Reconciles application access |
|------|-------------------|-------------------------------|
| Full `--os=linux` | Yes, through `deploy.yml` | Yes |
| Full `--os=talos` | No; run `deploy-tailscale.yml` separately | Yes |
| `--helm-only` | No; existing operator required | Yes |
| `deploy-tailscale.yml` | Yes; reuses existing kubeconfig | No |

See [toggles/tailscale.md](toggles/tailscale.md) for the operator-only command.

---

## How to generate the OAuth client

1. Open the [Tailscale admin console](https://login.tailscale.com/admin/settings/oauth)
   → **Settings → OAuth clients → Generate OAuth client**.
2. Grant the scopes you need:
   - **Operator** (VPN ingress / subnet router): `Devices` (write) and `Routes`
     (write), tied to a tag such as `tag:k8s-homelab`.
   - **tailscale-exporter** (`TAILSCALE_EXPORTER_ENABLED=true`): **read** access —
     `Devices: read` and `Routes: read` are sufficient.
   - A single client can hold both write and read scopes; the example reuses one
     client for the operator and the exporter.
3. Copy the **client ID** and **client secret** into `TAILSCALE_OAUTH_CLIENT_ID`
   and `TAILSCALE_OAUTH_CLIENT_SECRET`. The secret is shown only once.

> The exporter only needs read scope. If your operator client lacks read access,
> create a second read-only OAuth client and point the exporter at it (you would
> need to split them in `secrets.env` / the deploy).

---

## tailscale-exporter

When enabled, the deploy:

1. Creates the namespace `tailscale-exporter`.
2. Creates a secret `tailscale-exporter-oauth` with `tailnet`, `client-id`,
   `client-secret` from the variables above.
3. Installs the `adinhodovic/tailscale-exporter` Helm chart (listens on `:9250`)
   with a ServiceMonitor enabled.

The chart values are in `helm-homelab/tailscale-exporter/values.yaml`; the deploy
logic is `deploy_tailscale_exporter()` in `scripts/lib/common.sh`.

Verify after deploy:

```bash
kubectl -n tailscale-exporter logs deploy/tailscale-exporter   # "OAuth token obtained"
# In Grafana: dashboard 24177 (Tailscale) should list your devices.
```
