# Tailscale

See also: [toggles/tailscale.md](toggles/tailscale.md),
[toggles/tailscale-exporter.md](toggles/tailscale-exporter.md).

Tailscale VPN into the cluster. Flag: `TAILSCALE_ENABLED`. Variables below.

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
| `TAILSCALE_SUBNET_ROUTER_ENABLED` | `true` | Advertise the LAN subnet through a Tailscale subnet router. |
| `TAILSCALE_EXTRA_ROUTES` | _(unset)_ | Extra CIDRs to advertise (e.g. pod/service CIDRs `10.42.0.0/16,10.43.0.0/16`). |
| `TAILSCALE_API_SERVER_PROXY` | `false` | Expose the Kubernetes API server through Tailscale. |
| `TAILSCALE_LOGIN_SERVER` | _(unset)_ | Custom control server URL (e.g. Headscale). Empty = Tailscale SaaS. |

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
