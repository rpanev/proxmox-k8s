# CEPH_STORAGE

Controls whether Proxmox VM disks are placed on **Ceph** shared storage.

## Enable

```bash
CEPH_STORAGE=true
```

## Behavior

| Value | Effect |
|-------|--------|
| `true` | VM disks on `ceph_datastore_id` (e.g. `ceph-prod`); VMs spread across `proxmox_nodes`; deploy auto-sets Terraform `-parallelism=1` |
| `false` | Local datastore (`local-lvm`); VMs pinned to `target_node` / non-Ceph placement |

Configured in each stack’s `terraform.tfvars`:

```hcl
ceph               = true   # also driven from secrets via secrets.auto.tfvars
ceph_datastore_id  = "ceph-prod"
local_datastore_id = "local-lvm"
proxmox_nodes      = ["node1", "node2", "node3", "node4", "node5"]
```

## Configuration

| Variable / file | Role |
|-----------------|------|
| `CEPH_STORAGE` | Toggle in `secrets.env` → written to `secrets.auto.tfvars` as `ceph` |
| `terrafrom/*/terraform.tfvars` | Datastore IDs, node lists, LB/CP/worker placement |

## Verify

```bash
# After terraform apply — VM disks should show Ceph storage in Proxmox UI
cd terrafrom/talos-linux && terraform output
```

## Related

- [../proxmox.md](../proxmox.md)
- [longhorn.md](longhorn.md) — Longhorn is **in-cluster** storage; Ceph is for Proxmox VM disks
