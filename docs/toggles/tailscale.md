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
TAILSCALE_SUBNET_ROUTER_ENABLED=true
# TAILSCALE_EXTRA_ROUTES=10.42.0.0/16,10.43.0.0/16
TAILSCALE_API_SERVER_PROXY=false
```

## Behavior

- Installs Tailscale operator via Helm (Ansible localhost role / deploy path)
- Optionally applies ACL fragment from the repo
- Optional subnet router advertising LAN (+ extra routes)
- Cleanup on destroy via Tailscale API

## Configuration

| Variable | Description |
|----------|-------------|
| `TAILSCALE_TAILNET` | Tailnet DNS name |
| `TAILSCALE_OAUTH_CLIENT_*` | OAuth client for operator |
| `TAILSCALE_APPLY_ACL` | Push ACL fragment on deploy |
| `TAILSCALE_SUBNET_ROUTER_ENABLED` | Advertise LAN routes |
| `TAILSCALE_EXTRA_ROUTES` | Extra CIDRs |
| `TAILSCALE_API_SERVER_PROXY` | Expose K8s API via Tailscale |
| `TAILSCALE_LOGIN_SERVER` | Empty = Tailscale SaaS; set for Headscale |

### OAuth client

Admin console → Settings → OAuth clients. Operator needs Devices/Routes **write**
(with appropriate tags). See [../tailscale.md](../tailscale.md).

## Verify

```bash
kubectl get pods -n tailscale
# Devices appear in Tailscale admin console
```

## Related

- [tailscale-exporter.md](tailscale-exporter.md)
- [../tailscale.md](../tailscale.md)
