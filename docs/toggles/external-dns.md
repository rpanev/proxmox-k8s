# EXTERNAL_DNS_ENABLED

Creates Cloudflare **A records** from Gateway HTTPRoutes → `GATEWAY_LB_IP`.

## Enable

```bash
GATEWAY_ENABLED=true
EXTERNAL_DNS_ENABLED=true
CLOUDFLARE_API_TOKEN=...
EXTERNAL_DNS_DOMAIN_FILTER=panev.cloud   # apex zone, NOT homelab.panev.cloud
CLOUDFLARE_DNS_PROXIED=false
```

## Behavior

Deploys `external-dns` watching HTTPRoutes / related Gateway resources and
upserting DNS in the Cloudflare zone.

Requires a working Gateway stack — see [gateway.md](gateway.md).

## Configuration

| Variable | Description |
|----------|-------------|
| `EXTERNAL_DNS_DOMAIN_FILTER` | Cloudflare **apex** hosted zone |
| `CLOUDFLARE_API_TOKEN` | Same token as cert-manager (Zone:DNS:Edit) |
| `CLOUDFLARE_DNS_PROXIED` | Grey cloud for private IPs |

Helm values: `helm-homelab/external-dns/values.yaml`.

## Verify

```bash
kubectl logs -n external-dns deploy/external-dns --tail=50
# Cloudflare DNS should show A records for grafana., argocd., etc.
```

## Pitfalls

- Filter set to subdomain → no zone match → silent skip
- Orange cloud + private IP → broken reachability

## Related

- [../cloudflare-gateway.md](../cloudflare-gateway.md)
- [gateway.md](gateway.md)
