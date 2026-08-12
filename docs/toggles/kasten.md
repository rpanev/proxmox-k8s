# KASTEN_ENABLED

Veeam Kasten (K10) for Kubernetes backup / restore / DR.

Backup target for this lab: **NFS** `192.168.99.50:/volume1/k8s-dr`
(not Proxmox `SSD-storage` — that is only for VM disks).

## Enable (after cluster rebuild)

```bash
KASTEN_ENABLED=true
VELERO_ENABLED=false   # pick one backup stack

KASTEN_NFS_SERVER=192.168.99.50
KASTEN_NFS_PATH=/volume1/k8s-dr
KASTEN_NFS_SIZE=1Ti
KASTEN_LOCATION_PROFILE=nfs-k8s-dr
KASTEN_STORAGE_CLASS=longhorn-1r
```

`deploy_kasten()` will:

1. Create StorageClass `longhorn-1r` (+ VolumeSnapshotClass `longhorn` if snapshot CRDs exist)
2. Helm install `kasten/k10` into `kasten-io`
3. Bind static NFS PV/PVC and create Location Profile `nfs-k8s-dr` (FileStore)
4. Create Policy `homelab-all-apps`: **all current namespaces** (minus excludes),
   `@daily` backup + export to NFS. New namespaces are picked up on the next deploy.
5. Create Policy `k10-disaster-recovery` for `kasten-io` itself (Kasten forbids
   covering K10 via a normal `*` / all-apps policy)

```bash
KASTEN_POLICY_ENABLED=true
KASTEN_POLICY_FREQUENCY=@daily
KASTEN_POLICY_HOUR=2
KASTEN_POLICY_EXCLUDE=kube-system,kube-public,kube-node-lease,kasten-io
KASTEN_DR_POLICY_ENABLED=true
```


**Prerequisite:** `SNAPSHOT_CONTROLLER_ENABLED=true` (CSI VolumeSnapshot CRDs) — see
[snapshot-controller.md](snapshot-controller.md). Without it, Kasten cannot take PVC snapshots.

On Talos, Kasten installs **after** the parallel Helm stack (needs CRDs before NFS
Location Profile). `wait_for_crd` polls until `profiles.config.kio.kasten.io` exists.

**Note:** Kasten rejects `In: ["*"]` for app policies (forces K10 DR for `kasten-io`).
Deploy builds an explicit namespace list (minus excludes) on each run so new NS are
included after the next `deploy-infra` / `deploy_kasten`.


Export ACL must allow the cluster subnet (e.g. `172.16.33.0/24`):

```text
showmount -e 192.168.99.50
# /volume1/k8s-dr   172.16.33.1/24,...
```

## UI

With Gateway (`GATEWAY_ENABLED`):

```text
https://kasten.homelab.panev.cloud/k10/
```

(`/` redirects to `/k10/`. Override host with `KASTEN_HOSTNAME`.)

Fallback without Gateway:

```bash
kubectl -n kasten-io port-forward svc/gateway 8080:80
# http://127.0.0.1:8080/k10/#/
```

## Notes

- Free/Starter: ≤ 5 worker nodes
- Needs Longhorn (`LONGHORN_ENABLED=true`)
- CSI volume snapshots: [snapshot-controller.md](snapshot-controller.md) (`SNAPSHOT_CONTROLLER_ENABLED`)
- Grafana: `helm-homelab/grafana/dashboards/kasten-k10.json` (tags `backup`, `kasten`, `k10`)
  uses Grafana datasource **Kasten** → `prometheus-server.kasten-io/k10/prometheus`
  (not the cluster Prometheus — K10 metrics live only there)

## Related

- [velero.md](velero.md) — optional S3/MinIO alternative
- [longhorn.md](longhorn.md) — in-cluster volumes
- [ceph-storage.md](ceph-storage.md) — Proxmox VM disk datastore (separate from Kasten NFS)
