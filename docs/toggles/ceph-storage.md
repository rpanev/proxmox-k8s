# CEPH_STORAGE

Controls whether Proxmox VM disks use **Ceph RBD** or the non-Ceph datastore
(`PROXMOX_DATASTORE_ID`, typically NFS `SSD-storage`).

## Enable Ceph

```bash
CEPH_STORAGE=true
```

## Use NFS (SSD-storage) instead

```bash
CEPH_STORAGE=false
PROXMOX_SHARED_STORAGE=true
PROXMOX_DATASTORE_ID=SSD-storage
```

| Variable | Role |
|----------|------|
| `CEPH_STORAGE=true` | Disks on `ceph_datastore_id` (e.g. `ceph-prod`); serial TF clones |
| `CEPH_STORAGE=false` | Disks on `PROXMOX_DATASTORE_ID` / `local_datastore_id` |
| `PROXMOX_SHARED_STORAGE` | Spread VMs across `proxmox_nodes` (needed for shared NFS) |
| `PROXMOX_DATASTORE_ID` | Proxmox storage ID when Ceph is off (default `SSD-storage`) |

## Behavior

| Value | Effect |
|-------|--------|
| `true` | VM disks on Ceph; VMs spread across nodes; deploy may use `-parallelism=1` |
| `false` + shared NFS | VM disks on `SSD-storage`; VMs still spread when `PROXMOX_SHARED_STORAGE=true` |
| `false` + local only | Set `PROXMOX_SHARED_STORAGE=false` and pin to `target_node` / `local-lvm` |

Hand-edited defaults live in each stack’s `terraform.tfvars`; deploy writes
overrides into `secrets.auto.tfvars`.

```hcl
ceph               = false
shared_storage     = true
ceph_datastore_id  = "ceph-prod"
local_datastore_id = "SSD-storage"
proxmox_nodes      = ["node1", "node2", "node3", "node4", "node5"]
```

## Verify

```bash
# After terraform apply — VM disks should show SSD-storage (or Ceph) in Proxmox
cd terrafrom/talos-linux && terraform output
```

## Related

- [../proxmox.md](../proxmox.md)
- [../backup.md](../backup.md) — Proxmox NFS vs Kasten NFS vs Longhorn
- [longhorn.md](longhorn.md) — Longhorn is **in-cluster** storage; Ceph/NFS here is for Proxmox VM disks
- [kasten.md](kasten.md) — app backup (separate from Proxmox datastore)
