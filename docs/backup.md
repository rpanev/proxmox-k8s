# Backup & storage — what is what

Three separate layers. Mixing them up is the usual source of confusion.

| Layer | Component | What it protects | Toggle / setting |
|-------|-----------|------------------|------------------|
| **Proxmox VM disks** | Shared NFS `SSD-storage` (or Ceph) | Leader/worker/LB VM images; live migration / HA | `CEPH_STORAGE=false`, `PROXMOX_SHARED_STORAGE=true`, `PROXMOX_DATASTORE_ID=SSD-storage` — [toggles/ceph-storage.md](toggles/ceph-storage.md) |
| **In-cluster volumes** | **Longhorn** | PVC data while apps run | `LONGHORN_ENABLED` — [toggles/longhorn.md](toggles/longhorn.md) |
| **App backup / DR** | **Kasten K10** (preferred) or Velero | Namespaces + PVC snapshots → off-cluster store | `KASTEN_ENABLED` or `VELERO_ENABLED` |

```
Proxmox nodes
  └── VMs on SSD-storage (NFS) or Ceph     ← hypervisor storage / live migrate
        └── Kubernetes (Talos or K3s)
              └── Longhorn PVCs              ← runtime block storage
                    └── Kasten snapshots     ← CSI VolumeSnapshot (type=snap)
                          └── export → NAS   ← KASTEN_NFS_* (≠ Proxmox SSD-storage)
```

## Longhorn vs Kasten

| | Longhorn | Kasten (K10) |
|--|----------|--------------|
| Job | Provide disks (PVC → replicas on workers) | Backup / restore / export apps |
| UI | `https://longhorn.<GATEWAY_DOMAIN>` | `https://kasten.<GATEWAY_DOMAIN>/k10/` |
| Needs the other? | No | Yes — PVC data via CSI snapshots on Longhorn |

Flow on a Kasten backup of a namespace with PVCs:

1. K10 inventories the app (YAML + PVCs).
2. CSI **VolumeSnapshot** → Longhorn (`VolumeSnapshotClass longhorn`, `parameters.type: snap`).
3. K10 **exports** the restore point to Location Profile `nfs-k8s-dr` (`KASTEN_NFS_SERVER`/`PATH`).

Local Longhorn snaps do **not** need a Longhorn Backup Target. Export is Kasten’s job.

CSI plumbing: [toggles/snapshot-controller.md](toggles/snapshot-controller.md).

## Two different NFS exports

| Export | Used by | Example |
|--------|---------|---------|
| Proxmox datastore | VM disks / live migration | `192.168.99.48:…/proxmox-storage-sata` → storage id `SSD-storage` |
| Kasten Location | App backup export | `192.168.99.50:/volume1/k8s-dr` → profile `nfs-k8s-dr` |

Do not point Kasten at Proxmox `SSD-storage` or the reverse.

## Policies (when `KASTEN_ENABLED=true`)

| Policy | Scope | Default schedule |
|--------|--------|------------------|
| `homelab-all-apps` | All namespaces except `KASTEN_POLICY_EXCLUDE` | `@daily` @ 02:00 + export |
| `k10-disaster-recovery-policy` | `kasten-io` only (required name) | `@daily` @ 03:00 |

Kasten rejects `In: ["*"]` for normal app policies (K10 must use the DR policy). Deploy rebuilds the explicit namespace list each run — new NS appear after the next `deploy_kasten` / full deploy.

**Compliant** in the UI means covered by a policy **and** a successful backup in window. A brand-new policy is Non-Compliant until the first run (schedule or Run Once).

DR passphrase (store offline): `secrets/<ENV_ID>/kasten-dr-passphrase`.

## Velero alternative

Set `VELERO_ENABLED=true` and `KASTEN_ENABLED=false` for S3/MinIO backups. Prefer one stack, not both. See [toggles/velero.md](toggles/velero.md).

## Related

- [toggles/kasten.md](toggles/kasten.md)
- [toggles/longhorn.md](toggles/longhorn.md)
- [toggles/snapshot-controller.md](toggles/snapshot-controller.md)
- [toggles/ceph-storage.md](toggles/ceph-storage.md)
- [architecture.md](architecture.md)
