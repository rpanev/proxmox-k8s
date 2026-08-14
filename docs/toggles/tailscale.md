# TAILSCALE_ENABLED

**Tailscale Kubernetes Operator** for remote VPN access to the cluster / LAN.

Longer OAuth / ACL notes: [../tailscale.md](../tailscale.md).

## Enable

```bash
TAILSCALE_ENABLED=true
TAILSCALE_TAILNET=tailXXXX.ts.net
TAILSCALE_OAUTH_CLIENT_ID=...
TAILSCALE_OAUTH_CLIENT_SECRET=tskey-client-...
TAILSCALE_APPLY_ACL=true
TAILSCALE_SUBNET_ROUTER_ENABLED=false
# TAILSCALE_EXTRA_ROUTES=10.42.0.0/16,10.43.0.0/16
TAILSCALE_API_SERVER_PROXY=false
```

## Behavior

- Installs Tailscale operator via Helm (Ansible localhost role / deploy path)
- Exposes enabled platform UIs through Tailscale MagicDNS HTTPS URLs
- Runs alongside Gateway API: VPN and LAN URLs target the same Services
- Optionally applies ACL fragment from the repo
- Optional subnet router advertising LAN (+ extra routes); disabling it removes
  the managed Connector
- Cleanup on destroy via Tailscale API

With both `TAILSCALE_ENABLED=true` and `GATEWAY_ENABLED=true`, each enabled
platform UI keeps its standard `https://<service>.<GATEWAY_DOMAIN>` URL and also
gets `https://<service>.<TAILSCALE_TAILNET>`. Kasten uses `/k10/`.

Subnet routing and the Kubernetes API proxy are independent of these UI URLs
and remain disabled by default.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `TAILSCALE_TAILNET` | _(required)_ | Tailnet DNS name |
| `TAILSCALE_OAUTH_CLIENT_*` | _(required)_ | OAuth client for operator |
| `TAILSCALE_APPLY_ACL` | `true` | Push ACL fragment on deploy |
| `TAILSCALE_SUBNET_ROUTER_ENABLED` | `false` | Advertise LAN routes; `false` removes the managed Connector |
| `TAILSCALE_EXTRA_ROUTES` | _(unset)_ | Extra CIDRs |
| `TAILSCALE_API_SERVER_PROXY` | `false` | Expose K8s API via Tailscale |
| `TAILSCALE_LOGIN_SERVER` | _(unset)_ | Empty = Tailscale SaaS; set for Headscale |

### OAuth client

Admin console → Settings → OAuth clients. Operator needs Devices/Routes **write**
(with appropriate tags). See [../tailscale.md](../tailscale.md).

### Deploy behavior

A full Linux/K3s `deploy-infra.sh` run installs the operator through Ansible.
Talos and operator-only re-runs use:

```bash
cd ansible
HOMELAB_ROOT="$(pwd)/.." ANSIBLE_CONFIG=ansible.cfg \
  ansible-playbook playbooks/deploy-tailscale.yml \
  -i inventories/<ENV_ID>/hosts.yml
```

A `--helm-only` run reconciles application Ingress resources but assumes the
operator and `IngressClass/tailscale` already exist. The role reuses an existing
`kubeconfigs/<ENV_ID>.kubeconfig` and fetches one only when missing.

## Verify

```bash
kubectl get pods -n tailscale
kubectl get ingress -A
kubectl get ingressclass tailscale
kubectl get connector -A   # empty when subnet routing is disabled
# Devices appear in Tailscale admin console
```

## Related

- [tailscale-exporter.md](tailscale-exporter.md)
- [../tailscale.md](../tailscale.md)
