# KASTEN_ENABLED

Veeam Kasten (K10) for Kubernetes backup / restore / DR.

**Longhorn ≠ Kasten.** Longhorn is in-cluster PVC storage; Kasten is the backup
product. Overview of both (and Proxmox NFS): [../backup.md](../backup.md).

Backup export target for this lab: **NFS** `KASTEN_NFS_SERVER`:`KASTEN_NFS_PATH`
(e.g. `192.168.99.50:/volume1/k8s-dr`) — **not** Proxmox `SSD-storage` (VM disks).

## Enable (after cluster rebuild)

```bash
KASTEN_ENABLED=true
VELERO_ENABLED=false   # pick one backup stack

KASTEN_NFS_SERVER=192.168.99.50
KASTEN_NFS_PATH=/volume1/k8s-dr
KASTEN_NFS_SIZE=1Ti          # PVC claim size (metadata); not NAS pre-allocation
KASTEN_LOCATION_PROFILE=nfs-k8s-dr
KASTEN_STORAGE_CLASS=longhorn-1r
KASTEN_HOSTNAME=kasten
```

`deploy_kasten()` will:

1. Create StorageClass `longhorn-1r` + VolumeSnapshotClass `longhorn`
   (`parameters.type: snap` — local Longhorn snap, no Longhorn Backup Target)
2. Helm install `kasten/k10` into `kasten-io`
3. Bind static NFS PV/PVC and Location Profile `nfs-k8s-dr` (FileStore)
4. Policy `homelab-all-apps`: all current namespaces minus excludes,
   `@daily` backup + export to NFS (list refreshed each deploy)
5. Policy `k10-disaster-recovery-policy` for `kasten-io` (exact name required)

```bash
KASTEN_POLICY_ENABLED=true
KASTEN_POLICY_NAME=homelab-all-apps
KASTEN_POLICY_FREQUENCY=@daily
KASTEN_POLICY_HOUR=2
KASTEN_POLICY_RETENTION_DAILY=7
KASTEN_POLICY_RETENTION_WEEKLY=4
KASTEN_POLICY_RETENTION_MONTHLY=3
KASTEN_POLICY_EXCLUDE=kube-system,kube-public,kube-node-lease,kasten-io

KASTEN_DR_POLICY_ENABLED=true
KASTEN_DR_POLICY_FREQUENCY=@daily
KASTEN_DR_POLICY_HOUR=3
KASTEN_DR_POLICY_RETENTION_DAILY=7
```

**Prerequisites:**

- `LONGHORN_ENABLED=true`
- `SNAPSHOT_CONTROLLER_ENABLED=true` (default on with Longhorn/Kasten) —
  [snapshot-controller.md](snapshot-controller.md)
- NFS export ACL allows the cluster subnet (e.g. `172.16.33.0/24`)

```text
showmount -e 192.168.99.50
# /volume1/k8s-dr   172.16.33.0/24,...
```

On Talos, Kasten installs **after** the parallel Helm stack (needs CRDs before the
NFS Location Profile). `wait_for_crd` polls until `profiles.config.kio.kasten.io`
exists.

**Note:** Kasten rejects `In: ["*"]` for app policies (use K10 DR for `kasten-io`).
Deploy builds an explicit namespace list (minus excludes) so new NS are included
after the next `deploy-infra` / `deploy_kasten`.

## UI

With Gateway:

```text
https://kasten.<GATEWAY_DOMAIN>/k10/
```

(`/` redirects to `/k10/`. Override host with `KASTEN_HOSTNAME`.)

Without Gateway:

```bash
kubectl -n kasten-io port-forward svc/gateway 8080:80
# http://127.0.0.1:8080/k10/#/
```

## Compliance / first run

Apps show **Non-Compliant** until a successful policy backup exists (schedule
defaults to 02:00). Run Once from the UI, or:

```bash
kubectl -n kasten-io create -f - <<'EOF'
apiVersion: actions.kio.kasten.io/v1alpha1
kind: RunAction
metadata:
  generateName: run-homelab-all-apps-
  namespace: kasten-io
spec:
  subject:
    apiVersion: config.kio.kasten.io/v1alpha1
    kind: Policy
    name: homelab-all-apps
    namespace: kasten-io
EOF
```

## K10 Disaster Recovery

Policy name must be `k10-disaster-recovery-policy`. Passphrase is read from
`KASTEN_DR_PASSPHRASE` or auto-written to
`secrets/<ENV_ID>/kasten-dr-passphrase` — **store a copy offline** for catalog
restore.

## Grafana

Dashboard `helm-homelab/grafana/dashboards/kasten-k10.json` (tags `backup`,
`kasten`, `k10`) uses Grafana datasource **Kasten** →
`http://prometheus-server.kasten-io.svc/k10/prometheus`
(not cluster Prometheus — K10 metrics live only there).

## Verify

```bash
kubectl get pods -n kasten-io
kubectl get profiles.config.kio.kasten.io -n kasten-io
kubectl get policies.config.kio.kasten.io -n kasten-io
kubectl get volumesnapshotclass longhorn -o yaml   # expect parameters.type: snap
```

## Notes

- Free/Starter: ≤ 5 worker nodes
- Virtual Machines page is for KubeVirt / infra profiles — **not** Proxmox VMs
- Infrastructure Profile (AWS/vSphere/…) is unused here; Location Profile NFS is enough

## Related

- [../backup.md](../backup.md) — Longhorn vs Kasten vs Proxmox NFS
- [velero.md](velero.md) — S3 alternative (keep disabled when Kasten is on)
- [longhorn.md](longhorn.md) — PVC storage
- [snapshot-controller.md](snapshot-controller.md) — CSI VolumeSnapshots
- [ceph-storage.md](ceph-storage.md) — Proxmox VM datastore (separate NFS)
