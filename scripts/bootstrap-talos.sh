#!/usr/bin/env bash
# Bootstrap Talos cluster: gen config → apply-config → bootstrap → kubeconfig.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_secrets
apply_platform_toggles
set_tf_dir

if [[ "${TALOS_ENABLED}" != "true" ]]; then
  echo "error: bootstrap-talos.sh requires TALOS_ENABLED=true" >&2
  exit 1
fi

TF="$(terraform_bin)"
cd "${TF_DIR}"

GEN_DIR="${HOMELAB_ROOT}/generated/talos/${ENV_ID}"
KUBECONFIG_OUT="$(kubeconfig_path)"
INSTALL_DISK="${TALOS_INSTALL_DISK:-/dev/sda}"
CLUSTER_NAME="${TALOS_CLUSTER_NAME:-${ENV_ID}}"
LONGHORN_VOL="${TALOS_LONGHORN_VOLUME_NAME:-longhorn-data}"

if ! command -v talosctl >/dev/null 2>&1; then
  echo "error: talosctl not found — install: https://www.talos.dev/v1.13/talos-guides/install/talosctl/" >&2
  exit 1
fi

API_URL="$(${TF} output -json talos_lb | python3 -c 'import json,sys; print(json.load(sys.stdin)["api_url"])')"
LB_IP="$(${TF} output -json talos_lb | python3 -c 'import json,sys; print(json.load(sys.stdin)["ip"])')"

