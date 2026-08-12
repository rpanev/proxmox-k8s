# Getting started

## 1. Prerequisites

On the **deploy host**:

- `terraform` or `opentofu`
- `ansible-playbook`, `python3`
- `kubectl`, `helm`
- `talosctl` (only for `--os=talos`)

On **Proxmox**:

- API token (`PROXMOX_API_TOKEN`) — see [proxmox.md](proxmox.md)
- Cloud-init template for the API LB (`TEMPLATE_*`, Debian)
- Talos cloud image for CP/workers when using Talos (`TALOS_TEMPLATE_*`)

## 2. Configure secrets

```bash
cp secrets.env.example secrets.env
```

Edit at least:

- Proxmox endpoint + API token
- `SSH_PUBLIC_KEY`, network (`IP_BASE`, `NETWORK_GATEWAY`)
- `ENV_ID`, `LEADER_COUNT`, `WORKER_COUNT`
- Platform toggles you need — see [toggles/](toggles/README.md)

## 3. Configure VM placement

| Stack | File |
|-------|------|
| K3s | `terrafrom/linux/terraform.tfvars` |
| Talos | `terrafrom/talos-linux/terraform.tfvars` |

Proxmox node names are `node1`…`node5`. Templates must point at the node where
the template VM actually lives (`template_node` / `lb_template_node`).

## 4. Deploy

```bash
./deploy-infra.sh -y --os=talos    # or --os=linux
```

Useful flags:

| Flag | Meaning |
|------|---------|
| `-y` | Auto-approve Terraform |
| `--helm-only` | Re-run Helm (cluster already up) |
| `--infra-only` | Terraform + inventory only |
| `--serial-clones` | Force serial VM clones (also auto with `CEPH_STORAGE=true`) |

## 5. Verify

```bash
export KUBECONFIG=kubeconfigs/<ENV_ID>.kubeconfig
kubectl get nodes
kubectl get httproute -A
```

Service URLs: `https://<hostname>.<GATEWAY_DOMAIN>` (when Gateway is enabled).

### Optional: Kasten backup

If `KASTEN_ENABLED=true` (and `VELERO_ENABLED=false`):

```bash
kubectl get policies.config.kio.kasten.io -n kasten-io
kubectl get profiles.config.kio.kasten.io -n kasten-io
# UI: https://kasten.<GATEWAY_DOMAIN>/k10/
```

Longhorn is PVC storage; Kasten is backup — see [backup.md](backup.md).
Apps stay Non-Compliant until the first successful policy run (02:00 by default
or Run Once in the UI).

## 6. Tear down

```bash
./destroy-infra.sh -y --os=talos
```

Keeps `secrets.env`. Removes inventories, kubeconfigs, generated tfvars, etc.

## Next

- [architecture.md](architecture.md) — what got created
- [backup.md](backup.md) — Proxmox NFS / Longhorn / Kasten
- [toggles/](toggles/README.md) — enable optional platform pieces
- [cloudflare-gateway.md](cloudflare-gateway.md) — if TLS/DNS fails
