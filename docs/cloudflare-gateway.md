# Gateway API + Cloudflare TLS

Envoy Gateway (Gateway API) on a MetalLB IP, cert-manager with Cloudflare
DNS-01, external-dns for HTTPRoute A records. Needs `GATEWAY_ENABLED=true`
(and `EXTERNAL_DNS_ENABLED=true` for DNS). See
[toggles/gateway.md](toggles/gateway.md) and
[toggles/external-dns.md](toggles/external-dns.md).

This LAN path can run in parallel with Tailscale MagicDNS ingress. Tailscale
uses separate proxy pods and hostnames and does not replace the Gateway,
MetalLB, Cloudflare DNS, or HTTPRoutes described here.

```bash
# MetalLB IP on LAN — free address in 192.168.99.200-219 (210 = K8s API LB)
GATEWAY_LB_IP=192.168.99.211
GATEWAY_DOMAIN=homelab.panev.cloud
ACME_EMAIL=dev@panev.cloud
LETSENCRYPT_STAGING=false
# Cloudflare API token: Zone:DNS:Edit for panev.cloud (covers homelab.panev.cloud)
CLOUDFLARE_API_TOKEN=...
# DNS only (grey cloud) — required for private LAN IP
CLOUDFLARE_DNS_PROXIED=false
# Cloudflare hosted zone (apex). Auto-derived from GATEWAY_DOMAIN when empty.
EXTERNAL_DNS_DOMAIN_FILTER=panev.cloud
```

| Variable | Description |
|----------|--------------|
| `GATEWAY_LB_IP` | The LoadBalancer IP MetalLB assigns to the Envoy Gateway. Must be a **free** address on your LAN, outside the DHCP range. Here `.211` (note `.210` is the K3s API HAProxy LB). |
| `GATEWAY_DOMAIN` | Base domain for all ingress hostnames. Services resolve as `<hostname>.<GATEWAY_DOMAIN>` (e.g. `grafana.homelab.panev.cloud`). |
| `ACME_EMAIL` | Contact email for the Let's Encrypt account (expiry notices). |
| `LETSENCRYPT_STAGING` | `true` uses the Let's Encrypt **staging** CA (untrusted certs, high rate limits) for testing. `false` = production, trusted certs. |
| `CLOUDFLARE_API_TOKEN` | Scoped Cloudflare token used by **both** cert-manager (DNS-01 challenge) and external-dns (A records). Treat as a secret. |
| `CLOUDFLARE_DNS_PROXIED` | `false` = grey cloud (DNS only) — **required** when the target is a private LAN IP. `true` = orange cloud (proxied), only valid with a public IP + port forwarding. |
| `EXTERNAL_DNS_DOMAIN_FILTER` | The Cloudflare **hosted zone (apex)**, e.g. `panev.cloud`. external-dns operates only within this zone. Leave empty to auto-derive from `GATEWAY_DOMAIN`'s last two labels. |

> **Why the apex zone matters:** the Cloudflare zone is the registered domain
> (`panev.cloud`), even though services live under `homelab.panev.cloud`. If the
> filter is set to the subdomain, external-dns cannot find a matching zone and
> silently skips all records. Always use the apex.

---

## How to generate the Cloudflare API token

The same token is shared by cert-manager and external-dns, so it needs DNS edit
rights on the zone.

1. Cloudflare dashboard → **My Profile → API Tokens → Create Token**.
2. Use the **Edit zone DNS** template (or create a custom token).
3. Permissions:
   - **Zone → DNS → Edit**
   - (cert-manager also benefits from **Zone → Zone → Read**)
4. Zone Resources: **Include → Specific zone → `panev.cloud`**.
5. Create, then copy the token into `CLOUDFLARE_API_TOKEN` (shown once).

Verify the token:

```bash
curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  https://api.cloudflare.com/client/v4/user/tokens/verify
```

---

## Universal SSL blocks DNS-01

Cloudflare **Universal SSL** reserves `_acme-challenge.*` for its own edge
certificates. cert-manager can create the TXT record via the API (and
`1.1.1.1` DoH may show it), but **public recursive DNS (UDP/TCP) returns
NXDOMAIN** — so Let's Encrypt and cert-manager never complete DNS-01.

Before the first deploy (or if the wildcard cert stays `Ready: False` with
*Waiting for DNS-01 challenge propagation*):

1. Cloudflare dashboard → zone **`panev.cloud`** → **SSL/TLS** →
   **Edge Certificates**
2. **Disable Universal SSL** (temporarily is fine for homelab grey-cloud DNS)
3. **DNS** → delete stale `_acme-challenge` TXT records if present
4. Re-run: `./deploy-infra.sh -y --os=talos --helm-only`

The deploy script runs a preflight (`verify_cloudflare_acme_dns01_ready`) before
cert-manager and fails early with this hint if `_acme-challenge` still does not
resolve publicly.

Re-enable Universal SSL after the Let's Encrypt cert is `Ready` if you use
orange-cloud records elsewhere; grey-cloud gateway records are unaffected.

---

## How it fits together

```
HTTPRoute (host: grafana.homelab.panev.cloud)
        │
        ├─ external-dns ─────► Cloudflare A record → GATEWAY_LB_IP (192.168.99.211)
        │                       (zone: EXTERNAL_DNS_DOMAIN_FILTER, grey cloud)
        │
        ├─ cert-manager ─────► Let's Encrypt cert via Cloudflare DNS-01
        │                       (CLOUDFLARE_API_TOKEN, ACME_EMAIL)
        │
        └─ Envoy Gateway ────► MetalLB LoadBalancer on GATEWAY_LB_IP
```

A client on the LAN resolves `grafana.homelab.panev.cloud` → `192.168.99.211`,
hits Envoy Gateway, and gets a trusted TLS certificate.

> For LAN-only resolution without Cloudflare, point your router/local DNS at
> `GATEWAY_LB_IP`. With external-dns + grey-cloud records, public DNS already
> returns the private IP (resolvable only from inside the LAN).