mapfile -t CP_IPS < <(${TF} output -json talos_controlplane_nodes | python3 -c '
import json,sys
for n in json.load(sys.stdin):
    print(n["ip"])
')

mapfile -t WORKER_IPS < <(${TF} output -json talos_worker_nodes | python3 -c '
import json,sys
for n in json.load(sys.stdin):
    print(n["ip"])
')

mkdir -p "${GEN_DIR}" "${HOMELAB_ROOT}/kubeconfigs"

FIRST_CP_EARLY="${CP_IPS[0]}"
TALOS_ENDPOINTS_EARLY=$(IFS=,; echo "${CP_IPS[*]}")

# Re-running full deploy must not talosctl gen config (new PKI) over a live cluster —
# apply-config then fails with "tls: certificate required".
talos_cluster_exists() {
  [[ -f "${GEN_DIR}/talosconfig" ]] || return 1
  [[ -f "${KUBECONFIG_OUT}" ]] || return 1
  talosctl --talosconfig "${GEN_DIR}/talosconfig" \
    --nodes "${FIRST_CP_EARLY}" --endpoints "${FIRST_CP_EARLY}" \
    version >/dev/null 2>&1 || return 1
  local i
  for i in 1 2 3 4 5 6; do
    if KUBECONFIG="${KUBECONFIG_OUT}" kubectl get nodes --request-timeout=30s >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  return 1
}

if talos_cluster_exists; then
  echo "==> Existing Talos cluster detected — skip bootstrap (reuse talosconfig)"
  talosctl kubeconfig "${KUBECONFIG_OUT}" \
    --force \
    --nodes "${FIRST_CP_EARLY}" \
    --endpoints "${TALOS_ENDPOINTS_EARLY}" \
    --talosconfig "${GEN_DIR}/talosconfig"
  chmod 600 "${KUBECONFIG_OUT}"
  echo ""
  echo "Kubeconfig: ${KUBECONFIG_OUT}"
  echo "Talosconfig: ${GEN_DIR}/talosconfig"
  echo "  export KUBECONFIG=${KUBECONFIG_OUT}"
  echo "  kubectl get nodes"
  exit 0
fi

REGEN_CONFIG="${TALOS_REGEN_CONFIG:-1}"
if [[ "${REGEN_CONFIG}" == "1" ]]; then
  rm -f "${GEN_DIR}/talosconfig" "${GEN_DIR}/controlplane.yaml" "${GEN_DIR}/worker.yaml"
  echo "==> talosctl gen config ${CLUSTER_NAME} ${API_URL}"
  talosctl gen config "${CLUSTER_NAME}" "${API_URL}" \
    --output-dir "${GEN_DIR}" \
    --with-docs=false \
    --with-examples=false
else
  echo "==> Reusing existing Talos config in ${GEN_DIR} (TALOS_REGEN_CONFIG=0)"
  [[ -f "${GEN_DIR}/talosconfig" ]] || { echo "error: missing ${GEN_DIR}/talosconfig" >&2; exit 1; }
fi

patch_install_disk() {
  local file="$1"
  python3 - "${file}" "${INSTALL_DISK}" <<'PY'
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit(2)

path, disk = Path(sys.argv[1]), sys.argv[2]
text = path.read_text()
docs = list(yaml.safe_load_all(text))
if not docs:
    sys.exit(1)

patched = False
for doc in docs:
    if isinstance(doc, dict) and "machine" in doc:
        doc.setdefault("machine", {}).setdefault("install", {})["disk"] = disk
        patched = True
        break

if not patched:
    sys.exit(1)

out = []
for i, doc in enumerate(docs):
    if i:
        out.append("---\n")
    out.append(yaml.dump(doc, default_flow_style=False, sort_keys=False))
path.write_text("".join(out))
PY
}

# Proxmox cloud-init IP is not reliable after talosctl upgrade/reboot — bake static
# addresses into machine config (one file per node IP).
write_node_machine_config() {
  local base_file="$1" out_file="$2" node_ip="$3"
  python3 - "${base_file}" "${out_file}" "${node_ip}" \
    "${NETWORK_GATEWAY}" "${NETWORK_CIDR:-24}" "${DNS_SERVERS:-1.1.1.1}" <<'PY'
import shlex
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit(2)

base, out, ip, gateway, cidr, dns_raw = sys.argv[1:7]
docs = list(yaml.safe_load_all(Path(base).read_text()))
if not docs:
    sys.exit(1)

dns_servers = [s for s in shlex.split(dns_raw) if s]
if not dns_servers:
    dns_servers = ["1.1.1.1"]

patched = False
for doc in docs:
    if isinstance(doc, dict) and "machine" in doc:
        doc.setdefault("machine", {})["network"] = {
            "interfaces": [
                {
                    "deviceSelector": {"physical": True},
                    "dhcp": False,
                    "addresses": [f"{ip}/{cidr}"],
                    "routes": [{"network": "0.0.0.0/0", "gateway": gateway}],
                }
            ],
            "nameservers": dns_servers,
        }
        patched = True
        break

if not patched:
    sys.exit(1)

parts = []
for i, doc in enumerate(docs):
    if i:
        parts.append("---\n")
    parts.append(yaml.dump(doc, default_flow_style=False, sort_keys=False))
Path(out).write_text("".join(parts))
PY
}

patch_longhorn_volume() {
  local file="$1"
  python3 - "${file}" "${LONGHORN_VOL}" "${LONGHORN_DATA_DISK_FSTYPE:-xfs}" <<'PY'
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit(2)

path = Path(sys.argv[1])
name, fstype = sys.argv[2], sys.argv[3]
docs = list(yaml.safe_load_all(path.read_text()))

# Proxmox: sda ~32G OS, sdb ~50G data — both transport "virtio".
# volumeType:disk CEL has no system_disk; select data disk by size.
volume = {
    "apiVersion": "v1alpha1",
    "kind": "UserVolumeConfig",
    "name": name,
    "volumeType": "disk",
    "provisioning": {
        "diskSelector": {"match": "disk.transport == 'virtio' && disk.size > 40u * GB"},
    },
    "filesystem": {"type": fstype},
}

updated = False
for i, doc in enumerate(docs):
    if isinstance(doc, dict) and doc.get("kind") == "UserVolumeConfig" and doc.get("name") == name:
        docs[i] = volume
        updated = True
        break

if not updated:
    docs.append(volume)

out = []
for i, doc in enumerate(docs):
    if i:
        out.append("---\n")
    out.append(yaml.dump(doc, default_flow_style=False, sort_keys=False))
path.write_text("".join(out))
PY
}

# Longhorn needs iscsiadm/fstrim — K3s gets open-iscsi via Ansible; Talos needs Image Factory extensions.
resolve_talos_installer_schematic() {
  if [[ -n "${TALOS_INSTALLER_SCHEMATIC:-}" ]]; then
    echo "${TALOS_INSTALLER_SCHEMATIC}"
    return 0
  fi
  python3 <<'PY'
import json
import urllib.request

payload = {
    "customization": {
        "systemExtensions": {
            "officialExtensions": [
                "siderolabs/iscsi-tools",
                "siderolabs/util-linux-tools",
                "siderolabs/qemu-guest-agent",
            ]
        }
    }
}
req = urllib.request.Request(
    "https://factory.talos.dev/schematics",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
with urllib.request.urlopen(req, timeout=60) as resp:
    print(json.load(resp)["id"])
PY
}

patch_talos_longhorn_machine() {
  local file="$1" schematic="$2"
  python3 - "${file}" "${schematic}" <<'PY'
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit(2)

path = Path(sys.argv[1])
schematic = sys.argv[2]
docs = list(yaml.safe_load_all(path.read_text()))
patched = False

for doc in docs:
    if not isinstance(doc, dict) or "machine" not in doc:
        continue
    machine = doc["machine"]
    install = machine.setdefault("install", {})
    image = install.get("image", "ghcr.io/siderolabs/installer:v1.13.4")
    version = image.rsplit(":", 1)[-1]
    install["image"] = f"factory.talos.dev/installer/{schematic}:{version}"

    kernel = machine.setdefault("kernel", {})
    modules = kernel.setdefault("modules", [])
    existing = {m.get("name") for m in modules if isinstance(m, dict)}
    for mod in ("iscsi_tcp",):
        if mod not in existing:
            modules.append({"name": mod})
    patched = True
    break

if not patched:
    sys.exit(1)

out = []
for i, doc in enumerate(docs):
    if i:
        out.append("---\n")
    out.append(yaml.dump(doc, default_flow_style=False, sort_keys=False))
path.write_text("".join(out))
PY
}

read_talos_installer_image() {
  local file="${1:?config file}"
  python3 - "${file}" <<'PY'
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit(2)

for doc in yaml.safe_load_all(Path(sys.argv[1]).read_text()):
    if isinstance(doc, dict) and "machine" in doc:
        image = doc.get("machine", {}).get("install", {}).get("image", "")
        if image:
            print(image)
        break
PY
}

talos_node_has_iscsi_tools() {
  local ip="$1"
  if talosctl --talosconfig "${GEN_DIR}/talosconfig" get extensions \
      --nodes "${ip}" --endpoints "${ip}" 2>/dev/null | grep -q iscsi-tools; then
    return 0
  fi
  env -u TALOSCONFIG talosctl -n "${ip}" get extensions --insecure 2>/dev/null | grep -q iscsi-tools
}

# ExtensionStatus controller populates a bit after the Talos API returns post-reboot,
# so poll instead of checking once (avoids false negatives that abort bootstrap).
talos_node_wait_iscsi_tools() {
  local ip="$1" attempts="${2:-24}"
  local i
  for ((i = 0; i < attempts; i++)); do
    if talos_node_has_iscsi_tools "${ip}"; then
      return 0
    fi
    sleep 5
  done
  return 1
}

# Longhorn schedules only on workers (control planes are tainted NoSchedule), so
# iscsi-tools is required on workers only. Fall back to control planes for
# single-node / all-in-one clusters with no dedicated workers.
longhorn_node_ips() {
  if [[ ${#WORKER_IPS[@]} -gt 0 ]]; then
    printf '%s\n' "${WORKER_IPS[@]}"
  else
    printf '%s\n' "${CP_IPS[@]}"
  fi
}

talos_cluster_needs_longhorn_upgrade() {
  if [[ "$(hcl_bool "${LONGHORN_ENABLED:-false}")" != "true" ]]; then
    return 1
  fi
  local installer_image
  installer_image="$(read_talos_installer_image "${GEN_DIR}/worker.yaml" 2>/dev/null)" || installer_image=""
  if [[ -z "${installer_image}" || "${installer_image}" != factory.talos.dev/* ]]; then
    installer_image="$(read_talos_installer_image "${GEN_DIR}/controlplane.yaml" 2>/dev/null)" || installer_image=""
  fi
  if [[ -z "${installer_image}" || "${installer_image}" != factory.talos.dev/* ]]; then
    return 1
  fi
  local ip
  while IFS= read -r ip; do
    [[ -n "${ip}" ]] || continue
    if ! talos_node_has_iscsi_tools "${ip}"; then
      return 0
    fi
  done < <(longhorn_node_ips)
  return 1
}

wait_talos_api_all_nodes() {
  local ip ready
  echo "==> Waiting for Talos API on all nodes..."
  for ip in "$@"; do
    ready=0
    for _ in $(seq 1 120); do
      if talosctl --talosconfig "${GEN_DIR}/talosconfig" version \
          --nodes "${ip}" --endpoints "${ip}" >/dev/null 2>&1; then
        ready=1
        break
      fi
      if env -u TALOSCONFIG talosctl -n "${ip}" version --insecure >/dev/null 2>&1; then
        ready=1
        break
      fi
      sleep 5
    done
    if [[ ${ready} -ne 1 ]]; then
      echo "error: Talos API not reachable on ${ip}" >&2
      return 1
    fi
    echo "    ${ip} ready"
  done
}

talosctl_ensure_longhorn_extensions() {
  if ! talos_cluster_needs_longhorn_upgrade; then
    echo "==> Talos factory extensions OK (iscsi-tools present)"
    return 0
  fi
  echo "==> Cloned VMs lack iscsi-tools — factory installer upgrade required for Longhorn"
  talosctl_upgrade_longhorn_installer

  local ip missing=0
  while IFS= read -r ip; do
    [[ -n "${ip}" ]] || continue
    if ! talos_node_wait_iscsi_tools "${ip}"; then
      echo "warning: iscsi-tools still missing on ${ip} after factory upgrade" >&2
      missing=1
    fi
  done < <(longhorn_node_ips)
  if [[ ${missing} -ne 0 ]]; then
    echo "error: iscsi-tools missing on worker node(s) — check Image Factory / network" >&2
    return 1
  fi
}

talosctl_upgrade_longhorn_installer() {
  if [[ "$(hcl_bool "${LONGHORN_ENABLED:-false}")" != "true" ]]; then
    return 0
  fi

  local installer_image upgrade_timeout ip
  installer_image="$(read_talos_installer_image "${GEN_DIR}/worker.yaml" 2>/dev/null)" || installer_image=""
  if [[ -z "${installer_image}" || "${installer_image}" != factory.talos.dev/* ]]; then
    installer_image="$(read_talos_installer_image "${GEN_DIR}/controlplane.yaml" 2>/dev/null)" || installer_image=""
  fi
  if [[ -z "${installer_image}" || "${installer_image}" != factory.talos.dev/* ]]; then
    echo "warning: no factory.talos.dev installer image in config — skip talosctl upgrade" >&2
    return 0
  fi

  upgrade_timeout="${TALOS_UPGRADE_TIMEOUT:-15m}"
  local -a all_ips=()
  while IFS= read -r ip; do
    [[ -n "${ip}" ]] && all_ips+=("${ip}")
  done < <(longhorn_node_ips)

  echo "==> talosctl upgrade — factory installer with iscsi-tools + util-linux-tools (worker nodes)"
  echo "    (each node reboots ~3–5 min; sequential upgrade, no Kubernetes drain)"
  for ip in "${all_ips[@]}"; do
    echo "    ${ip}"
    # Do not use --wait here: before bootstrap it waits for Kubernetes and hangs ~30m+.
    if ! talosctl --talosconfig "${GEN_DIR}/talosconfig" upgrade \
        --nodes "${ip}" --endpoints "${ip}" \
        --image "${installer_image}" --wait=false --timeout "${upgrade_timeout}" \
        --drain=false; then
      echo "    ${ip} (fallback: insecure upgrade)" >&2
      env -u TALOSCONFIG talosctl upgrade --insecure -n "${ip}" --endpoints "${ip}" \
        --image "${installer_image}" --timeout "${upgrade_timeout}" --wait=false --drain=false
    fi
    echo "    ${ip} waiting for Talos API after reboot..."
    local ready=0
    for _ in $(seq 1 180); do
      if talosctl --talosconfig "${GEN_DIR}/talosconfig" version \
          --nodes "${ip}" --endpoints "${ip}" >/dev/null 2>&1; then
        ready=1
        break
      fi
      if env -u TALOSCONFIG talosctl -n "${ip}" version --insecure >/dev/null 2>&1; then
        ready=1
        break
      fi
      sleep 5
    done
    if [[ ${ready} -ne 1 ]]; then
      echo "error: ${ip} did not return after upgrade within 15m" >&2
      return 1
    fi
    if talos_node_wait_iscsi_tools "${ip}"; then
      echo "    ${ip} iscsi-tools extension OK"
    else
      echo "warning: iscsi-tools extension not visible on ${ip} after upgrade" >&2
    fi
  done
}

for f in controlplane.yaml worker.yaml; do
  if [[ -f "${GEN_DIR}/${f}" ]]; then
    rc=0
    patch_install_disk "${GEN_DIR}/${f}" || rc=$?
    if [[ ${rc} -eq 2 ]]; then
      echo "warning: python3-yaml not installed — verify machine.install.disk=${INSTALL_DISK} in ${GEN_DIR}/${f}" >&2
    elif [[ ${rc} -ne 0 ]]; then
      echo "warning: could not patch install disk in ${GEN_DIR}/${f} (rc=${rc})" >&2
    else
      echo "    patched machine.install.disk=${INSTALL_DISK} in ${f}"
    fi
  fi
done

if [[ "$(hcl_bool "${LONGHORN_ENABLED}")" == "true" ]]; then
  schematic=""
  if schematic="$(resolve_talos_installer_schematic 2>/dev/null)"; then
    for f in controlplane.yaml worker.yaml; do
      if [[ -f "${GEN_DIR}/${f}" ]]; then
        rc=0
        patch_talos_longhorn_machine "${GEN_DIR}/${f}" "${schematic}" || rc=$?
        if [[ ${rc} -eq 2 ]]; then
          echo "warning: python3-yaml not installed — Longhorn Talos extensions not patched in ${f}" >&2
        elif [[ ${rc} -ne 0 ]]; then
          echo "warning: could not patch Longhorn installer extensions in ${f} (rc=${rc})" >&2
        else
          echo "    patched Longhorn extensions (iscsi-tools, util-linux-tools) in ${f}"
        fi
      fi
    done
  else
    echo "warning: could not resolve Talos Image Factory schematic — set TALOS_INSTALLER_SCHEMATIC in secrets.env" >&2
  fi

  if [[ -f "${GEN_DIR}/worker.yaml" ]]; then
    rc=0
    patch_longhorn_volume "${GEN_DIR}/worker.yaml" || rc=$?
    if [[ ${rc} -eq 2 ]]; then
      echo "warning: python3-yaml not installed — Longhorn data volume not patched in worker.yaml" >&2
    elif [[ ${rc} -ne 0 ]]; then
      echo "warning: could not patch Longhorn UserVolumeConfig in worker.yaml (rc=${rc})" >&2
    else
      echo "    patched UserVolumeConfig ${LONGHORN_VOL} (scsi1 volumeType=disk → /var/mnt/${LONGHORN_VOL}) in worker.yaml"
    fi
  fi
fi

echo "==> Waiting for Talos maintenance API on control planes..."
for ip in "${CP_IPS[@]}"; do
  for _ in $(seq 1 60); do
    if talosctl -n "${ip}" version --insecure >/dev/null 2>&1; then
      echo "    ${ip} ready"
      break
    fi
    sleep 5
  done
done

APPLY_MODE="${TALOS_APPLY_MODE:-reboot}"
NODE_CFG_DIR="${GEN_DIR}/node-configs"
mkdir -p "${NODE_CFG_DIR}"

echo "==> talosctl apply-config (control planes, --mode=${APPLY_MODE})"
for ip in "${CP_IPS[@]}"; do
  echo "    ${ip}"
  write_node_machine_config "${GEN_DIR}/controlplane.yaml" "${NODE_CFG_DIR}/controlplane-${ip}.yaml" "${ip}"
  talosctl apply-config --insecure -n "${ip}" --mode "${APPLY_MODE}" --file "${NODE_CFG_DIR}/controlplane-${ip}.yaml"
done

if [[ ${#WORKER_IPS[@]} -gt 0 ]]; then
  echo "==> Waiting for workers (post-reboot)..."
  for ip in "${WORKER_IPS[@]}"; do
    for _ in $(seq 1 60); do
      if talosctl -n "${ip}" version --insecure >/dev/null 2>&1; then
        break
      fi
      sleep 5
    done
  done
  echo "==> talosctl apply-config (workers, --mode=${APPLY_MODE})"
  for ip in "${WORKER_IPS[@]}"; do
    echo "    ${ip}"
    write_node_machine_config "${GEN_DIR}/worker.yaml" "${NODE_CFG_DIR}/worker-${ip}.yaml" "${ip}"
    talosctl apply-config --insecure -n "${ip}" --mode "${APPLY_MODE}" --file "${NODE_CFG_DIR}/worker-${ip}.yaml"
  done
fi

FIRST_CP="${CP_IPS[0]}"
TALOS_ENDPOINTS=$(IFS=,; echo "${CP_IPS[*]}")
ALL_NODE_IPS=("${CP_IPS[@]}")
if [[ ${#WORKER_IPS[@]} -gt 0 ]]; then
  ALL_NODE_IPS+=("${WORKER_IPS[@]}")
fi

wait_talos_api_all_nodes "${ALL_NODE_IPS[@]}"

# Proxmox clones keep the template OS — machine.install.image in config does not
# install extensions until talosctl upgrade. Run before bootstrap so Kubernetes
# never sees duplicate Node objects after upgrade.
talosctl_ensure_longhorn_extensions
wait_talos_api_all_nodes "${ALL_NODE_IPS[@]}"

echo "==> talosctl bootstrap (first CP ${FIRST_CP}; K8s API stays on LB ${LB_IP}:6443)"
bootstrap_ok=0
for _ in $(seq 1 120); do
  set +e
  bootstrap_out="$(talosctl bootstrap \
    --nodes "${FIRST_CP}" \
    --endpoints "${FIRST_CP}" \
    --talosconfig "${GEN_DIR}/talosconfig" 2>&1)"
  bootstrap_rc=$?
  set -e
  if [[ ${bootstrap_rc} -eq 0 ]]; then
    echo "${bootstrap_out}"
    bootstrap_ok=1
    break
  fi
  if echo "${bootstrap_out}" | grep -qiE 'already bootstrapped|etcd cluster has already been bootstrapped'; then
    echo "    already bootstrapped — continuing"
    bootstrap_ok=1
    break
  fi
  if echo "${bootstrap_out}" | grep -qiE 'bootstrap is not available yet|time is not in sync yet|connection refused|EOF'; then
    sleep 5
    continue
  fi
  echo "${bootstrap_out}" >&2
  exit "${bootstrap_rc}"
done
if [[ ${bootstrap_ok} -eq 0 ]]; then
  echo "error: bootstrap timed out — check: talosctl -n ${FIRST_CP} services (ext-qemu-guest-agent, etcd)" >&2
  exit 1
fi

HEALTH_TIMEOUT="${TALOS_HEALTH_TIMEOUT:-15m}"
echo "==> Waiting for cluster health (timeout ${HEALTH_TIMEOUT}; Talos API via CP, K8s API via ${API_URL})..."
if ! talosctl --talosconfig "${GEN_DIR}/talosconfig" \
    --nodes "${FIRST_CP}" --endpoints "${TALOS_ENDPOINTS}" \
    health --wait-timeout="${HEALTH_TIMEOUT}"; then
  echo "warning: talosctl health did not pass within ${HEALTH_TIMEOUT}" >&2
fi

talosctl kubeconfig "${KUBECONFIG_OUT}" \
  --force \
  --nodes "${FIRST_CP}" \
  --endpoints "${TALOS_ENDPOINTS}" \
  --talosconfig "${GEN_DIR}/talosconfig"

chmod 600 "${KUBECONFIG_OUT}"

echo ""
echo "Kubeconfig: ${KUBECONFIG_OUT}"
echo "Talosconfig: ${GEN_DIR}/talosconfig"
echo "  export KUBECONFIG=${KUBECONFIG_OUT}"
echo "  kubectl get nodes"
