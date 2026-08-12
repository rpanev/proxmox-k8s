# SNAPSHOT_CONTROLLER_ENABLED

Installs Kubernetes **VolumeSnapshot** CRDs + `snapshot-controller`
([external-snapshotter](https://github.com/kubernetes-csi/external-snapshotter)
via [piraeus-charts](https://piraeus.io/helm-charts/)).

**Required for Kasten CSI volume backups / DR** (and Longhorn CSI snapshots).
Without this, Kasten can still back up resources, but PVC data snapshots fail.

## Enable

```bash
SNAPSHOT_CONTROLLER_ENABLED=true   # default when unset: true if LONGHORN or KASTEN
```

Deploy order in one `./deploy-infra.sh` run:

1. Critical path: install CRDs + controller (**ServiceMonitor off** — Prometheus not up yet)
2. After Prometheus: same deploy automatically re-upgrades with **ServiceMonitor on**

Creates VolumeSnapshotClass `longhorn` with:

```yaml
annotations:
  k10.kasten.io/is-snapshot-class: "true"
parameters:
  type: snap   # local Longhorn snap — no Backup Target; Kasten exports to NFS
```

## Check

```bash
kubectl get crd | grep snapshot.storage.k8s.io
kubectl -n kube-system get deploy snapshot-controller
kubectl get volumesnapshotclass
```

## Related

- [kasten.md](kasten.md) — uses this for PVC snapshots
- [longhorn.md](longhorn.md) — CSI driver `driver.longhorn.io`
