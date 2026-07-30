#!/usr/bin/env bash
# Shared helpers for homelab deploy scripts.

set -euo pipefail

_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
HOMELAB_ROOT="$(cd "${_lib_dir}/../.." && pwd)"
ENV_ID="${ENV_ID:-homelab}"
SECRETS_FILE="${HOMELAB_ROOT}/secrets.env"
TF_ROOT="${HOMELAB_ROOT}/terrafrom"
TF_DIR="${TF_ROOT}/linux"
TFVARS_AUTO="${TF_DIR}/secrets.auto.tfvars"
SECRETS_DIR="${HOMELAB_ROOT}/secrets/${ENV_ID}"
K3S_TOKEN_FILE="${SECRETS_DIR}/k3s_token"
ANSIBLE_VARS_DIR="${HOMELAB_ROOT}/ansible/inventories/${ENV_ID}/group_vars"
GENERATED_DIR="${HOMELAB_ROOT}/scripts/generated"
HOMELAB_SSH_KNOWN_HOSTS="${HOMELAB_ROOT}/.ssh/known_hosts"

load_secrets() {
  if [[ ! -f "${SECRETS_FILE}" ]]; then
    echo "error: missing ${SECRETS_FILE} (copy from secrets.env.example)" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  set -a && source "${SECRETS_FILE}" && set +a
}

apply_platform_toggles() {
  export CEPH_STORAGE="$(hcl_bool "${CEPH_STORAGE:-true}")"
  export TALOS_ENABLED="$(hcl_bool "${TALOS_ENABLED:-false}")"
  export TAILSCALE_ENABLED="$(hcl_bool "${TAILSCALE_ENABLED:-true}")"
  export LONGHORN_ENABLED="$(hcl_bool "${LONGHORN_ENABLED:-true}")"
  export DATADOG_ENABLED="$(hcl_bool "${DATADOG_ENABLED:-true}")"
  export ARGOCD_ENABLED="$(hcl_bool "${ARGOCD_ENABLED:-true}")"
  export VELERO_ENABLED="$(hcl_bool "${VELERO_ENABLED:-false}")"
  export GATEWAY_ENABLED="$(hcl_bool "${GATEWAY_ENABLED:-true}")"
  export EXTERNAL_DNS_ENABLED="$(hcl_bool "${EXTERNAL_DNS_ENABLED:-true}")"
  export SEALED_SECRETS_ENABLED="$(hcl_bool "${SEALED_SECRETS_ENABLED:-true}")"
  export RELOADER_ENABLED="$(hcl_bool "${RELOADER_ENABLED:-true}")"
  export ARGOCD_BOOTSTRAP_ENABLED="$(hcl_bool "${ARGOCD_BOOTSTRAP_ENABLED:-true}")"
  export PROMETHEUS_ENABLED="$(hcl_bool "${PROMETHEUS_ENABLED:-true}")"
  export ALERTMANAGER_ENABLED="$(hcl_bool "${ALERTMANAGER_ENABLED:-false}")"
  export LOKI_ENABLED="$(hcl_bool "${LOKI_ENABLED:-false}")"
  export TRIVY_OPERATOR_ENABLED="$(hcl_bool "${TRIVY_OPERATOR_ENABLED:-false}")"

  if [[ "$(hcl_bool "${LONGHORN_ENABLED:-false}")" == "true" ]]; then
    export LONGHORN_MOUNT_PATH="${LONGHORN_MOUNT_PATH:-/var/mnt/longhorn-data}"
  fi

  echo "==> platform: os=${HOMELAB_OS:-linux} talos=${TALOS_ENABLED} ceph=${CEPH_STORAGE} tailscale=${TAILSCALE_ENABLED} longhorn=${LONGHORN_ENABLED} datadog=${DATADOG_ENABLED} prometheus=${PROMETHEUS_ENABLED} loki=${LOKI_ENABLED} trivy=${TRIVY_OPERATOR_ENABLED} alertmanager=${ALERTMANAGER_ENABLED} argocd=${ARGOCD_ENABLED} velero=${VELERO_ENABLED} gateway=${GATEWAY_ENABLED} sealed-secrets=${SEALED_SECRETS_ENABLED} reloader=${RELOADER_ENABLED}"
}

hcl_list() {
  local raw="${1:-}"
  if [[ -z "${raw// }" ]]; then
    echo "[]"
    return
  fi
  local out="["
  local first=1 part
  for part in ${raw}; do
    [[ ${first} -eq 1 ]] || out+=", "
    out+="\"${part}\""
    first=0
  done
  out+="]"
  echo "${out}"
}

hcl_bool() {
  case "${1,,}" in
    true|1|yes) echo "true" ;;
    *) echo "false" ;;
  esac
}

# Platform OS: linux (K3s) or talos. CLI --os= wins over secrets.env TALOS_ENABLED.
resolve_homelab_os() {
  local os="${HOMELAB_OS:-}"
  if [[ -z "${os}" ]]; then
    if [[ "$(hcl_bool "${TALOS_ENABLED:-false}")" == "true" ]]; then
      os=talos
    else
      os=linux
    fi
  fi
  case "${os,,}" in
    talos) export HOMELAB_OS=talos TALOS_ENABLED=true ;;
    linux) export HOMELAB_OS=linux TALOS_ENABLED=false ;;
    *)
      echo "error: invalid OS '${os}' — use linux or talos" >&2
      return 1
      ;;
  esac
}

# Select terrafrom/linux (K3s) or terrafrom/talos-linux from HOMELAB_OS / TALOS_ENABLED.
set_tf_dir() {
  if [[ "$(hcl_bool "${TALOS_ENABLED:-false}")" == "true" ]]; then
    TF_DIR="${TF_ROOT}/talos-linux"
  else
    TF_DIR="${TF_ROOT}/linux"
  fi
  TFVARS_AUTO="${TF_DIR}/secrets.auto.tfvars"
}

terraform_stack_name() {
  if [[ "$(hcl_bool "${TALOS_ENABLED:-false}")" == "true" ]]; then
    echo "talos-linux"
  else
    echo "linux"
  fi
}

# Writes only secrets.auto.tfvars — terraform.tfvars stays hand-edited per stack.
# Caller must run load_secrets (+ resolve_homelab_os for --os=…) before this.
write_tfvars() {
  # load_secrets resets TALOS_ENABLED from secrets.env — preserve CLI --os=… choice.
  local saved_os="${HOMELAB_OS:-}"
  load_secrets
  if [[ -n "${saved_os}" ]]; then
    export HOMELAB_OS="${saved_os}"
    resolve_homelab_os
  fi
  set_tf_dir

  if [[ "$(hcl_bool "${TALOS_ENABLED:-false}")" == "true" ]]; then
    write_tfvars_talos
  else
    write_tfvars_linux
  fi
}

write_tfvars_linux() {
  : "${PROXMOX_ENDPOINT:?PROXMOX_ENDPOINT required}"
  : "${PROXMOX_API_TOKEN:?PROXMOX_API_TOKEN required}"
  : "${IP_BASE:?IP_BASE required}"
  : "${NETWORK_GATEWAY:?NETWORK_GATEWAY required}"
  : "${SSH_PUBLIC_KEY:?SSH_PUBLIC_KEY required}"
  : "${LEADER_COUNT:?LEADER_COUNT required}"
  : "${WORKER_COUNT:?WORKER_COUNT required}"
  : "${TEMPLATE_VM_ID:?TEMPLATE_VM_ID required}"
  : "${ENV_ID:?ENV_ID required}"

  cat >"${TFVARS_AUTO}" <<EOF
# Generated from secrets.env — do not edit by hand.

# ===== Proxmox API =====
proxmox_endpoint     = "${PROXMOX_ENDPOINT}"
proxmox_api_token    = "${PROXMOX_API_TOKEN}"
proxmox_insecure     = $(hcl_bool "${PROXMOX_INSECURE:-true}")
proxmox_ssh_username = "${PROXMOX_SSH_USERNAME:-root}"

# ===== Proxmox template & pool =====
template_name  = "${TEMPLATE_NAME:-almalinux10-cloud}"
template_vm_id = ${TEMPLATE_VM_ID}
template_node  = "${TEMPLATE_NODE:-node4}"
env_id         = "${ENV_ID}"

# ===== SSH / cloud-init =====
ssh_user       = "${SSH_USER:-root}"
ssh_password   = "${SSH_PASSWORD:-}"
ssh_public_key = "${SSH_PUBLIC_KEY}"

# ===== Network =====
network_bridge  = "${NETWORK_BRIDGE:-vmbr0}"
network_gateway = "${NETWORK_GATEWAY}"
network_cidr    = ${NETWORK_CIDR:-24}
ip_base         = "${IP_BASE}"
vlan_tag        = ${VLAN_TAG:-0}
dns_domain      = "${DNS_DOMAIN:-panev.cloud}"
dns_servers     = $(hcl_list "${DNS_SERVERS:-1.1.1.1}")

# ===== K8s cluster size =====
leader_count = ${LEADER_COUNT}
worker_count = ${WORKER_COUNT}

# ===== Storage (from deploy-infra.sh platform toggles) =====
ceph                     = $(hcl_bool "${CEPH_STORAGE:-true}")
worker_data_disk_enabled = $(hcl_bool "${LONGHORN_ENABLED:-true}")
worker_data_disk_gb      = ${WORKER_DATA_DISK_GB:-30}

# ===== Proxmox VM tags =====
vm_tags = $(hcl_list "${VM_TAGS:-k8s terraform}")
EOF

  chmod 600 "${TFVARS_AUTO}"
  echo "wrote ${TFVARS_AUTO} (stack: linux)"
}

write_tfvars_talos() {
  : "${PROXMOX_ENDPOINT:?PROXMOX_ENDPOINT required}"
  : "${PROXMOX_API_TOKEN:?PROXMOX_API_TOKEN required}"
  : "${IP_BASE:?IP_BASE required}"
  : "${NETWORK_GATEWAY:?NETWORK_GATEWAY required}"
  : "${SSH_PUBLIC_KEY:?SSH_PUBLIC_KEY required for HAProxy LB}"
  : "${LEADER_COUNT:?LEADER_COUNT required}"
  : "${WORKER_COUNT:?WORKER_COUNT required}"
  : "${ENV_ID:?ENV_ID required}"

  cat >"${TFVARS_AUTO}" <<EOF
# Generated from secrets.env — do not edit by hand.

proxmox_endpoint     = "${PROXMOX_ENDPOINT}"
proxmox_api_token    = "${PROXMOX_API_TOKEN}"
proxmox_insecure     = $(hcl_bool "${PROXMOX_INSECURE:-true}")
proxmox_ssh_username = "${PROXMOX_SSH_USERNAME:-root}"

env_id = "${ENV_ID}"

ssh_user       = "${SSH_USER:-root}"
ssh_password   = "${SSH_PASSWORD:-}"
ssh_public_key = "${SSH_PUBLIC_KEY}"

network_bridge  = "${NETWORK_BRIDGE:-vmbr0}"
network_gateway = "${NETWORK_GATEWAY}"
network_cidr    = ${NETWORK_CIDR:-24}
ip_base         = "${IP_BASE}"
vlan_tag        = ${VLAN_TAG:-0}
dns_domain      = "${DNS_DOMAIN:-panev.cloud}"
dns_servers     = $(hcl_list "${DNS_SERVERS:-1.1.1.1}")

controlplane_count = ${LEADER_COUNT}
worker_count       = ${WORKER_COUNT}

ceph                     = $(hcl_bool "${CEPH_STORAGE:-true}")
worker_data_disk_enabled = $(hcl_bool "${LONGHORN_ENABLED:-true}")
worker_data_disk_gb      = ${WORKER_DATA_DISK_GB:-50}
vm_tags                  = $(hcl_list "${VM_TAGS:-k8s terraform}")
EOF

  chmod 600 "${TFVARS_AUTO}"
  echo "wrote ${TFVARS_AUTO} (stack: talos-linux)"
}

setup_k3s_token() {
  # Persist token outside Terraform — Ansible only, never TF_VAR.
  mkdir -p "${SECRETS_DIR}"
  chmod 700 "${SECRETS_DIR}"

  if [[ -z "${K3S_TOKEN:-}" && -r "${K3S_TOKEN_FILE}" ]]; then
    local existing=""
    existing="$(tr -d '\r\n' <"${K3S_TOKEN_FILE}" | sed -E 's/[[:space:]]+//g' || true)"
    if [[ -n "${existing}" && "${existing}" =~ ^K3S-[A-Za-z0-9._:-]+-TOKEN$ ]]; then
      export K3S_TOKEN="${existing}"
    fi
  fi

  if [[ -z "${K3S_TOKEN:-}" ]]; then
    if command -v openssl >/dev/null 2>&1; then
      export K3S_TOKEN="K3S-$(openssl rand -hex 8)-TOKEN"
    else
      export K3S_TOKEN="K3S-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')-TOKEN"
    fi
    echo "generated new k3s token → ${K3S_TOKEN_FILE}"
  fi

  if [[ -n "${K3S_TOKEN:-}" ]]; then
    umask 077
    printf '%s' "${K3S_TOKEN}" >"${K3S_TOKEN_FILE}"
    chmod 600 "${K3S_TOKEN_FILE}"
  fi
}

write_ansible_k3s_vars() {
  : "${K3S_TOKEN:?K3S_TOKEN required}"
  : "${K3S_VERSION:?K3S_VERSION required — set in secrets.env}"
  mkdir -p "${ANSIBLE_VARS_DIR}"
  local extra_tls_block="k3s_extra_tls_sans: []"
  if [[ -n "${GATEWAY_DOMAIN:-}" ]]; then
    extra_tls_block="k3s_extra_tls_sans:
  - \"${GATEWAY_DOMAIN}\""
  fi
  cat >"${ANSIBLE_VARS_DIR}/k3s.yml" <<EOF
# Generated by deploy-infra.sh — do not edit by hand.
k3s_token: "${K3S_TOKEN}"
k3s_version: "${K3S_VERSION}"
${extra_tls_block}
EOF
  chmod 600 "${ANSIBLE_VARS_DIR}/k3s.yml"
  echo "wrote ${ANSIBLE_VARS_DIR}/k3s.yml"
}

write_ansible_tailscale_vars() {
  load_secrets
  local all_vars_dir="${ANSIBLE_VARS_DIR}/all"
  mkdir -p "${all_vars_dir}"
  local enabled
  enabled="$(hcl_bool "${TAILSCALE_ENABLED:-false}")"

  # Must live under group_vars/all/ — there is no inventory group named "tailscale".
  if [[ "${enabled}" == "true" ]]; then
    : "${TAILSCALE_OAUTH_CLIENT_ID:?TAILSCALE_OAUTH_CLIENT_ID required when TAILSCALE_ENABLED=true}"
    : "${TAILSCALE_OAUTH_CLIENT_SECRET:?TAILSCALE_OAUTH_CLIENT_SECRET required when TAILSCALE_ENABLED=true}"
    local subnet_router_enabled
    subnet_router_enabled="$(hcl_bool "${TAILSCALE_SUBNET_ROUTER_ENABLED:-true}")"
    local extra_routes_block=""
    if [[ -n "${TAILSCALE_EXTRA_ROUTES:-}" ]]; then
      extra_routes_block="tailscale_extra_routes:"
      local part
      for part in ${TAILSCALE_EXTRA_ROUTES//,/ }; do
        part="${part// /}"
        [[ -n "${part}" ]] || continue
        extra_routes_block+=$'\n'"  - \"${part}\""
      done
    fi
    cat >"${all_vars_dir}/tailscale.yml" <<EOF
# Generated by deploy-infra.sh — do not edit by hand.
# env_id, homelab_network_cidr, tailscale_proxy_tag: from Terraform → inventory hosts.yml
tailscale_enabled: true
tailscale_oauth_client_id: "${TAILSCALE_OAUTH_CLIENT_ID}"
tailscale_oauth_client_secret: "${TAILSCALE_OAUTH_CLIENT_SECRET}"
tailscale_tailnet: "${TAILSCALE_TAILNET:-}"
tailscale_login_server: "${TAILSCALE_LOGIN_SERVER:-}"
tailscale_api_server_proxy: $(hcl_bool "${TAILSCALE_API_SERVER_PROXY:-false}")
tailscale_subnet_router_enabled: ${subnet_router_enabled}
${extra_routes_block}
EOF
  else
    cat >"${all_vars_dir}/tailscale.yml" <<EOF
# Generated by deploy-infra.sh — do not edit by hand.
tailscale_enabled: false
EOF
  fi

  rm -f "${ANSIBLE_VARS_DIR}/tailscale.yml"
  chmod 600 "${all_vars_dir}/tailscale.yml"
  echo "wrote ${all_vars_dir}/tailscale.yml"
}

write_ansible_longhorn_vars() {
  load_secrets
  local all_vars_dir="${ANSIBLE_VARS_DIR}/all"
  mkdir -p "${all_vars_dir}"
  local enabled disk_gb mount_path fstype
  enabled="$(hcl_bool "${LONGHORN_ENABLED:-true}")"
  disk_gb="${WORKER_DATA_DISK_GB:-30}"
  mount_path="${LONGHORN_MOUNT_PATH:-/var/mnt/longhorn-data}"
  fstype="${LONGHORN_DATA_DISK_FSTYPE:-xfs}"

  cat >"${all_vars_dir}/longhorn.yml" <<EOF
# Generated by deploy-infra.sh — do not edit by hand.
longhorn_enabled: ${enabled}
longhorn_data_disk_gb: ${disk_gb}
longhorn_mount_path: "${mount_path}"
longhorn_data_disk_fstype: "${fstype}"
EOF
  echo "wrote ${all_vars_dir}/longhorn.yml"
}

write_ansible_loki_vars() {
  load_secrets
  local all_vars_dir="${HOMELAB_ROOT}/ansible/inventories/${ENV_ID}/group_vars/all"
  mkdir -p "${all_vars_dir}"
  local enabled push_host
  enabled="$(hcl_bool "${LOKI_ENABLED:-false}")"
  push_host="${LOKI_PUSH_HOST:-}"
  if [[ -z "${push_host}" ]]; then
    local inventory="${HOMELAB_ROOT}/ansible/inventories/${ENV_ID}/hosts.yml"
    if [[ -f "${inventory}" ]]; then
      push_host="$(python3 - "${inventory}" <<'PY' 2>/dev/null || true
import sys, yaml
with open(sys.argv[1]) as f:
    inv = yaml.safe_load(f)
children = inv.get("all", {}).get("children", {})

def first_ansible_host(group_name: str) -> str:
    hosts = (children.get(group_name) or {}).get("hosts") or {}
    if not hosts:
        return ""
    return next(iter(hosts.values())).get("ansible_host", "") or ""

for group in (
    "k3s_first_leader",
    "talos_workers",
    "talos_controlplane",
):
    ip = first_ansible_host(group)
    if ip:
        print(ip)
        break
PY
)"
    fi
  fi
  cat >"${all_vars_dir}/loki.yml" <<EOF
# Generated by deploy-infra.sh — do not edit by hand.
loki_promtail_enabled: ${enabled}
loki_gateway_node_port: ${LOKI_GATEWAY_NODE_PORT:-31080}
loki_push_host: "${push_host}"
EOF
  echo "wrote ${all_vars_dir}/loki.yml"
}

setup_k3s_version() {
  # Set in secrets.env; fallback to GitHub latest if empty.
  if [[ -n "${K3S_VERSION:-}" ]]; then
    export K3S_VERSION
    return
  fi
  local latest
  latest="$(curl -fsSL https://api.github.com/repos/k3s-io/k3s/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+' || true)"
  K3S_VERSION="${latest:-v1.36.1+k3s1}"
  export K3S_VERSION
  echo "K3S_VERSION not set in secrets.env, using ${K3S_VERSION}"
}

terraform_bin() {
  if command -v terraform >/dev/null 2>&1; then
    echo terraform
  elif command -v tofu >/dev/null 2>&1; then
    echo tofu
  else
    echo "error: terraform or tofu not found" >&2
    exit 1
  fi
}

prepare_ssh_known_host() {
  local host="${1:?host required}"
  mkdir -p "$(dirname "${HOMELAB_SSH_KNOWN_HOSTS}")"
  touch "${HOMELAB_SSH_KNOWN_HOSTS}"
  chmod 600 "${HOMELAB_SSH_KNOWN_HOSTS}"
  ssh-keygen -R "${host}" -f "${HOMELAB_SSH_KNOWN_HOSTS}" >/dev/null 2>&1 || true
  ssh-keyscan -H "${host}" 2>/dev/null >>"${HOMELAB_SSH_KNOWN_HOSTS}" || true
}

homelab_ssh_opts() {
  local -a opts=(
    -o ConnectTimeout=10
    -o StrictHostKeyChecking=yes
    -o UserKnownHostsFile="${HOMELAB_SSH_KNOWN_HOSTS}"
    -o LogLevel=ERROR
  )
  if [[ -n "${ANSIBLE_SSH_PRIVATE_KEY_FILE:-}" ]]; then
    opts+=(-i "${ANSIBLE_SSH_PRIVATE_KEY_FILE}")
  fi
  printf '%s\n' "${opts[@]}"
}

helm_repo_ensure() {
  local name="${1:?repo name required}" url="${2:?repo url required}"
  helm repo add "${name}" "${url}" >/dev/null 2>&1 || true
  helm repo update "${name}" >/dev/null 2>&1
}

generate_inventory() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
  "${script_dir}/generate-inventory.sh"
}

generate_tailscale_acl() {
  local script_dir tf
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
  tf="$(terraform_bin)"
  local out_dir="${GENERATED_DIR}"
  local out_file="${out_dir}/tailscale-acl-fragment.json"
  mkdir -p "${out_dir}"
  cd "${TF_DIR}"
  if ! ${tf} output -json tailscale >/dev/null 2>&1; then
    echo "skip tailscale ACL (terraform output tailscale not available yet)" >&2
    return 0
  fi
  ${tf} output -json | python3 "${script_dir}/generate-tailscale-acl.py" >"${out_file}.tmp"
  mv "${out_file}.tmp" "${out_file}"
  chmod 644 "${out_file}"
  echo "wrote ${out_file}"
}

apply_tailscale_acl() {
  load_secrets
  if [[ "$(hcl_bool "${TAILSCALE_ENABLED:-false}")" != "true" ]]; then
    return 0
  fi
  if [[ "$(hcl_bool "${TAILSCALE_APPLY_ACL:-true}")" != "true" ]]; then
    echo "skip Tailscale ACL apply (TAILSCALE_APPLY_ACL=false)"
    return 0
  fi

  : "${TAILSCALE_TAILNET:?TAILSCALE_TAILNET required when TAILSCALE_ENABLED=true}"
  : "${TAILSCALE_OAUTH_CLIENT_ID:?TAILSCALE_OAUTH_CLIENT_ID required}"
  : "${TAILSCALE_OAUTH_CLIENT_SECRET:?TAILSCALE_OAUTH_CLIENT_SECRET required}"

  local script_dir fragment
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
  fragment="${GENERATED_DIR}/tailscale-acl-fragment.json"
  if [[ ! -f "${fragment}" ]]; then
    echo "error: missing ${fragment} — run terraform apply and generate-inventory first" >&2
    return 1
  fi

  echo "==> apply Tailscale ACL (merge autoApprovers + tagOwners)"
  export HOMELAB_ROOT TAILSCALE_TAILNET TAILSCALE_OAUTH_CLIENT_ID TAILSCALE_OAUTH_CLIENT_SECRET
  export TAILSCALE_ACL_FRAGMENT="${fragment}"
  python3 "${script_dir}/apply-tailscale-acl.py"
}

run_ansible() {
  if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "error: ansible-playbook not found" >&2
    exit 1
  fi

  local inventory="${HOMELAB_ROOT}/ansible/inventories/${ENV_ID}/hosts.yml"
  if [[ ! -f "${inventory}" ]]; then
    echo "error: missing ${inventory}" >&2
    exit 1
  fi

  export ANSIBLE_CONFIG="${HOMELAB_ROOT}/ansible/ansible.cfg"
  export HOMELAB_ROOT
  cd "${HOMELAB_ROOT}/ansible"

  echo "==> ansible-playbook deploy.yml"
  local forks="${ANSIBLE_FORKS:-}"
  if [[ -z "${forks}" ]]; then
    forks=$(( ${LEADER_COUNT:-2} + ${WORKER_COUNT:-3} + 1 ))
  fi
  echo "  ansible forks: ${forks} (parallel hosts; serial plays stay one-by-one in deploy.yml)"
  ansible-playbook playbooks/deploy.yml -i "inventories/${ENV_ID}/hosts.yml" --forks "${forks}" "$@"
}

run_ansible_talos_haproxy() {
  if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "error: ansible-playbook not found" >&2
    exit 1
  fi

  local inventory="${HOMELAB_ROOT}/ansible/inventories/${ENV_ID}/hosts.yml"
  if [[ ! -f "${inventory}" ]]; then
    echo "error: missing ${inventory}" >&2
    exit 1
  fi

  export ANSIBLE_CONFIG="${HOMELAB_ROOT}/ansible/ansible.cfg"
  export HOMELAB_ROOT
  cd "${HOMELAB_ROOT}/ansible"

  echo "==> ansible-playbook deploy-haproxy-talos.yml (HAProxy → Talos control planes)"
  ansible-playbook playbooks/deploy-haproxy-talos.yml -i "inventories/${ENV_ID}/hosts.yml" "$@"
}

bootstrap_talos_cluster() {
  bash "${HOMELAB_ROOT}/scripts/bootstrap-talos.sh"
}

run_ansible_tailscale() {
  if [[ "$(hcl_bool "${TAILSCALE_ENABLED:-false}")" != "true" ]]; then
    return 0
  fi
  if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "error: ansible-playbook not found" >&2
    exit 1
  fi
  export ANSIBLE_CONFIG="${HOMELAB_ROOT}/ansible/ansible.cfg"
  export HOMELAB_ROOT
  cd "${HOMELAB_ROOT}/ansible"
  echo "==> ansible-playbook deploy-tailscale.yml"
  ansible-playbook playbooks/deploy-tailscale.yml -i "inventories/${ENV_ID}/hosts.yml" "$@"
}

run_ansible_promtail() {
  if [[ "$(hcl_bool "${LOKI_ENABLED:-false}")" != "true" ]]; then
    return 0
  fi
  if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "error: ansible-playbook not found" >&2
    exit 1
  fi
  write_ansible_loki_vars
  export ANSIBLE_CONFIG="${HOMELAB_ROOT}/ansible/ansible.cfg"
  export HOMELAB_ROOT
  cd "${HOMELAB_ROOT}/ansible"
  echo "==> ansible-playbook deploy-promtail.yml"
  local promtail_hosts="k8s_lb"
  if [[ "$(hcl_bool "${TALOS_ENABLED:-false}")" != "true" ]]; then
    promtail_hosts="k8s_lb:k3s_first_leader:k3s_additional_leaders:k3s_workers"
  fi
  ansible-playbook playbooks/deploy-promtail.yml -i "inventories/${ENV_ID}/hosts.yml" \
    --limit "${promtail_hosts}" "$@"
}

kubeconfig_path() {
  echo "${HOMELAB_ROOT}/kubeconfigs/${ENV_ID}.kubeconfig"
}

fetch_kubeconfig() {
  local output="${1:-$(kubeconfig_path)}"
  local inventory="${HOMELAB_ROOT}/ansible/inventories/${ENV_ID}/hosts.yml"

  if [[ ! -f "${inventory}" ]]; then
    echo "error: missing ${inventory}" >&2
    return 1
  fi

  local leader_ip lb_url
  leader_ip="$(python3 - <<'PY' "${inventory}"
import sys, yaml
with open(sys.argv[1]) as f:
    inv = yaml.safe_load(f)
hosts = inv["all"]["children"]["k3s_first_leader"]["hosts"]
name = next(iter(hosts))
print(hosts[name]["ansible_host"])
PY
)"
  lb_url="$(python3 - <<'PY' "${inventory}"
import sys, yaml
with open(sys.argv[1]) as f:
    inv = yaml.safe_load(f)
print(inv["all"]["vars"]["k3s_server_url"])
PY
)"

  local ssh_user="${SSH_USER:-root}"
  local -a ssh_opts
  mapfile -t ssh_opts < <(homelab_ssh_opts)
  prepare_ssh_known_host "${leader_ip}"

  mkdir -p "$(dirname "${output}")"
  umask 077

  echo "==> fetch kubeconfig from ${ssh_user}@${leader_ip}"
  echo "==> API server: ${lb_url}"

  ssh "${ssh_opts[@]}" "${ssh_user}@${leader_ip}" 'cat /etc/rancher/k3s/k3s.yaml' \
    | sed -E \
      -e "s|^[[:space:]]*server: https://127\\.0\\.0\\.1:6443|    server: ${lb_url}|" \
      -e "s|^[[:space:]]*server: https://[^[:space:]]+:6443|    server: ${lb_url}|" \
    >"${output}.tmp"

  mv "${output}.tmp" "${output}"
  chmod 600 "${output}"
  echo "wrote ${output}"
}

show_kubeconfig_summary() {
  local kubeconfig="${1:-$(kubeconfig_path)}"

  if [[ ! -f "${kubeconfig}" ]]; then
    echo "error: missing ${kubeconfig}" >&2
    return 1
  fi

  local api_server
  api_server="$(grep -E '^[[:space:]]*server:' "${kubeconfig}" | sed -E 's/^[[:space:]]*server:[[:space:]]*//' | tr -d '\r')"

  echo ""
  echo "================================================================"
  echo " Kubeconfig ready (API via HAProxy LB)"
  echo "================================================================"
  echo ""
  echo "  export KUBECONFIG=${kubeconfig}"
  echo ""
  echo "  API server: ${api_server}"
  echo ""
  echo "  # verify cluster access:"
  echo "  kubectl get nodes -o wide"
  echo ""
}

cleanup_tailscale_homelab() {
  load_secrets
  if [[ "$(hcl_bool "${TAILSCALE_ENABLED:-false}")" != "true" ]]; then
    echo "skip Tailscale cleanup (TAILSCALE_ENABLED=false)"
    return 0
  fi

  : "${TAILSCALE_TAILNET:?TAILSCALE_TAILNET required}"
  : "${TAILSCALE_OAUTH_CLIENT_ID:?TAILSCALE_OAUTH_CLIENT_ID required}"
  : "${TAILSCALE_OAUTH_CLIENT_SECRET:?TAILSCALE_OAUTH_CLIENT_SECRET required}"

  generate_tailscale_acl || true

  local fragment proxy_tag connector_hostname tf
  fragment="${GENERATED_DIR}/tailscale-acl-fragment.json"
  if [[ ! -f "${fragment}" ]]; then
    echo "error: missing ${fragment} for Tailscale ACL cleanup" >&2
    return 1
  fi

  tf="$(terraform_bin)"
  proxy_tag="$(${tf} -chdir="${TF_DIR}" output -raw tailscale_proxy_tag 2>/dev/null || true)"
  connector_hostname="$(${tf} -chdir="${TF_DIR}" output -json tailscale 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); d=d.get("value",d); print(d.get("connector_hostname",""))' 2>/dev/null || true)"

  echo "==> remove Tailscale homelab devices + ACL (API)"
  export HOMELAB_ROOT TAILSCALE_TAILNET TAILSCALE_OAUTH_CLIENT_ID TAILSCALE_OAUTH_CLIENT_SECRET
  export TAILSCALE_ACL_FRAGMENT="${fragment}"
  export TAILSCALE_PROXY_TAG="${proxy_tag:-tag:${ENV_ID}}"
  export TAILSCALE_CONNECTOR_HOSTNAME="${connector_hostname:-}"
  python3 "${HOMELAB_ROOT}/scripts/remove-tailscale-homelab.py"
}

cleanup_external_dns_homelab() {
  load_secrets
  if [[ "$(hcl_bool "${EXTERNAL_DNS_ENABLED:-true}")" != "true" ]]; then
    echo "skip Cloudflare DNS cleanup (EXTERNAL_DNS_ENABLED=false)"
    return 0
  fi
  if [[ "$(hcl_bool "${GATEWAY_ENABLED:-true}")" != "true" ]]; then
    echo "skip Cloudflare DNS cleanup (GATEWAY_ENABLED=false)"
    return 0
  fi

  : "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN required when EXTERNAL_DNS_ENABLED=true}"
  : "${GATEWAY_DOMAIN:?GATEWAY_DOMAIN required when GATEWAY_ENABLED=true}"
  : "${GATEWAY_LB_IP:?GATEWAY_LB_IP required when GATEWAY_ENABLED=true}"

  local kubeconfig namespace release
  kubeconfig="$(kubeconfig_path)"
  namespace="${EXTERNAL_DNS_NAMESPACE:-external-dns}"
  release="${EXTERNAL_DNS_RELEASE:-external-dns}"

  if [[ -f "${kubeconfig}" ]] && command -v helm >/dev/null 2>&1; then
    export KUBECONFIG="${kubeconfig}"
    if helm status "${release}" -n "${namespace}" >/dev/null 2>&1; then
      echo "==> helm uninstall ${release} (let external-dns drop DNS records)"
      helm uninstall "${release}" -n "${namespace}" --wait --timeout 5m >/dev/null 2>&1 \
        || helm uninstall "${release}" -n "${namespace}" >/dev/null 2>&1 || true
      sleep 15
    fi
  fi

  local zone_filter txt_owner
  txt_owner="${EXTERNAL_DNS_TXT_OWNER_ID:-homelab-${ENV_ID}}"
  zone_filter="${EXTERNAL_DNS_DOMAIN_FILTER:-$(echo "${GATEWAY_DOMAIN}" | awk -F. '{print $(NF-1)"."$NF}')}"

  echo "==> remove Cloudflare DNS records (external-dns owner=${txt_owner}, zone=${zone_filter})"
  export CLOUDFLARE_API_TOKEN ENV_ID GATEWAY_DOMAIN GATEWAY_LB_IP
  export EXTERNAL_DNS_TXT_OWNER_ID="${txt_owner}"
  export EXTERNAL_DNS_ZONE="${zone_filter}"
  export ARGOCD_HOSTNAME="${ARGOCD_HOSTNAME:-argocd}"
  export LONGHORN_HOSTNAME="${LONGHORN_HOSTNAME:-longhorn}"
  export GRAFANA_HOSTNAME="${GRAFANA_HOSTNAME:-grafana}"
  export PROMETHEUS_HOSTNAME="${PROMETHEUS_HOSTNAME:-prometheus}"
  python3 "${HOMELAB_ROOT}/scripts/remove-cloudflare-external-dns.py"
}

# Remove deploy-generated files (inventory, kubeconfig, k3s token, tfvars).
# Cleans all ENV_ID dirs under inventories/ and secrets/ — not only the current
# ENV_ID — so leftovers after renaming (e.g. homelab → k8s-homelab) are removed too.
# Does NOT touch secrets.env — that is user config.
cleanup_deploy_artifacts() {
  load_secrets
  : "${ENV_ID:?ENV_ID required}"

  local kubeconfig
  kubeconfig="$(kubeconfig_path)"
  local acl_fragment="${GENERATED_DIR}/tailscale-acl-fragment.json"
  local inventories_root="${HOMELAB_ROOT}/ansible/inventories"
  local secrets_root="${HOMELAB_ROOT}/secrets"
  local kubeconfigs_root="${HOMELAB_ROOT}/kubeconfigs"
  local inv_dir secret_dir kc

  echo "==> remove deploy artifacts for ${ENV_ID}"

  if [[ -d "${inventories_root}" ]]; then
    for inv_dir in "${inventories_root}"/*/; do
      [[ -d "${inv_dir}" ]] || continue
      rm -rf "${inv_dir}"
      echo "  removed ${inv_dir%/}"
    done
  fi

  if [[ -d "${secrets_root}" ]]; then
    for secret_dir in "${secrets_root}"/*/; do
      [[ -d "${secret_dir}" ]] || continue
      rm -rf "${secret_dir}"
      echo "  removed ${secret_dir%/}"
    done
  fi

  if [[ -d "${kubeconfigs_root}" ]]; then
    for kc in "${kubeconfigs_root}"/*.kubeconfig; do
      [[ -f "${kc}" ]] || continue
      rm -f "${kc}"
      echo "  removed ${kc}"
    done
  elif [[ -f "${kubeconfig}" ]]; then
    rm -f "${kubeconfig}"
    echo "  removed ${kubeconfig}"
  fi

  if [[ -f "${TFVARS_AUTO}" ]]; then
    rm -f "${TFVARS_AUTO}"
    echo "  removed ${TFVARS_AUTO}"
  fi

  local talos_gen="${HOMELAB_ROOT}/generated/talos"
  if [[ -d "${talos_gen}" ]]; then
    rm -rf "${talos_gen}"
    echo "  removed ${talos_gen}"
  fi

  if [[ -f "${acl_fragment}" ]]; then
    rm -f "${acl_fragment}"
    echo "  removed ${acl_fragment}"
  fi

  local lb_scrape="${GENERATED_DIR}/prometheus-lb-scrape.values.yaml"
  if [[ -f "${lb_scrape}" ]]; then
    rm -f "${lb_scrape}"
    echo "  removed ${lb_scrape}"
  fi
  local loki_ds="${GENERATED_DIR}/prometheus-loki-datasource.values.yaml"
  if [[ -f "${loki_ds}" ]]; then
    rm -f "${loki_ds}"
    echo "  removed ${loki_ds}"
  fi
}

ensure_helm_cli() {
  if ! command -v helm >/dev/null 2>&1; then
    echo "==> install Helm"
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
}

# Fresh HA clusters (K3s + Talos) can etcd-blip under Helm bursts (MetalLB → Longhorn).
wait_for_cluster_api_stable() {
  local timeout="${CLUSTER_READY_TIMEOUT:-180}"
  local need="${CLUSTER_API_STABLE_CHECKS:-2}"
  echo "==> wait for cluster readiness (nodes + stable API, up to ${timeout}s)"
  kubectl wait --for=condition=Ready node --all --timeout="${timeout}s" 2>/dev/null \
    || echo "warning: not all nodes Ready yet" >&2

  local elapsed=0 successes=0
  while [[ "${elapsed}" -lt "${timeout}" ]]; do
    if kubectl get --raw /readyz >/dev/null 2>&1 \
      && kubectl get --raw /livez >/dev/null 2>&1; then
      successes=$((successes + 1))
      if [[ "${successes}" -ge "${need}" ]]; then
        echo "    API stable"
        return 0
      fi
    else
      successes=0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  echo "warning: API stability check timed out — continuing" >&2
}

# Pause after etcd/API blips — used before heavy Helm steps and on retry.
wait_for_etcd_cooldown() {
  local delay checks platform
  if [[ "$(hcl_bool "${TALOS_ENABLED:-false}")" == "true" ]]; then
    platform="Talos"
    delay="${ETCD_COOLDOWN_SECONDS:-20}"
    checks="${ETCD_COOLDOWN_STABLE_CHECKS:-2}"
  else
    platform="K3s"
    delay="${ETCD_COOLDOWN_SECONDS:-30}"
    checks="${ETCD_COOLDOWN_STABLE_CHECKS:-4}"
  fi
  echo "==> etcd cooldown (${platform}: ${delay}s + ${checks} stable API checks)"
  sleep "${delay}"
  local saved="${CLUSTER_API_STABLE_CHECKS:-}"
  CLUSTER_API_STABLE_CHECKS="${checks}"
  wait_for_cluster_api_stable
  CLUSTER_API_STABLE_CHECKS="${saved}"
}

homelab_helm_profile() {
  if [[ "$(hcl_bool "${TALOS_ENABLED:-false}")" == "true" ]]; then
    echo "talos"
  else
    echo "k3s"
  fi
}

is_transient_kubectl_error() {
  local text="${1:-}"
  grep -qiE 'apiserver not ready|ServiceUnavailable|unexpected EOF|error from a previous attempt: EOF|connection reset|etcdserver|context deadline exceeded|i/o timeout|TLS handshake timeout|dial tcp|no route to host' <<<"${text}"
}

# Retry kubectl when HA etcd/API blips during rollout waits (K3s + Talos).
kubectl_with_api_retry() {
  local label="${1:?}"; shift
  local attempts="${KUBECTL_API_RETRY_ATTEMPTS:-3}"
  local attempt=1 out rc

  while [[ "${attempt}" -le "${attempts}" ]]; do
    out="$("$@" 2>&1)" && { printf '%s\n' "${out}"; return 0; }
    rc=$?
    if [[ "${attempt}" -ge "${attempts}" ]] || ! is_transient_kubectl_error "${out}"; then
      printf '%s\n' "${out}" >&2
      return "${rc}"
    fi
    echo "warning: ${label} attempt ${attempt}/${attempts} — transient API error, etcd cooldown before retry" >&2
    wait_for_etcd_cooldown
    attempt=$((attempt + 1))
  done
  return 1
}

helm_force_remove_release() {
  local release="${1:?release}" namespace="${2:?namespace}"
  kubectl delete secrets -n "${namespace}" -l "owner=helm,name=${release}" \
    --ignore-not-found --wait=false 2>/dev/null || true
}

# Longhorn uninstall hook requires deleting-confirmation-flag; --no-hooks + CRD cleanup on recovery.
cleanup_longhorn_install() {
  local namespace="${LONGHORN_NAMESPACE:-longhorn-system}"
  local release="${LONGHORN_RELEASE:-longhorn}"
  echo "==> cleanup Longhorn install state in ${namespace}"

  kubectl delete jobs -n "${namespace}" -l 'app=longhorn-uninstall' \
    --ignore-not-found --wait=false 2>/dev/null || true

  if helm status "${release}" -n "${namespace}" >/dev/null 2>&1; then
    helm uninstall "${release}" -n "${namespace}" --no-hooks --wait --timeout 3m >/dev/null 2>&1 || true
  fi
  helm_force_remove_release "${release}" "${namespace}"

  kubectl delete deploy,ds,sts,job,pod,svc -n "${namespace}" --all \
    --ignore-not-found --wait=false 2>/dev/null || true

  local resource
  for resource in \
    $(kubectl get validatingwebhookconfigurations -o name 2>/dev/null | grep -i longhorn || true) \
    $(kubectl get mutatingwebhookconfigurations -o name 2>/dev/null | grep -i longhorn || true) \
    $(kubectl get clusterrole,clusterrolebinding -o name 2>/dev/null | grep -i longhorn || true); do
    [[ -n "${resource}" ]] && kubectl delete "${resource}" --ignore-not-found --wait=false 2>/dev/null || true
  done

  local crd
  while IFS= read -r crd; do
    [[ -n "${crd}" ]] && kubectl delete "${crd}" --ignore-not-found --wait=false 2>/dev/null || true
  done < <(kubectl get crd -o name 2>/dev/null | grep 'longhorn\.io' || true)

  sleep 5
}

longhorn_wait_workloads() {
  local namespace="${LONGHORN_NAMESPACE:-longhorn-system}"
  local crd
  local manager_timeout="${LONGHORN_MANAGER_ROLLOUT_TIMEOUT:-900s}"
  local attempts="${LONGHORN_ROLLOUT_ATTEMPTS:-2}"
  local attempt=1

  echo "==> wait for Longhorn CRDs + workloads"
  while IFS= read -r crd; do
    [[ -z "${crd}" ]] && continue
    kubectl wait --for=condition=Established "${crd}" --timeout=300s 2>/dev/null \
      || echo "note: ${crd} not Established yet"
  done < <(kubectl get crd -o name 2>/dev/null | grep 'longhorn\.io' || true)

  while [[ "${attempt}" -le "${attempts}" ]]; do
    if kubectl rollout status daemonset/longhorn-manager -n "${namespace}" --timeout="${manager_timeout}"; then
      break
    fi
    if [[ "${attempt}" -ge "${attempts}" ]]; then
      echo "error: longhorn-manager rollout failed after ${attempts} attempt(s)" >&2
      return 1
    fi
    echo "warning: longhorn-manager rollout attempt ${attempt}/${attempts} timed out — etcd cooldown before retry" >&2
    wait_for_etcd_cooldown
    attempt=$((attempt + 1))
  done

  kubectl rollout status deployment/longhorn-driver-deployer -n "${namespace}" --timeout=300s
  kubectl rollout status deployment/longhorn-ui -n "${namespace}" --timeout=180s
}

longhorn_release_is_healthy() {
  local release="${LONGHORN_RELEASE:-longhorn}"
  local namespace="${LONGHORN_NAMESPACE:-longhorn-system}"
  helm status "${release}" -n "${namespace}" -o json 2>/dev/null \
    | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("info",{}).get("status")=="deployed" else 1)' 2>/dev/null
}

longhorn_has_partial_install() {
  local namespace="${LONGHORN_NAMESPACE:-longhorn-system}"
  kubectl get namespace "${namespace}" >/dev/null 2>&1 \
    && kubectl get ds,deploy -n "${namespace}" -o name 2>/dev/null | grep -q .
}

# After etcd/API blips Helm can leave pending-install/failed/uninstalling releases.
helm_recover_stuck_release() {
  local release="${1:?release}" namespace="${2:?namespace}"
  local status=""
  status="$(helm status "${release}" -n "${namespace}" -o json 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("info",{}).get("status",""))' 2>/dev/null)" || return 0
  case "${status}" in
    uninstalling)
      echo "==> helm: waiting for ${release} uninstall in ${namespace}..."
      local i
      for i in $(seq 1 36); do
        status="$(helm status "${release}" -n "${namespace}" -o json 2>/dev/null \
          | python3 -c 'import json,sys; print(json.load(sys.stdin).get("info",{}).get("status",""))' 2>/dev/null)" || status=""
        [[ "${status}" != "uninstalling" ]] && break
        sleep 5
      done
      if [[ "${status}" == "uninstalling" ]]; then
        echo "==> helm: force-remove stuck uninstalling release ${release}"
        helm uninstall "${release}" -n "${namespace}" --no-hooks --wait --timeout 3m >/dev/null 2>&1 || true
        helm_force_remove_release "${release}" "${namespace}"
        if [[ "${release}" == "longhorn" ]]; then
          cleanup_longhorn_install
        fi
      fi
      ;;
    pending-upgrade|pending-rollback)
      echo "==> helm: release ${release} is ${status} — clearing stale helm lock"
      kubectl get secrets -n "${namespace}" -l "owner=helm,name=${release}" -o json 2>/dev/null \
        | python3 -c "
import json, subprocess, sys
for item in json.load(sys.stdin).get('items', []):
    if item.get('metadata', {}).get('labels', {}).get('status') in ('pending-upgrade', 'pending-rollback', 'pending-install'):
        name = item['metadata']['name']
        subprocess.run(['kubectl', 'delete', 'secret', '-n', '${namespace}', name], check=False)
" 2>/dev/null || true
      ;;
    pending-install|failed)
      if helm status "${release}" -n "${namespace}" >/dev/null 2>&1; then
        echo "==> helm: uninstall stuck release ${release} in ${namespace} (was ${status})"
        helm uninstall "${release}" -n "${namespace}" --no-hooks >/dev/null 2>&1 || true
        helm_force_remove_release "${release}" "${namespace}"
        if [[ "${release}" == "longhorn" ]]; then
          cleanup_longhorn_install
        elif [[ "${release}" == "prometheus" ]]; then
          cleanup_prometheus_install
        fi
      else
        echo "==> helm: no release ${release} in ${namespace} (was ${status}) — skip uninstall"
      fi
      ;;
  esac
}

cleanup_prometheus_install() {
  local namespace="${PROMETHEUS_NAMESPACE:-monitoring}"
  local release="${PROMETHEUS_RELEASE:-prometheus}"
  local kind
  echo "==> cleanup Prometheus install state in ${namespace}"

  if helm status "${release}" -n "${namespace}" >/dev/null 2>&1; then
    helm uninstall "${release}" -n "${namespace}" --no-hooks --wait --timeout 5m >/dev/null 2>&1 || true
  fi
  helm_force_remove_release "${release}" "${namespace}"

  kubectl delete jobs,deploy,sts,ds,pod,svc,cm,secret -n "${namespace}" \
    -l "app.kubernetes.io/instance=${release}" \
    --ignore-not-found --wait=false 2>/dev/null || true
  for kind in prometheusrules servicemonitors podmonitors probes alertmanagerconfigs \
    prometheuses alertmanagers thanosrulers; do
    kubectl delete "${kind}" -n "${namespace}" -l "app.kubernetes.io/instance=${release}" \
      --ignore-not-found --wait=false 2>/dev/null || true
  done
  kubectl delete jobs -n "${namespace}" \
    -l 'app.kubernetes.io/component=prometheus-operator-webhook' \
    --ignore-not-found --wait=false 2>/dev/null || true
  kubectl delete jobs -n "${namespace}" \
    -l 'app.kubernetes.io/name=kube-prometheus-stack-admission' \
    --ignore-not-found --wait=false 2>/dev/null || true
  kubectl delete validatingwebhookconfigurations \
    prometheus-kube-prometheus-admission \
    --ignore-not-found --wait=false 2>/dev/null || true
  kubectl delete secret -n "${namespace}" \
    prometheus-kube-prometheus-admission \
    --ignore-not-found --wait=false 2>/dev/null || true
  sleep 5
}

helm_run_with_retry() {
  local release="${1:?release}" namespace="${2:?namespace}"
  shift 2
  local attempts="${HELM_RETRY_ATTEMPTS:-3}"
  local attempt=1
  local helm_log err

  while [[ "${attempt}" -le "${attempts}" ]]; do
    helm_recover_stuck_release "${release}" "${namespace}"
    helm_log="$(mktemp)"
    if helm "$@" >"${helm_log}" 2>&1; then
      cat "${helm_log}"
      rm -f "${helm_log}"
      return 0
    fi
    err="$(cat "${helm_log}")"
    cat "${helm_log}" >&2
    rm -f "${helm_log}"

    if [[ "${attempt}" -ge "${attempts}" ]]; then
      return 1
    fi

    echo "error: helm ${release} failed (attempt ${attempt}/${attempts}) — retrying after recovery" >&2
    helm_recover_stuck_release "${release}" "${namespace}"

    if echo "${err}" | grep -qiE 'etcdserver|context deadline exceeded|Timeout:|Progress deadline|not ready|unexpected EOF|ServiceUnavailable|unable to handle the request'; then
      echo "==> etcd/API timeout detected — cooling down before retry"
      wait_for_etcd_cooldown
    else
      sleep 15
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

# Fast Helm phase: install without --wait, then helm wait once at the end.
HELM_BACKGROUND_MANIFEST=""
HELM_FAST_ROLLOUT_MANIFEST=""

helm_begin_background_phase() {
  HELM_FAST_DEPLOY=1
  HELM_BACKGROUND_MANIFEST="$(mktemp)"
  HELM_FAST_ROLLOUT_MANIFEST="$(mktemp)"
  export HELM_FAST_DEPLOY HELM_BACKGROUND_MANIFEST HELM_FAST_ROLLOUT_MANIFEST
  echo "==> Helm background phase (parallel install, deferred readiness wait)"
}

helm_end_background_phase() {
  wait_for_background_helm_releases
  rm -f "${HELM_BACKGROUND_MANIFEST}" "${HELM_FAST_ROLLOUT_MANIFEST}"
  unset HELM_FAST_DEPLOY HELM_BACKGROUND_MANIFEST HELM_FAST_ROLLOUT_MANIFEST
}

helm_timeout_from_args() {
  local -a args=("$@")
  local i
  for ((i = 0; i < ${#args[@]}; i++)); do
    if [[ "${args[$i]}" == "--timeout" && $((i + 1)) -lt ${#args[@]} ]]; then
      echo "${args[$((i + 1))]}"
      return 0
    fi
  done
  echo "${HELM_DEFAULT_FAST_TIMEOUT:-10m}"
}

# Helm 4 removed standalone `helm wait`; upgrade --wait defaults to hookOnly — use watcher for workloads.
helm_wait_flag() {
  if helm upgrade --help 2>&1 | grep -q 'WaitStrategy'; then
    echo '--wait=watcher'
  else
    echo '--wait'
  fi
}

helm_wait_release_workloads_once() {
  local release="${1:?release}" namespace="${2:?namespace}" timeout="${3:-10m}"
  local selector="app.kubernetes.io/instance=${release}"
  local resource found=0 get_out

  get_out="$(kubectl get deploy,sts,ds -n "${namespace}" -l "${selector}" -o name 2>&1)" || {
    printf '%s\n' "${get_out}" >&2
    return 1
  }

  while IFS= read -r resource; do
    [[ -z "${resource}" ]] && continue
    found=1
    kubectl_with_api_retry "rollout ${resource}" \
      kubectl rollout status "${resource}" -n "${namespace}" --timeout="${timeout}" \
      || return 1
  done <<<"${get_out}"

  if [[ "${found}" == "0" ]]; then
    helm status "${release}" -n "${namespace}" -o json 2>/dev/null \
      | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("info",{}).get("status")=="deployed" else 1)' \
      || return 1
  fi
  return 0
}

helm_wait_release_workloads() {
  local release="${1:?release}" namespace="${2:?namespace}" timeout="${3:-10m}"
  local attempts="${HELM_WAIT_ROLLOUT_ATTEMPTS:-3}"
  local attempt=1

  while [[ "${attempt}" -le "${attempts}" ]]; do
    if helm_wait_release_workloads_once "${release}" "${namespace}" "${timeout}"; then
      return 0
    fi
    if [[ "${attempt}" -ge "${attempts}" ]]; then
      return 1
    fi
    echo "warning: wait workloads ${release} attempt ${attempt}/${attempts} failed — etcd cooldown before retry" >&2
    wait_for_etcd_cooldown
    attempt=$((attempt + 1))
  done
  return 1
}

helm_track_background_release() {
  local release="$1" namespace="$2" wait_timeout="$3"
  echo "${release}|${namespace}|${wait_timeout}" >>"${HELM_BACKGROUND_MANIFEST}"
}

helm_track_background_rollout() {
  local kind="$1" name="$2" namespace="$3" wait_timeout="$4"
  echo "${kind}|${name}|${namespace}|${wait_timeout}" >>"${HELM_FAST_ROLLOUT_MANIFEST}"
}

# K3s: apply manifests without Helm --wait (avoids object_status_reporter spam on API blips).
helm_stack_install_mode() {
  if [[ "$(homelab_helm_profile)" == "k3s" ]]; then
    echo "apply"
  elif [[ "${HELM_FAST_DEPLOY:-}" == "1" ]]; then
    echo "fast"
  else
    echo "critical"
  fi
}

# critical: --wait now | apply: helm apply + kubectl rollout | fast: deferred wait
helm_install_release() {
  local mode="${1:?critical|apply|fast}" release="${2:?}" namespace="${3:?}" retry="${4:-false}"
  shift 4
  local -a helm_args=("$@")
  local wait_timeout
  wait_timeout="$(helm_timeout_from_args "${helm_args[@]}")"

  if [[ "${mode}" == "apply" ]]; then
    helm_recover_stuck_release "${release}" "${namespace}"
    if [[ "${retry}" == "true" ]]; then
      helm_run_with_retry "${release}" "${namespace}" "${helm_args[@]}" || return 1
    else
      helm "${helm_args[@]}" || return 1
    fi
    helm_wait_release_workloads "${release}" "${namespace}" "${wait_timeout}"
    return $?
  fi

  if [[ "${mode}" == "critical" ]]; then
    helm_args+=("$(helm_wait_flag)")
    if [[ "${retry}" == "true" ]]; then
      helm_run_with_retry "${release}" "${namespace}" "${helm_args[@]}"
    else
      helm_recover_stuck_release "${release}" "${namespace}"
      helm "${helm_args[@]}"
    fi
    return $?
  fi

  helm_recover_stuck_release "${release}" "${namespace}"
  if [[ "${retry}" == "true" ]]; then
    helm_run_with_retry "${release}" "${namespace}" "${helm_args[@]}" || return 1
  else
    helm "${helm_args[@]}" || return 1
  fi
  helm_track_background_release "${release}" "${namespace}" "${wait_timeout}"
}

helm_run_parallel() {
  local -a pids=() fn
  for fn in "$@"; do
    "${fn}" &
    pids+=($!)
  done
  local pid rc=0
  for pid in "${pids[@]}"; do
    if ! wait "${pid}"; then
      rc=1
    fi
  done
  return "${rc}"
}

wait_for_background_helm_releases() {
  local line release namespace timeout kind name
  echo "==> wait for background Helm releases"
  wait_for_etcd_cooldown
  if [[ -f "${HELM_BACKGROUND_MANIFEST:-}" ]]; then
    while IFS= read -r line; do
      [[ -n "${line}" ]] || continue
      release="${line%%|*}"
      namespace="${line#*|}"; namespace="${namespace%%|*}"
      timeout="${line##*|}"
      echo "    wait workloads ${release} (${namespace}, ${timeout})"
      helm_wait_release_workloads "${release}" "${namespace}" "${timeout}" \
        || { echo "error: wait workloads ${release} failed" >&2; return 1; }
    done <"${HELM_BACKGROUND_MANIFEST}"
  fi
  if [[ -f "${HELM_FAST_ROLLOUT_MANIFEST:-}" ]]; then
    while IFS= read -r line; do
      [[ -n "${line}" ]] || continue
      kind="${line%%|*}"; line="${line#*|}"
      name="${line%%|*}"; line="${line#*|}"
      namespace="${line%%|*}"
      timeout="${line##*|}"
      echo "    rollout ${kind}/${name} (${namespace}, ${timeout})"
      kubectl_with_api_retry "rollout ${kind}/${name}" \
        kubectl rollout status "${kind}/${name}" -n "${namespace}" --timeout="${timeout}" \
        || { echo "error: rollout ${kind}/${name} failed" >&2; return 1; }
    done <"${HELM_FAST_ROLLOUT_MANIFEST}"
  fi
}

# K3s bundles Traefik as LoadBalancer — conflicts with MetalLB IP for Envoy Gateway
cleanup_k3s_traefik() {
  if [[ "$(hcl_bool "${GATEWAY_ENABLED:-true}")" != "true" ]]; then
    return 0
  fi
  if ! helm status traefik -n kube-system >/dev/null 2>&1; then
    return 0
  fi
  echo "==> remove K3s Traefik (frees MetalLB IP ${GATEWAY_LB_IP:-.211} for Envoy Gateway)"
  helm uninstall traefik -n kube-system >/dev/null 2>&1 || true
  helm uninstall traefik-crd -n kube-system >/dev/null 2>&1 || true
  kubectl delete svc traefik -n kube-system --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
}

apply_manifest_template() {
  local template="${1:?template required}"
  if [[ ! -f "${template}" ]]; then
    echo "error: missing ${template}" >&2
    return 1
  fi
  envsubst <"${template}" | kubectl apply -f -
}

apply_manifest_template_with_retry() {
  local template="${1:?template required}"
  local attempts="${2:-6}"
  local attempt
  if [[ ! -f "${template}" ]]; then
    echo "error: missing ${template}" >&2
    return 1
  fi
  for attempt in $(seq 1 "${attempts}"); do
    if envsubst <"${template}" | kubectl apply -f -; then
      return 0
    fi
    echo "note: manifest apply attempt ${attempt}/${attempts} failed — retrying..."
    sleep 10
  done
  echo "error: manifest apply failed after ${attempts} attempts: ${template}" >&2
  return 1
}

wait_for_metallb_webhook() {
  local namespace="${METALLB_NAMESPACE:-metallb-system}"
  echo "==> wait for MetalLB validation webhook"
  kubectl wait --for=condition=Available deployment/metallb-controller \
    -n "${namespace}" --timeout=300s 2>/dev/null \
    || kubectl rollout status deployment/metallb-controller -n "${namespace}" --timeout=300s
  local i
  for i in $(seq 1 60); do
    if kubectl get endpoints metallb-webhook-service -n "${namespace}" \
        -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null | grep -q .; then
      echo "    MetalLB webhook endpoints ready"
      sleep 5
      return 0
    fi
    sleep 5
  done
  echo "warning: MetalLB webhook endpoints not ready — continuing anyway" >&2
}

gateway_platform_env() {
  : "${ACME_EMAIL:?ACME_EMAIL required when GATEWAY_ENABLED=true}"
  : "${GATEWAY_LB_IP:?GATEWAY_LB_IP required when GATEWAY_ENABLED=true}"
  : "${GATEWAY_DOMAIN:?GATEWAY_DOMAIN required when GATEWAY_ENABLED=true}"
  export GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-envoy-gateway-system}"
  export ACME_EMAIL
  export GATEWAY_LB_IP
  export GATEWAY_DOMAIN
  export CLOUDFLARE_DNS_ZONE="${EXTERNAL_DNS_DOMAIN_FILTER:-$(echo "${GATEWAY_DOMAIN}" | awk -F. '{print $(NF-1)"."$NF}')}"
  if [[ "$(hcl_bool "${LETSENCRYPT_STAGING:-false}")" == "true" ]]; then
    export ACME_SERVER="https://acme-staging-v02.api.letsencrypt.org/directory"
  else
    export ACME_SERVER="https://acme-v02.api.letsencrypt.org/directory"
  fi
}

ensure_cloudflare_api_secret() {
  local namespace="${1:?namespace required}"
  : "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN required when GATEWAY_ENABLED=true or EXTERNAL_DNS_ENABLED=true}"

  kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl create secret generic cloudflare-api-token \
    --namespace "${namespace}" \
    --from-literal=api-token="${CLOUDFLARE_API_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

deploy_metallb() {
  if [[ "$(hcl_bool "${GATEWAY_ENABLED:-true}")" != "true" ]]; then
    return 0
  fi

  gateway_platform_env
  local namespace="${METALLB_NAMESPACE:-metallb-system}"
  local release="${METALLB_RELEASE:-metallb}"
  local helm_repo="${METALLB_HELM_REPO:-https://metallb.github.io/metallb}"
  local chart="${METALLB_CHART:-metallb/metallb}"
  local wait_timeout="${METALLB_WAIT_TIMEOUT:-10m}"
  local values="${HOMELAB_ROOT}/helm-homelab/metallb/values.yaml"

  ensure_helm_cli
  echo "==> helm: MetalLB (${release})"
  helm_repo_ensure metallb "${helm_repo}"

  local -a helm_args=(
    upgrade --install "${release}" "${chart}"
    --namespace "${namespace}"
    --create-namespace
    --timeout "${wait_timeout}"
    --hide-notes
    -f "${values}"
  )
  if [[ -n "${METALLB_CHART_VERSION:-}" ]]; then
    helm_args+=(--version "${METALLB_CHART_VERSION}")
  fi
  helm_install_release critical "${release}" "${namespace}" true "${helm_args[@]}"

  wait_for_metallb_webhook
  echo "==> MetalLB IP pool ${GATEWAY_LB_IP}"
  apply_manifest_template_with_retry "${HOMELAB_ROOT}/helm-homelab/gateway/manifests/metallb-ip-pool.yaml.tpl"
}

deploy_cert_manager() {
  if [[ "$(hcl_bool "${GATEWAY_ENABLED:-true}")" != "true" ]]; then
    return 0
  fi

  gateway_platform_env
  local namespace="${CERT_MANAGER_NAMESPACE:-cert-manager}"
  local release="${CERT_MANAGER_RELEASE:-cert-manager}"
  local helm_repo="${CERT_MANAGER_HELM_REPO:-https://charts.jetstack.io}"
  local chart="${CERT_MANAGER_CHART:-jetstack/cert-manager}"
  local wait_timeout="${CERT_MANAGER_WAIT_TIMEOUT:-10m}"
  local values="${HOMELAB_ROOT}/helm-homelab/cert-manager/values.yaml"

  ensure_helm_cli
  echo "==> helm: cert-manager (${release})"
  helm_repo_ensure jetstack "${helm_repo}"

  local -a helm_args=(
    upgrade --install "${release}" "${chart}"
    --namespace "${namespace}"
    --create-namespace
    --timeout "${wait_timeout}"
    --hide-notes
    -f "${values}"
  )
  # ServiceMonitor CRD comes from kube-prometheus-stack — must install Prometheus first.
  if [[ "$(hcl_bool "${PROMETHEUS_ENABLED:-true}")" != "true" ]]; then
    helm_args+=(
      --set "prometheus.enabled=false"
      --set "prometheus.servicemonitor.enabled=false"
    )
  fi
  if [[ -n "${CERT_MANAGER_CHART_VERSION:-}" ]]; then
    helm_args+=(--version "${CERT_MANAGER_CHART_VERSION}")
  fi
  helm_install_release critical "${release}" "${namespace}" true "${helm_args[@]}"

  ensure_cloudflare_api_secret "${namespace}"
  ensure_cloudflare_api_secret "${GATEWAY_NAMESPACE}"
  echo "==> ClusterIssuer letsencrypt-cloudflare (zone ${CLOUDFLARE_DNS_ZONE})"
  apply_manifest_template "${HOMELAB_ROOT}/helm-homelab/gateway/manifests/cluster-issuer.yaml.tpl"
}

deploy_sealed_secrets() {
  if [[ "$(hcl_bool "${SEALED_SECRETS_ENABLED:-true}")" != "true" ]]; then
    echo "skip Sealed Secrets (SEALED_SECRETS_ENABLED=false)"
    return 0
  fi

  local namespace="${SEALED_SECRETS_NAMESPACE:-kube-system}"
  local version="${SEALED_SECRETS_VERSION:-0.38.1}"
  local manifest="https://github.com/bitnami-labs/sealed-secrets/releases/download/v${version}/controller.yaml"
  local wait_timeout="${SEALED_SECRETS_WAIT_TIMEOUT:-5m}"

  echo "==> Sealed Secrets controller v${version} (upstream manifest)"
  kubectl apply -f "${manifest}"
  if [[ "${HELM_FAST_DEPLOY:-}" == "1" ]]; then
    helm_track_background_rollout deployment sealed-secrets-controller "${namespace}" "${wait_timeout}"
    return 0
  fi
  kubectl rollout status deployment/sealed-secrets-controller \
    -n "${namespace}" --timeout="${wait_timeout}"
}

deploy_reloader() {
  if [[ "$(hcl_bool "${RELOADER_ENABLED:-true}")" != "true" ]]; then
    echo "skip Reloader (RELOADER_ENABLED=false)"
    return 0
  fi

  local namespace="${RELOADER_NAMESPACE:-reloader}"
  local release="${RELOADER_RELEASE:-reloader}"
  local helm_repo="${RELOADER_HELM_REPO:-https://stakater.github.io/stakater-charts}"
  local chart="${RELOADER_CHART:-stakater/reloader}"
  local wait_timeout="${RELOADER_WAIT_TIMEOUT:-5m}"
  local values="${HOMELAB_ROOT}/helm-homelab/reloader/values.yaml"

  ensure_helm_cli
  echo "==> helm: Reloader (${release})"
  helm_repo_ensure stakater "${helm_repo}"

  local -a helm_args=(
    upgrade --install "${release}" "${chart}"
    --namespace "${namespace}"
    --create-namespace
    --timeout "${wait_timeout}"
    --hide-notes
    -f "${values}"
  )
  if [[ -n "${RELOADER_CHART_VERSION:-}" ]]; then
    helm_args+=(--version "${RELOADER_CHART_VERSION}")
  fi
  helm_install_release "$(helm_stack_install_mode)" "${release}" "${namespace}" false "${helm_args[@]}"
}

install_envoy_gateway_crds() {
  local crds_chart="${ENVOY_GATEWAY_CRDS_CHART:-oci://docker.io/envoyproxy/gateway-crds-helm}"
  local crds_version="${ENVOY_GATEWAY_CHART_VERSION:-1.8.1}"
  local gateway_api_enabled=true

  if helm status traefik-crd -n kube-system >/dev/null 2>&1; then
    gateway_api_enabled=false
    echo "note: traefik-crd present — skip Gateway API CRDs (K3s legacy)"
  fi

  echo "==> Gateway API + Envoy CRDs (gateway-crds-helm ${crds_version})"
  wait_for_etcd_cooldown

  local -a template_args=(
    template eg-crds "${crds_chart}"
    --version "${crds_version}"
    --set "crds.gatewayAPI.enabled=${gateway_api_enabled}"
    --set crds.envoyGateway.enabled=true
  )

  local crd_manifest attempts attempt apply_out
  crd_manifest="$(mktemp)"
  helm "${template_args[@]}" | python3 -c "
import sys, yaml
for doc in yaml.safe_load_all(sys.stdin):
    if doc and doc.get('kind') == 'CustomResourceDefinition':
        sys.stdout.write('---\n')
        yaml.dump(doc, sys.stdout, default_flow_style=False)
" >"${crd_manifest}"

  attempts="${KUBECTL_API_RETRY_ATTEMPTS:-3}"
  attempt=1
  while [[ "${attempt}" -le "${attempts}" ]]; do
    apply_out="$(kubectl apply --server-side --force-conflicts -f "${crd_manifest}" 2>&1)" && {
      printf '%s\n' "${apply_out}"
      rm -f "${crd_manifest}"
      break
    }
    printf '%s\n' "${apply_out}" >&2
    if [[ "${attempt}" -ge "${attempts}" ]]; then
      rm -f "${crd_manifest}"
      return 1
    fi
    echo "error: Gateway CRD apply failed (attempt ${attempt}/${attempts}) — etcd cooldown before retry" >&2
    wait_for_etcd_cooldown
    attempt=$((attempt + 1))
  done

  echo "==> wait for Gateway API CRDs"
  kubectl_with_api_retry "gateway crd referencegrants" \
    kubectl wait --for=condition=Established crd/referencegrants.gateway.networking.k8s.io --timeout=120s
  kubectl_with_api_retry "gateway crd gateways" \
    kubectl wait --for=condition=Established crd/gateways.gateway.networking.k8s.io --timeout=120s
  kubectl_with_api_retry "gateway crd httproutes" \
    kubectl wait --for=condition=Established crd/httproutes.gateway.networking.k8s.io --timeout=120s
}

deploy_envoy_gateway() {
  if [[ "$(hcl_bool "${GATEWAY_ENABLED:-true}")" != "true" ]]; then
    return 0
  fi

  gateway_platform_env
  cleanup_k3s_traefik
  local namespace="${GATEWAY_NAMESPACE}"
  local release="${ENVOY_GATEWAY_RELEASE:-eg}"
  local chart="${ENVOY_GATEWAY_CHART:-oci://docker.io/envoyproxy/gateway-helm}"
  local wait_timeout="${ENVOY_GATEWAY_WAIT_TIMEOUT:-10m}"
  local values="${HOMELAB_ROOT}/helm-homelab/envoy-gateway/values.yaml"

  ensure_helm_cli
  install_envoy_gateway_crds

  echo "==> helm: Envoy Gateway (${release})"
  kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  local -a helm_args=(
    upgrade --install "${release}" "${chart}"
    --namespace "${namespace}"
    --create-namespace
    --timeout "${wait_timeout}"
    --hide-notes
    --skip-crds
    -f "${values}"
  )
  if [[ -n "${ENVOY_GATEWAY_CHART_VERSION:-}" ]]; then
    helm_args+=(--version "${ENVOY_GATEWAY_CHART_VERSION}")
  fi
  helm_install_release critical "${release}" "${namespace}" false "${helm_args[@]}"

  echo "==> GatewayClass eg (Envoy controller)"
  kubectl apply -f "${HOMELAB_ROOT}/helm-homelab/gateway/manifests/gatewayclass-eg.yaml"
  kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s 2>/dev/null \
    || echo "note: waiting for GatewayClass eg acceptance"
}

apply_gateway_platform() {
  if [[ "$(hcl_bool "${GATEWAY_ENABLED:-true}")" != "true" ]]; then
    return 0
  fi

  gateway_platform_env
  local manifest_dir="${HOMELAB_ROOT}/helm-homelab/gateway/manifests"

  echo "==> Gateway API Certificate (*.${GATEWAY_DOMAIN})"
  ensure_cloudflare_api_secret "${GATEWAY_NAMESPACE}"
  apply_manifest_template "${manifest_dir}/gateway-certificate.yaml.tpl"
  apply_manifest_template "${manifest_dir}/gateway.yaml.tpl"
  echo "note: full TLS wait runs after HTTPRoutes (see wait_for_gateway_tls_certificate)"
}

verify_cloudflare_acme_dns01_ready() {
  if [[ "$(hcl_bool "${GATEWAY_ENABLED:-true}")" != "true" ]]; then
    return 0
  fi
  if [[ "$(hcl_bool "${CLOUDFLARE_ACME_PREFLIGHT:-true}")" != "true" ]]; then
    echo "note: skipping Cloudflare ACME DNS preflight (CLOUDFLARE_ACME_PREFLIGHT=false)"
    return 0
  fi
  if [[ "$(hcl_bool "${LETSENCRYPT_STAGING:-false}")" == "true" ]]; then
    echo "note: skipping Cloudflare ACME DNS preflight (LETSENCRYPT_STAGING=true)"
    return 0
  fi

  gateway_platform_env
  : "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN required when GATEWAY_ENABLED=true}"

  local probe_name="_acme-challenge.${GATEWAY_DOMAIN}"
  echo "==> Cloudflare DNS-01 preflight (${probe_name})"

  python3 - "${CLOUDFLARE_API_TOKEN}" "${CLOUDFLARE_DNS_ZONE}" "${probe_name}" <<'PY'
import json
import random
import socket
import struct
import sys
import time
import urllib.request

token, zone_name, probe_name = sys.argv[1:4]

def cf_api(method, path, body=None):
    req = urllib.request.Request(
        f"https://api.cloudflare.com/client/v4{path}",
        method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        data=json.dumps(body).encode() if body is not None else None,
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.load(resp)
    if not data.get("success"):
        raise RuntimeError(data.get("errors") or data)
    return data

def query_txt(server: str, name: str) -> bool:
    tid = random.randint(0, 65535)
    parts = name.rstrip(".").split(".")
    qname = b"".join(bytes([len(p)]) + p.encode() for p in parts if p) + b"\x00"
    header = struct.pack("!HHHHHH", tid, 0x0100, 1, 0, 0, 0)
    question = qname + struct.pack("!HH", 16, 1)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(3)
    sock.sendto(header + question, (server, 53))
    data, _ = sock.recvfrom(4096)
    return (data[3] & 0xF) == 0 and len(data) > 12

zones = cf_api("GET", f"/zones?name={zone_name}").get("result") or []
if not zones:
    raise SystemExit(f"error: Cloudflare zone not found: {zone_name}")
zone_id = zones[0]["id"]
probe_value = '"homelab-acme-preflight"'

created = cf_api(
    "POST",
    f"/zones/{zone_id}/dns_records",
    {"type": "TXT", "name": probe_name, "content": probe_value, "ttl": 60, "proxied": False},
)
record_id = created["result"]["id"]

try:
    ok = False
    for _ in range(6):
        if any(query_txt(server, probe_name) for server in ("1.1.1.1", "8.8.8.8")):
            ok = True
            break
        time.sleep(5)
    if not ok:
        raise SystemExit(
            f"error: Cloudflare publishes {probe_name} in the API but public DNS returns NXDOMAIN.\n"
            "Let's Encrypt DNS-01 cannot succeed until _acme-challenge TXT records resolve.\n"
            "Fix in Cloudflare dashboard for zone "
            f"{zone_name}:\n"
            "  1. SSL/TLS → Edge Certificates → disable Universal SSL (or pause Cloudflare briefly)\n"
            "  2. Delete stale _acme-challenge TXT records (Dashboard → DNS, or API list)\n"
            "  3. Re-run deploy (or: ./deploy-infra.sh -y --os=talos --helm-only)\n"
            "See docs/cloudflare-gateway.md#universal-ssl-blocks-dns-01"
        )
finally:
    try:
        cf_api("DELETE", f"/zones/{zone_id}/dns_records/{record_id}")
    except Exception:
        pass
PY
}

gateway_tls_secret_issuer() {
  kubectl get secret homelab-gateway-tls -n "${GATEWAY_NAMESPACE}" -o jsonpath='{.data.tls\.crt}' 2>/dev/null \
    | base64 -d | openssl x509 -noout -issuer 2>/dev/null || true
}

gateway_tls_is_letsencrypt() {
  local issuer
  issuer="$(gateway_tls_secret_issuer)"
  [[ "${issuer}" == *"Let's Encrypt"* || "${issuer}" == *"letsencrypt"* ]]
}

wait_for_gateway_tls_certificate() {
  if [[ "$(hcl_bool "${GATEWAY_ENABLED:-true}")" != "true" ]]; then
    return 0
  fi
  if [[ "$(hcl_bool "${GATEWAY_TLS_WAIT_AT_DEPLOY:-true}")" != "true" ]]; then
    echo "note: skipping TLS wait at deploy end (GATEWAY_TLS_WAIT_AT_DEPLOY=false)"
    return 0
  fi

  gateway_platform_env
  local timeout="${GATEWAY_TLS_WAIT_TIMEOUT:-5m}"
  local manifest_dir="${HOMELAB_ROOT}/helm-homelab/gateway/manifests"

  echo "==> wait for Let's Encrypt TLS certificate (up to ${timeout})"
  ensure_cloudflare_api_secret "${GATEWAY_NAMESPACE}"
  apply_manifest_template "${manifest_dir}/gateway-certificate.yaml.tpl"

  if ! kubectl wait --for=condition=Ready certificate/homelab-gateway-wildcard \
    -n "${GATEWAY_NAMESPACE}" --timeout="${timeout}"; then
    echo "error: TLS certificate not Ready — inspect:" >&2
    echo "  kubectl describe certificate homelab-gateway-wildcard -n ${GATEWAY_NAMESPACE}" >&2
    echo "  kubectl get challenge,order -n ${GATEWAY_NAMESPACE}" >&2
    echo "  If challenge shows DNS propagation: disable Cloudflare Universal SSL (docs/cloudflare-gateway.md)" >&2
    kubectl get challenge,order -n "${GATEWAY_NAMESPACE}" 2>/dev/null || true
    return 1
  fi

  if ! gateway_tls_is_letsencrypt; then
    echo "error: homelab-gateway-tls is not a Let's Encrypt cert ($(gateway_tls_secret_issuer))" >&2
    return 1
  fi
  echo "    TLS Ready: $(gateway_tls_secret_issuer | sed 's/issuer=//')"
}

deploy_external_dns() {
  if [[ "$(hcl_bool "${EXTERNAL_DNS_ENABLED:-true}")" != "true" ]]; then
    echo "skip external-dns (EXTERNAL_DNS_ENABLED=false)"
    return 0
  fi
  if [[ "$(hcl_bool "${GATEWAY_ENABLED:-true}")" != "true" ]]; then
    echo "skip external-dns (GATEWAY_ENABLED=false)"
    return 0
  fi

  gateway_platform_env
  local namespace="${EXTERNAL_DNS_NAMESPACE:-external-dns}"
  local release="${EXTERNAL_DNS_RELEASE:-external-dns}"
  local helm_repo="${EXTERNAL_DNS_HELM_REPO:-https://kubernetes-sigs.github.io/external-dns}"
  local chart="${EXTERNAL_DNS_CHART:-external-dns/external-dns}"
  local wait_timeout="${EXTERNAL_DNS_WAIT_TIMEOUT:-5m}"
  local values="${HOMELAB_ROOT}/helm-homelab/external-dns/values.yaml"
  local txt_owner domain_filter
  local -a extra_args=( "--gateway-name=homelab" "--gateway-namespace=${GATEWAY_NAMESPACE}" )

  txt_owner="${EXTERNAL_DNS_TXT_OWNER_ID:-homelab-${ENV_ID}}"
  # Cloudflare hosted zone (apex) — NOT the gateway subdomain. external-dns excludes
  # the zone if the filter is a child of it. Defaults to the last two labels of
  # GATEWAY_DOMAIN (homelab.panev.cloud → panev.cloud); override if your zone differs.
  domain_filter="${EXTERNAL_DNS_DOMAIN_FILTER:-$(echo "${GATEWAY_DOMAIN}" | awk -F. '{print $(NF-1)"."$NF}')}"
  if [[ "$(hcl_bool "${CLOUDFLARE_DNS_PROXIED:-false}")" == "true" ]]; then
    extra_args=( "--cloudflare-proxied" "${extra_args[@]}" )
  fi

  ensure_helm_cli
  ensure_cloudflare_api_secret "${namespace}"
  echo "==> helm: external-dns (${release}) → Cloudflare A records for HTTPRoutes"
  echo "    zone filter: ${domain_filter} → ${GATEWAY_LB_IP} (DNS only, proxied=$(hcl_bool "${CLOUDFLARE_DNS_PROXIED:-false}"))"
  helm_repo_ensure external-dns "${helm_repo}"

  local -a helm_args=(
    upgrade --install "${release}" "${chart}"
    --namespace "${namespace}"
    --create-namespace
    --timeout "${wait_timeout}"
    --hide-notes
    -f "${values}"
    --set-string "domainFilters[0]=${domain_filter}"
    --set-string "txtOwnerId=${txt_owner}"
  )
  local i=0 arg
  for arg in "${extra_args[@]}"; do
    helm_args+=(--set-string "extraArgs[${i}]=${arg}")
    i=$((i + 1))
  done
  if [[ -n "${EXTERNAL_DNS_CHART_VERSION:-}" ]]; then
    helm_args+=(--version "${EXTERNAL_DNS_CHART_VERSION}")
  fi
  if [[ "${HELM_FAST_DEPLOY:-}" == "1" ]]; then
    helm_install_release fast "${release}" "${namespace}" false "${helm_args[@]}"
  else
    helm_install_release critical "${release}" "${namespace}" false "${helm_args[@]}"
  fi
}

apply_platform_httproutes() {
  if [[ "$(hcl_bool "${GATEWAY_ENABLED:-true}")" != "true" ]]; then
    return 0
  fi

  gateway_platform_env
  local route_dir="${HOMELAB_ROOT}/helm-homelab/gateway/manifests/httproutes"
  local route

  echo "==> platform HTTPRoutes (Gateway API)"
  for route in "${route_dir}"/*.yaml.tpl; do
    [[ -f "${route}" ]] || continue
    if [[ "${route}" == *argocd* ]] && [[ "$(hcl_bool "${ARGOCD_ENABLED:-true}")" != "true" ]]; then
      continue
    fi
    if [[ "${route}" == *longhorn* ]] && [[ "$(hcl_bool "${LONGHORN_ENABLED:-true}")" != "true" ]]; then
      continue
    fi
    if [[ "${route}" == *grafana* || "${route}" == *prometheus* ]] \
      && [[ "$(hcl_bool "${PROMETHEUS_ENABLED:-true}")" != "true" ]]; then
      continue
    fi
    if [[ "${route}" == *grafana* || "${route}" == *prometheus* ]]; then
      export PROMETHEUS_NAMESPACE="${PROMETHEUS_NAMESPACE:-monitoring}"
      export PROMETHEUS_RELEASE="${PROMETHEUS_RELEASE:-prometheus}"
    fi
    apply_manifest_template "${route}"
  done
}

detect_gitops_repo_url() {
  local url="${GITOPS_REPO_URL:-}"
  if [[ -n "${url}" ]]; then
    echo "${url}"
    return 0
  fi
  if git -C "${HOMELAB_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    url="$(git -C "${HOMELAB_ROOT}" remote get-url origin 2>/dev/null || true)"
    if [[ -n "${url}" ]]; then
      echo "${url}"
      return 0
    fi
  fi
  return 1
}

bootstrap_argocd() {
  if [[ "$(hcl_bool "${ARGOCD_BOOTSTRAP_ENABLED:-true}")" != "true" ]]; then
    echo "skip Argo CD bootstrap (ARGOCD_BOOTSTRAP_ENABLED=false)"
    return 0
  fi
  if [[ "$(hcl_bool "${ARGOCD_ENABLED:-true}")" != "true" ]]; then
    echo "skip Argo CD bootstrap (ARGOCD_ENABLED=false)"
    return 0
  fi

  local repo_url
  if ! repo_url="$(detect_gitops_repo_url)"; then
    echo "skip Argo CD bootstrap — set GITOPS_REPO_URL in secrets.env or add git remote origin" >&2
    return 0
  fi

  export GITOPS_REPO_URL="${repo_url}"
  export GITOPS_REPO_BRANCH="${GITOPS_REPO_BRANCH:-main}"
  export GITOPS_APPS_PATH="${GITOPS_APPS_PATH:-gitops/apps}"

  echo "==> Argo CD bootstrap (app-of-apps)"
  echo "    repo: ${GITOPS_REPO_URL}"
  echo "    path: ${GITOPS_APPS_PATH} @ ${GITOPS_REPO_BRANCH}"

  kubectl apply -f "${HOMELAB_ROOT}/gitops/bootstrap/appproject.yaml"
  apply_manifest_template "${HOMELAB_ROOT}/gitops/bootstrap/root-application.yaml.tpl"
}

show_gateway_summary() {
  load_secrets
  if [[ "$(hcl_bool "${GATEWAY_ENABLED:-true}")" != "true" ]]; then
    return 0
  fi

  local domain lb_ip
  domain="${GATEWAY_DOMAIN:-homelab.panev.cloud}"
  lb_ip="${GATEWAY_LB_IP:-}"

  echo ""
  echo "================================================================"
  echo " Gateway API (home LAN)"
  echo "================================================================"
  echo ""
  echo "  Gateway class: eg"
  echo "  Gateway:       homelab (namespace ${GATEWAY_NAMESPACE:-envoy-gateway-system})"
  if [[ -n "${lb_ip}" ]]; then
    echo "  LAN IP:        ${lb_ip}  (MetalLB — point local DNS or router here)"
  fi
  echo "  Domain base:   *.${domain}"
  echo "  TLS:           Let's Encrypt DNS-01 via Cloudflare"
  echo ""
  echo "  Platform URLs (HTTPS):"
  if [[ "$(hcl_bool "${ARGOCD_ENABLED:-true}")" == "true" ]]; then
    echo "    https://argocd.${domain}"
  fi
  if [[ "$(hcl_bool "${LONGHORN_ENABLED:-true}")" == "true" ]]; then
    echo "    https://longhorn.${domain}"
  fi
  if [[ "$(hcl_bool "${PROMETHEUS_ENABLED:-true}")" == "true" ]]; then
    echo "    https://grafana.${domain}"
    echo "    https://prometheus.${domain}"
  fi
  echo ""
  echo "  App template:  gitops/examples/httproute-app.yaml"
  if [[ "$(hcl_bool "${EXTERNAL_DNS_ENABLED:-true}")" == "true" ]]; then
    echo "  DNS:           external-dns → Cloudflare A → ${lb_ip:-<GATEWAY_LB_IP>} (per HTTPRoute hostname)"
  else
    echo "  DNS:           manual — create A records in Cloudflare → ${lb_ip:-<GATEWAY_LB_IP>}"
    echo "                 or set EXTERNAL_DNS_ENABLED=true"
  fi
  echo ""
  if [[ "$(hcl_bool "${TAILSCALE_ENABLED:-false}")" == "true" ]]; then
    echo "  Remote access: Tailscale ingress still available (optional, away from home)"
  fi
  echo ""
}

show_sealed_secrets_summary() {
  load_secrets
  if [[ "$(hcl_bool "${SEALED_SECRETS_ENABLED:-true}")" != "true" ]]; then
    return 0
  fi

  echo ""
  echo "================================================================"
  echo " Sealed Secrets"
  echo "================================================================"
  echo ""
  echo "  kubeseal example: gitops/examples/sealed-secret.md"
  echo "  fetch cert: kubeseal --fetch-cert > pub-cert.pem"
  echo ""
}

# Read the HAProxy/API LB IP from the generated Ansible inventory (k3s_lb_ip).
lb_scrape_ip() {
  local inventory="${HOMELAB_ROOT}/ansible/inventories/${ENV_ID}/hosts.yml"
  [[ -f "${inventory}" ]] || return 0
  python3 - "${inventory}" <<'PY' 2>/dev/null || true
import sys, yaml
with open(sys.argv[1]) as f:
    inv = yaml.safe_load(f)
print(inv.get("all", {}).get("vars", {}).get("k3s_lb_ip", ""))
PY
}

# Generate a Prometheus values overlay that scrapes the LB VM's node_exporter
# (:9100) and HAProxy native exporter (:8404). Writes the file path to stdout.
write_lb_scrape_values() {
  local lb_ip="$1" haproxy_port="${HAPROXY_METRICS_PORT:-8404}" node_port="${LB_NODE_EXPORTER_PORT:-9100}"
  local out="${HOMELAB_ROOT}/scripts/generated/prometheus-lb-scrape.values.yaml"
  mkdir -p "$(dirname "${out}")"
  cat >"${out}" <<EOF
# Generated by deploy-infra.sh — scrape the standalone HAProxy LB VM (${lb_ip}).
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: lb-node-exporter
        static_configs:
          - targets: ["${lb_ip}:${node_port}"]
            labels:
              instance: "${ENV_ID}-lb"
              role: lb
      - job_name: lb-haproxy
        metrics_path: /metrics
        static_configs:
          - targets: ["${lb_ip}:${haproxy_port}"]
            labels:
              instance: "${ENV_ID}-lb"
              role: lb
EOF
  echo "${out}"
}

# Grafana datasource overlay when Loki is enabled (merged into kube-prometheus-stack deploy).
write_loki_grafana_datasource_values() {
  local namespace="${LOKI_NAMESPACE:-monitoring}"
  local release="${LOKI_RELEASE:-loki}"
  local out="${HOMELAB_ROOT}/scripts/generated/prometheus-loki-datasource.values.yaml"
  mkdir -p "$(dirname "${out}")"
  cat >"${out}" <<EOF
# Generated by deploy-infra.sh — Loki datasource for Grafana.
grafana:
  additionalDataSources:
    - name: Loki
      uid: loki
      type: loki
      access: proxy
      url: http://${release}-gateway.${namespace}.svc.cluster.local
      isDefault: false
      jsonData:
        maxLines: 1000
EOF
  echo "${out}"
}

prometheus_wait_workloads() {
  local namespace="${PROMETHEUS_NAMESPACE:-monitoring}"
  local release="${PROMETHEUS_RELEASE:-prometheus}"
  echo "==> wait for kube-prometheus-stack workloads"
  kubectl rollout status "deployment/${release}-kube-prometheus-operator" \
    -n "${namespace}" --timeout=900s
  kubectl rollout status "deployment/${release}-kube-state-metrics" \
    -n "${namespace}" --timeout=600s
  kubectl rollout status "deployment/${release}-grafana" \
    -n "${namespace}" --timeout=900s
  kubectl wait --for=condition=Ready pod \
    -l "app.kubernetes.io/name=prometheus-node-exporter,app.kubernetes.io/instance=${release}" \
    -n "${namespace}" --timeout=600s 2>/dev/null || true
  local i prom_name
  for i in $(seq 1 20); do
    prom_name="$(kubectl get prometheus -n "${namespace}" \
      -l "app.kubernetes.io/instance=${release}" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    if [[ -n "${prom_name}" ]]; then
      if kubectl wait --for=condition=Available "prometheus/${prom_name}" \
        -n "${namespace}" --timeout=120s 2>/dev/null; then
        echo "    kube-prometheus-stack ready"
        return 0
      fi
      if kubectl get pod -n "${namespace}" \
        -l "app.kubernetes.io/name=prometheus,app.kubernetes.io/instance=${release}" \
        -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null | grep -q true; then
        echo "    kube-prometheus-stack ready (prometheus pod)"
        return 0
      fi
    fi
    sleep 10
  done
  echo "error: Prometheus not available within 5m" >&2
  return 1
}

deploy_prometheus() {
  if [[ "$(hcl_bool "${PROMETHEUS_ENABLED:-true}")" != "true" ]]; then
    echo "skip Prometheus/Grafana (PROMETHEUS_ENABLED=false)"
    return 0
  fi

  : "${GRAFANA_ADMIN_PASSWORD:?GRAFANA_ADMIN_PASSWORD required when PROMETHEUS_ENABLED=true}"

  local namespace="${PROMETHEUS_NAMESPACE:-monitoring}"
  local release="${PROMETHEUS_RELEASE:-prometheus}"
  local helm_repo="${PROMETHEUS_HELM_REPO:-https://prometheus-community.github.io/helm-charts}"
  local chart="${PROMETHEUS_CHART:-prometheus-community/kube-prometheus-stack}"
  local wait_timeout="${PROMETHEUS_WAIT_TIMEOUT:-15m}"
  local values="${HOMELAB_ROOT}/helm-homelab/prometheus/values.yaml"
  local alertmanager_enabled retention

  alertmanager_enabled="$(hcl_bool "${ALERTMANAGER_ENABLED:-false}")"
  retention="${PROMETHEUS_RETENTION:-15d}"

  if [[ ! -f "${values}" ]]; then
    echo "error: missing ${values}" >&2
    return 1
  fi

  ensure_helm_cli
  echo "==> helm: kube-prometheus-stack (${release}) → namespace ${namespace}"
  echo "    node-exporter: all nodes | alertmanager: ${alertmanager_enabled}"
  echo "    prometheus-operator admission webhooks + TLS: disabled (fresh-cluster safety)"
  helm_repo_ensure prometheus-community "${helm_repo}"

  local -a helm_args=(
    upgrade --install "${release}" "${chart}"
    --namespace "${namespace}"
    --create-namespace
    --timeout "${wait_timeout}"
    --hide-notes
    -f "${values}"
    --set "alertmanager.enabled=${alertmanager_enabled}"
    --set-string "grafana.adminPassword=${GRAFANA_ADMIN_PASSWORD}"
    --set-string "prometheus.prometheusSpec.retention=${retention}"
    --set "defaultRules.rules.alertmanager=${alertmanager_enabled}"
  )

  local lb_ip
  lb_ip="$(lb_scrape_ip)"
  if [[ -n "${lb_ip}" ]]; then
    local lb_values
    lb_values="$(write_lb_scrape_values "${lb_ip}")"
    helm_args+=(-f "${lb_values}")
    echo "    LB scrape: ${lb_ip}:9100 (node) + ${lb_ip}:8404 (haproxy)"
  fi
  if [[ "$(hcl_bool "${LOKI_ENABLED:-false}")" == "true" ]]; then
    local loki_ds_values
    loki_ds_values="$(write_loki_grafana_datasource_values)"
    helm_args+=(-f "${loki_ds_values}")
    echo "    Grafana: Loki datasource → ${LOKI_RELEASE:-loki}-gateway"
  fi
  if [[ "$(hcl_bool "${GATEWAY_ENABLED:-true}")" == "true" ]]; then
    load_secrets
    local grafana_url="https://${GRAFANA_HOSTNAME:-grafana}.${GATEWAY_DOMAIN}/"
    helm_args+=(
      --set-string "grafana.grafana.ini.server.root_url=${grafana_url}"
      --set-string "grafana.grafana.ini.server.domain=${GRAFANA_HOSTNAME:-grafana}.${GATEWAY_DOMAIN}"
    )
    echo "    Grafana: root_url ${grafana_url}"
  fi
  if [[ -n "${PROMETHEUS_CHART_VERSION:-}" ]]; then
    helm_args+=(--version "${PROMETHEUS_CHART_VERSION}")
  fi

  # Apply without Helm --wait; kubectl rollout after (avoids progress deadline on etcd blips).
  local attempts="${HELM_RETRY_ATTEMPTS:-3}" attempt=1 prom_status=""
  helm_recover_stuck_release "${release}" "${namespace}"
  prom_status="$(helm status "${release}" -n "${namespace}" -o json 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("info",{}).get("status",""))' 2>/dev/null)" || prom_status=""
  if [[ "${prom_status}" == "failed" ]]; then
    echo "==> recovering failed Prometheus Helm release before retry"
    cleanup_prometheus_install
    wait_for_etcd_cooldown
  elif [[ "$(homelab_helm_profile)" == "k3s" ]]; then
    wait_for_etcd_cooldown
  fi

  while [[ "${attempt}" -le "${attempts}" ]]; do
    if helm_run_with_retry "${release}" "${namespace}" "${helm_args[@]}"; then
      if prometheus_wait_workloads; then
        return 0
      fi
      echo "error: prometheus workloads not ready (attempt ${attempt}/${attempts})" >&2
    else
      echo "error: helm ${release} apply failed (attempt ${attempt}/${attempts})" >&2
    fi
    if [[ "${attempt}" -ge "${attempts}" ]]; then
      return 1
    fi
    cleanup_prometheus_install
    wait_for_etcd_cooldown
    attempt=$((attempt + 1))
  done
  return 1
}

deploy_tailscale_exporter() {
  if [[ "$(hcl_bool "${TAILSCALE_EXPORTER_ENABLED:-false}")" != "true" ]]; then
    echo "skip tailscale-exporter (TAILSCALE_EXPORTER_ENABLED=false)"
    return 0
  fi
  if [[ "$(hcl_bool "${PROMETHEUS_ENABLED:-true}")" != "true" ]]; then
    echo "skip tailscale-exporter (PROMETHEUS_ENABLED=false — no ServiceMonitor consumer)"
    return 0
  fi
  : "${TAILSCALE_TAILNET:?TAILSCALE_TAILNET required for tailscale-exporter}"
  : "${TAILSCALE_OAUTH_CLIENT_ID:?TAILSCALE_OAUTH_CLIENT_ID required for tailscale-exporter}"
  : "${TAILSCALE_OAUTH_CLIENT_SECRET:?TAILSCALE_OAUTH_CLIENT_SECRET required for tailscale-exporter}"

  local namespace="${TAILSCALE_EXPORTER_NAMESPACE:-tailscale-exporter}"
  local release="${TAILSCALE_EXPORTER_RELEASE:-tailscale-exporter}"
  local helm_repo="${TAILSCALE_EXPORTER_HELM_REPO:-https://adinhodovic.github.io/tailscale-exporter}"
  local chart="${TAILSCALE_EXPORTER_CHART:-adinhodovic/tailscale-exporter}"
  local wait_timeout="${TAILSCALE_EXPORTER_WAIT_TIMEOUT:-5m}"
  local values="${HOMELAB_ROOT}/helm-homelab/tailscale-exporter/values.yaml"

  ensure_helm_cli
  echo "==> helm: tailscale-exporter (${release}) → Tailscale API metrics"
  kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl create secret generic tailscale-exporter-oauth \
    --namespace "${namespace}" \
    --from-literal=tailnet="${TAILSCALE_TAILNET}" \
    --from-literal=client-id="${TAILSCALE_OAUTH_CLIENT_ID}" \
    --from-literal=client-secret="${TAILSCALE_OAUTH_CLIENT_SECRET}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  helm_repo_ensure adinhodovic "${helm_repo}"
  local -a helm_args=(
    upgrade --install "${release}" "${chart}"
    --namespace "${namespace}"
    --create-namespace
    --timeout "${wait_timeout}"
    --hide-notes
    -f "${values}"
  )
  if [[ -n "${TAILSCALE_EXPORTER_CHART_VERSION:-}" ]]; then
    helm_args+=(--version "${TAILSCALE_EXPORTER_CHART_VERSION}")
  fi
  helm_install_release "$(helm_stack_install_mode)" "${release}" "${namespace}" false "${helm_args[@]}"
}

deploy_trivy_operator() {
  if [[ "$(hcl_bool "${TRIVY_OPERATOR_ENABLED:-false}")" != "true" ]]; then
    echo "skip trivy-operator (TRIVY_OPERATOR_ENABLED=false)"
    return 0
  fi
  if [[ "$(hcl_bool "${PROMETHEUS_ENABLED:-true}")" != "true" ]]; then
    echo "skip trivy-operator (PROMETHEUS_ENABLED=false — no ServiceMonitor consumer)"
    return 0
  fi

  local namespace="${TRIVY_OPERATOR_NAMESPACE:-trivy-system}"
  local release="${TRIVY_OPERATOR_RELEASE:-trivy-operator}"
  local helm_repo="${TRIVY_OPERATOR_HELM_REPO:-https://aquasecurity.github.io/helm-charts/}"
  local chart="${TRIVY_OPERATOR_CHART:-aqua/trivy-operator}"
  local wait_timeout="${TRIVY_OPERATOR_WAIT_TIMEOUT:-10m}"
  local values="${HOMELAB_ROOT}/helm-homelab/trivy-operator/values.yaml"
  local values_talos="${HOMELAB_ROOT}/helm-homelab/trivy-operator/values-talos.yaml"

  if [[ ! -f "${values}" ]]; then
    echo "error: missing ${values}" >&2
    return 1
  fi

  ensure_helm_cli
  echo "==> helm: trivy-operator (${release}) → namespace ${namespace}"
  echo "    scans: workloads in all namespaces | metrics → Grafana dashboard 16337"
  helm_repo_ensure aqua "${helm_repo}"

  local -a helm_args=(
    upgrade --install "${release}" "${chart}"
    --namespace "${namespace}"
    --create-namespace
    --timeout "${wait_timeout}"
    --hide-notes
    -f "${values}"
  )
  if [[ "$(hcl_bool "${TALOS_ENABLED:-false}")" == "true" && -f "${values_talos}" ]]; then
    echo "    talos: disable node-collector compliance (immutable root FS)"
    helm_args+=(-f "${values_talos}")
  fi
  if [[ -n "${TRIVY_OPERATOR_CHART_VERSION:-}" ]]; then
    helm_args+=(--version "${TRIVY_OPERATOR_CHART_VERSION}")
  fi
  helm_install_release "$(helm_stack_install_mode)" "${release}" "${namespace}" true "${helm_args[@]}"
}

deploy_loki() {
  if [[ "$(hcl_bool "${LOKI_ENABLED:-false}")" != "true" ]]; then
    echo "skip Loki (LOKI_ENABLED=false)"
    return 0
  fi
  if [[ "$(hcl_bool "${PROMETHEUS_ENABLED:-true}")" != "true" ]]; then
    echo "skip Loki (PROMETHEUS_ENABLED=false — Grafana required)"
    return 0
  fi

  local namespace="${LOKI_NAMESPACE:-monitoring}"
  local release="${LOKI_RELEASE:-loki}"
  local helm_repo="${LOKI_HELM_REPO:-https://grafana.github.io/helm-charts}"
  local chart="${LOKI_CHART:-grafana/loki}"
  local wait_timeout="${LOKI_WAIT_TIMEOUT:-10m}"
  local values="${HOMELAB_ROOT}/helm-homelab/loki/values.yaml"
  local retention="${LOKI_RETENTION:-168h}"
  local storage_size="${LOKI_STORAGE_SIZE:-20Gi}"
  local node_port="${LOKI_GATEWAY_NODE_PORT:-31080}"

  if [[ ! -f "${values}" ]]; then
    echo "error: missing ${values}" >&2
    return 1
  fi

  ensure_helm_cli
  echo "==> helm: Loki (${release}) → namespace ${namespace}"
  echo "    retention: ${retention} | storage: ${storage_size} | push NodePort: ${node_port}"
  helm_repo_ensure grafana "${helm_repo}"

  local -a helm_args=(
    upgrade --install "${release}" "${chart}"
    --namespace "${namespace}"
    --create-namespace
    --timeout "${wait_timeout}"
    --hide-notes
    -f "${values}"
    --set-string "loki.limits_config.retention_period=${retention}"
    --set-string "singleBinary.persistence.size=${storage_size}"
    --set-string "gateway.service.nodePort=${node_port}"
  )
  if [[ -n "${LOKI_CHART_VERSION:-}" ]]; then
    helm_args+=(--version "${LOKI_CHART_VERSION}")
  fi
  helm_install_release "$(helm_stack_install_mode)" "${release}" "${namespace}" false "${helm_args[@]}"
}

show_prometheus_summary() {
  load_secrets
  if [[ "$(hcl_bool "${PROMETHEUS_ENABLED:-true}")" != "true" ]]; then
    return 0
  fi

  local domain gateway alertmanager
  domain="${GATEWAY_DOMAIN:-}"
  gateway="$(hcl_bool "${GATEWAY_ENABLED:-true}")"
  alertmanager="$(hcl_bool "${ALERTMANAGER_ENABLED:-false}")"

  echo ""
  echo "================================================================"
  echo " Prometheus + Grafana"
  echo "================================================================"
  echo ""
  echo "  Node metrics:  node-exporter DaemonSet (all K3s nodes)"
  echo "  Cluster:     kube-state-metrics + Kubernetes / K3s targets"
  echo "  Alertmanager: ${alertmanager}"
  if [[ "${gateway}" == "true" ]] && [[ -n "${domain}" ]]; then
    echo "  Grafana:     https://grafana.${domain}  (admin / secrets.env)"
    echo "  Prometheus:  https://prometheus.${domain}"
  else
    echo "  Grafana:     kubectl -n ${PROMETHEUS_NAMESPACE:-monitoring} port-forward svc/${PROMETHEUS_RELEASE:-prometheus}-grafana 3000:80"
    echo "  Prometheus:  kubectl -n ${PROMETHEUS_NAMESPACE:-monitoring} port-forward svc/${PROMETHEUS_RELEASE:-prometheus}-kube-prometheus-prometheus 9090:9090"
  fi
  echo ""
  echo "  # Grafana login: admin + GRAFANA_ADMIN_PASSWORD from secrets.env"
  if [[ "$(hcl_bool "${LOKI_ENABLED:-false}")" == "true" ]]; then
    echo ""
    echo "  Logs (Loki):   Grafana → Homelab → Logging Dashboard via Loki v3"
    echo "                 filter: service_name=lb, container_name=haproxy, instance=k8s-homelab-lb"
  fi
  if [[ "$(hcl_bool "${TRIVY_OPERATOR_ENABLED:-false}")" == "true" ]]; then
    echo ""
    echo "  Security:      Grafana → Homelab → Trivy Operator - Vulnerabilities (16337)"
    echo "  Reports:       kubectl get vulnerabilityreports --all-namespaces"
  fi
  if [[ "$(hcl_bool "${VELERO_ENABLED:-false}")" == "true" ]]; then
    echo ""
    echo "  Backups:       Grafana → Homelab → Velero Overview (23838)"
  fi
  echo ""
}

# Talos ships Pod Security Admission with enforce=baseline (kube-system exempt only).
# Platform Helm charts (MetalLB speaker, Longhorn, etc.) need privileged namespaces.
ensure_privileged_namespace() {
  local namespace="${1:?namespace required}"
  kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl label namespace "${namespace}" \
    pod-security.kubernetes.io/enforce=privileged \
    pod-security.kubernetes.io/warn=privileged \
    pod-security.kubernetes.io/audit=privileged \
    --overwrite >/dev/null
}

ensure_talos_platform_namespaces() {
  if [[ "$(hcl_bool "${TALOS_ENABLED:-false}")" != "true" ]]; then
    return 0
  fi

  local -a namespaces=(
    "${METALLB_NAMESPACE:-metallb-system}"
    "${LONGHORN_NAMESPACE:-longhorn-system}"
    "${CERT_MANAGER_NAMESPACE:-cert-manager}"
    "${SEALED_SECRETS_NAMESPACE:-kube-system}"
    "${RELOADER_NAMESPACE:-reloader}"
    "${GATEWAY_NAMESPACE:-envoy-gateway-system}"
    "${DATADOG_NAMESPACE:-datadog}"
    "${PROMETHEUS_NAMESPACE:-monitoring}"
    "${LOKI_NAMESPACE:-monitoring}"
    "${TAILSCALE_EXPORTER_NAMESPACE:-tailscale-exporter}"
    "${TRIVY_OPERATOR_NAMESPACE:-trivy-system}"
    "${ARGOCD_NAMESPACE:-argocd}"
    "${EXTERNAL_DNS_NAMESPACE:-external-dns}"
    "${VELERO_NAMESPACE:-velero}"
    tailscale
  )

  echo "==> Talos: platform namespaces → pod-security enforce=privileged"
  local ns
  while IFS= read -r ns; do
    [[ -n "${ns}" ]] || continue
    [[ "${ns}" == "kube-system" ]] && continue
    ensure_privileged_namespace "${ns}"
  done < <(printf '%s\n' "${namespaces[@]}" | sort -u)
}

# After Talos upgrade/reinstall, old Node objects (e.g. k8s-homelab-*) stay NotReady while
# new ones (talos-*) register with the same IP — DaemonSets never reach desired count.
prune_stale_kubernetes_nodes() {
  if [[ "$(hcl_bool "${TALOS_ENABLED:-false}")" != "true" ]]; then
    return 0
  fi
  if ! command -v kubectl >/dev/null 2>&1; then
    return 0
  fi

  local nodes_json pruned
  nodes_json="$(kubectl get nodes -o json 2>/dev/null)" || return 0
  [[ -n "${nodes_json}" ]] || return 0
  pruned="$(printf '%s' "${nodes_json}" | python3 <<'PY'
import json
import subprocess
import sys

raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
data = json.loads(raw)
by_ip: dict[str, list] = {}
for node in data.get("items", []):
    name = node["metadata"]["name"]
    ready = any(
        c.get("type") == "Ready" and c.get("status") == "True"
        for c in node.get("status", {}).get("conditions", [])
    )
    for addr in node.get("status", {}).get("addresses", []):
        if addr.get("type") != "InternalIP":
            continue
        by_ip.setdefault(addr["address"], []).append((name, ready))

deleted = []
for ip, entries in by_ip.items():
    if len(entries) < 2:
        continue
    ready_names = [n for n, ok in entries if ok]
    if not ready_names:
        continue
    for name, ok in entries:
        if ok:
            continue
        subprocess.run(
            ["kubectl", "delete", "node", name, "--wait=false"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        deleted.append(f"{name} ({ip})")

print("\n".join(deleted))
PY
)" || true

  if [[ -n "${pruned}" ]]; then
    echo "==> Kubernetes: pruned stale NotReady nodes"
    while IFS= read -r line; do
      [[ -n "${line}" ]] && echo "    deleted ${line}"
    done <<<"${pruned}"
    sleep 5
  fi
}

deploy_helm_workloads() {
  load_secrets
  local kubeconfig
  kubeconfig="$(kubeconfig_path)"
  if [[ ! -f "${kubeconfig}" ]]; then
    echo "error: missing ${kubeconfig} — run fetch_kubeconfig first" >&2
    return 1
  fi
  export KUBECONFIG="${kubeconfig}"
  ensure_talos_platform_namespaces
  prune_stale_kubernetes_nodes
  wait_for_cluster_api_stable

  if [[ "$(homelab_helm_profile)" == "talos" ]]; then
    deploy_helm_workloads_talos
  else
    deploy_helm_workloads_k3s
  fi
}

deploy_helm_critical_path() {
  echo "==> Helm critical path (MetalLB → Longhorn → Prometheus → cert-manager → Gateway)"
  deploy_metallb
  wait_for_etcd_cooldown
  deploy_longhorn
}

deploy_helm_finish() {
  apply_platform_httproutes
  bootstrap_argocd
  deploy_external_dns
  echo "==> finish (Promtail + TLS cert in parallel)"
  helm_run_parallel wait_for_gateway_tls_certificate run_ansible_promtail
}

# K3s: etcd on control-plane nodes — sequential stack, longer cooldowns (was stable before parallel burst).
deploy_helm_workloads_k3s() {
  echo "==> Helm deploy profile: K3s (sequential stack)"
  deploy_helm_critical_path
  wait_for_etcd_cooldown
  deploy_prometheus
  verify_cloudflare_acme_dns01_ready
  deploy_cert_manager
  wait_for_etcd_cooldown
  deploy_envoy_gateway
  apply_gateway_platform

  echo "==> Helm stack (K3s sequential — one chart at a time)"
  deploy_sealed_secrets
  deploy_reloader
  deploy_tailscale_exporter
  deploy_datadog
  wait_for_etcd_cooldown
  deploy_loki
  wait_for_etcd_cooldown
  deploy_trivy_operator
  deploy_velero
  wait_for_etcd_cooldown
  deploy_argocd

  deploy_helm_finish
}

# Talos: dedicated control plane — parallel background installs + single readiness wait.
deploy_helm_workloads_talos() {
  echo "==> Helm deploy profile: Talos (parallel background stack)"
  deploy_helm_critical_path
  deploy_prometheus
  verify_cloudflare_acme_dns01_ready
  deploy_cert_manager
  wait_for_etcd_cooldown
  deploy_envoy_gateway
  apply_gateway_platform

  echo "==> Helm parallel stack (install together, single readiness wait)"
  helm_begin_background_phase
  helm_run_parallel \
    deploy_sealed_secrets \
    deploy_reloader \
    deploy_tailscale_exporter \
    deploy_datadog \
    deploy_loki \
    deploy_trivy_operator \
    deploy_velero \
    deploy_argocd
  helm_end_background_phase

  deploy_helm_finish
}

ensure_datadog_api_secret() {
  local namespace="${1:?namespace required}"
  local secret_name="${2:-datadog-api-key}"
  : "${DATADOG_API_KEY:?DATADOG_API_KEY required when DATADOG_ENABLED=true}"

  kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl create secret generic "${secret_name}" \
    --namespace "${namespace}" \
    --from-literal=api-key="${DATADOG_API_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

datadog_app_url() {
  local site="${1:-datadoghq.com}"
  case "${site}" in
    datadoghq.eu) echo "https://app.datadoghq.eu" ;;
    us3.datadoghq.com) echo "https://us3.datadoghq.com" ;;
    us5.datadoghq.com) echo "https://us5.datadoghq.com" ;;
    ap1.datadoghq.com) echo "https://ap1.datadoghq.com" ;;
    ap2.datadoghq.com) echo "https://ap2.datadoghq.com" ;;
    *) echo "https://app.datadoghq.com" ;;
  esac
}

deploy_datadog() {
  if [[ "$(hcl_bool "${DATADOG_ENABLED:-true}")" != "true" ]]; then
    echo "skip Datadog (DATADOG_ENABLED=false)"
    return 0
  fi

  : "${DATADOG_API_KEY:?DATADOG_API_KEY required when DATADOG_ENABLED=true}"

  local namespace="${DATADOG_NAMESPACE:-datadog}"
  local release="${DATADOG_RELEASE:-datadog}"
  local cluster_name="${DATADOG_CLUSTER_NAME:-${ENV_ID}}"
  local site="${DATADOG_SITE:-datadoghq.eu}"
  local helm_repo="${DATADOG_HELM_REPO:-https://helm.datadoghq.com}"
  local chart="${DATADOG_CHART:-datadog/datadog}"
  local wait_timeout="${DATADOG_WAIT_TIMEOUT:-15m}"
  local values="${HOMELAB_ROOT}/helm-homelab/datadog/values.yaml"

  if [[ ! -f "${values}" ]]; then
    echo "error: missing ${values}" >&2
    return 1
  fi

  if ! command -v helm >/dev/null 2>&1; then
    echo "==> install Helm"
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi

  echo "==> helm: Datadog (${release}) → namespace ${namespace}"
  ensure_datadog_api_secret "${namespace}"
  helm_repo_ensure datadog "${helm_repo}"

  local -a helm_args=(
    upgrade --install "${release}" "${chart}"
    --namespace "${namespace}"
    --create-namespace
    --timeout "${wait_timeout}"
    --hide-notes
    -f "${values}"
    --set-string "datadog.clusterName=${cluster_name}"
    --set-string "datadog.site=${site}"
  )
  if [[ -n "${DATADOG_CHART_VERSION:-}" ]]; then
    helm_args+=(--version "${DATADOG_CHART_VERSION}")
  fi

  helm_install_release "$(helm_stack_install_mode)" "${release}" "${namespace}" true "${helm_args[@]}"
}

show_datadog_summary() {
  load_secrets
  if [[ "$(hcl_bool "${DATADOG_ENABLED:-true}")" != "true" ]]; then
    return 0
  fi

  local cluster_name site app_url
  cluster_name="${DATADOG_CLUSTER_NAME:-${ENV_ID}}"
  site="${DATADOG_SITE:-datadoghq.eu}"
  app_url="$(datadog_app_url "${site}")"

  echo ""
  echo "================================================================"
  echo " Datadog"
  echo "================================================================"
  echo ""
  echo "  UI:      ${app_url}"
  echo "  Cluster: ${cluster_name}"
  echo ""
}

# Talos PSA prep creates namespace + labels before Helm; default SA/kube-root-ca.crt
# exist in every namespace — do not treat those as an orphaned install.
argocd_namespace_is_psa_prep_only() {
  local namespace="${1:?namespace required}"
  if ! kubectl get namespace "${namespace}" >/dev/null 2>&1; then
    return 1
  fi
  local workload_count
  workload_count="$(kubectl get pods,deployments,statefulsets,daemonsets,replicasets,jobs \
    -n "${namespace}" -o name 2>/dev/null | wc -l | tr -d ' ')"
  [[ "${workload_count}" == "0" ]]
}

cleanup_orphan_argocd_install() {
  local namespace="${1:-argocd}"
  local resource crd

  if kubectl get namespace "${namespace}" >/dev/null 2>&1; then
    if argocd_namespace_is_psa_prep_only "${namespace}"; then
      echo "==> keep empty PSA-prep namespace ${namespace} (Helm will install into it)"
    else
      echo "==> remove orphaned namespace ${namespace}"
      kubectl delete namespace "${namespace}" --wait=true --timeout=300s
    fi
  fi

  for crd in applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io; do
    if kubectl get crd "${crd}" >/dev/null 2>&1 \
      && ! kubectl get crd "${crd}" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null | grep -q Helm; then
      echo "==> remove orphaned CRD ${crd}"
      kubectl delete crd "${crd}" --wait=true --timeout=120s
    fi
  done

  for resource in \
    $(kubectl get clusterrole -o name 2>/dev/null | grep argocd || true) \
    $(kubectl get clusterrolebinding -o name 2>/dev/null | grep argocd || true) \
    $(kubectl get validatingwebhookconfiguration -o name 2>/dev/null | grep argocd || true) \
    $(kubectl get mutatingwebhookconfiguration -o name 2>/dev/null | grep argocd || true); do
    if [[ -n "${resource}" ]]; then
      echo "==> remove orphaned ${resource}"
      kubectl delete "${resource}" --ignore-not-found --wait=true --timeout=60s
    fi
  done
}

deploy_longhorn() {
  if [[ "$(hcl_bool "${LONGHORN_ENABLED:-true}")" != "true" ]]; then
    echo "skip Longhorn (LONGHORN_ENABLED=false)"
    return 0
  fi

  local tailscale_ingress
  tailscale_ingress="$(hcl_bool "${TAILSCALE_ENABLED:-false}")"
  if [[ "${tailscale_ingress}" != "true" ]]; then
    echo "note: Longhorn UI ingress disabled (TAILSCALE_ENABLED=false)"
  fi

  local namespace="${LONGHORN_NAMESPACE:-longhorn-system}"
  local release="${LONGHORN_RELEASE:-longhorn}"
  local hostname="${LONGHORN_HOSTNAME:-longhorn}"
  local helm_repo="${LONGHORN_HELM_REPO:-https://charts.longhorn.io}"
  local chart="${LONGHORN_CHART:-longhorn/longhorn}"
  local wait_timeout="${LONGHORN_WAIT_TIMEOUT:-20m}"
  local values="${HOMELAB_ROOT}/helm-homelab/longhorn/values.yaml"
  local data_path="${LONGHORN_MOUNT_PATH:-/var/mnt/longhorn-data}"

  if [[ ! -f "${values}" ]]; then
    echo "error: missing ${values}" >&2
    return 1
  fi

  ensure_helm_cli
  helm_recover_stuck_release "${release}" "${namespace}"
  if kubectl get crd -o name 2>/dev/null | grep -q 'longhorn\.io' \
    && ! helm status "${release}" -n "${namespace}" >/dev/null 2>&1; then
    echo "==> orphaned Longhorn CRDs without Helm release — cleaning up"
    cleanup_longhorn_install
  elif longhorn_has_partial_install && ! longhorn_release_is_healthy; then
    cleanup_longhorn_install
  fi

  echo "==> helm: Longhorn (${release}) → namespace ${namespace}"
  helm_repo_ensure longhorn "${helm_repo}"

  # Single Helm install owns CRDs. Omit --wait; kubectl rollout after apply.
  local -a helm_args=(
    upgrade --install "${release}" "${chart}"
    --namespace "${namespace}"
    --create-namespace
    --timeout "${wait_timeout}"
    --hide-notes
    -f "${values}"
    --set-string "defaultSettings.defaultDataPath=${data_path}"
    --set "ingress.enabled=${tailscale_ingress}"
  )
  if [[ "${tailscale_ingress}" == "true" ]]; then
    : "${TAILSCALE_TAILNET:?TAILSCALE_TAILNET required for Longhorn UI URL}"
    helm_args+=(--set-string "ingress.host=${hostname}")
  fi
  if [[ -n "${LONGHORN_CHART_VERSION:-}" ]]; then
    helm_args+=(--version "${LONGHORN_CHART_VERSION}")
  fi

  if helm "${helm_args[@]}"; then
    wait_for_etcd_cooldown
    longhorn_wait_workloads
    return 0
  fi

  echo "error: helm ${release} failed — retrying after Longhorn cleanup" >&2
  cleanup_longhorn_install
  wait_for_etcd_cooldown
  helm "${helm_args[@]}" || return 1
  longhorn_wait_workloads
}

show_longhorn_summary() {
  load_secrets
  if [[ "$(hcl_bool "${LONGHORN_ENABLED:-true}")" != "true" ]]; then
    return 0
  fi

  local hostname tailnet domain gateway
  hostname="${LONGHORN_HOSTNAME:-longhorn}"
  tailnet="${TAILSCALE_TAILNET:-}"
  domain="${GATEWAY_DOMAIN:-}"
  gateway="$(hcl_bool "${GATEWAY_ENABLED:-true}")"

  if [[ "${gateway}" != "true" ]] && [[ "$(hcl_bool "${TAILSCALE_ENABLED:-false}")" != "true" ]]; then
    return 0
  fi

  echo ""
  echo "================================================================"
  echo " Longhorn"
  echo "================================================================"
  echo ""
  if [[ "${gateway}" == "true" ]] && [[ -n "${domain}" ]]; then
    echo "  UI (LAN):  https://longhorn.${domain}"
  fi
  if [[ "$(hcl_bool "${TAILSCALE_ENABLED:-false}")" == "true" ]] && [[ -n "${tailnet}" ]]; then
    echo "  UI (VPN):  https://${hostname}.${tailnet}"
  fi
  echo ""
}

deploy_argocd() {
  if [[ "$(hcl_bool "${ARGOCD_ENABLED:-true}")" != "true" ]]; then
    echo "skip Argo CD (ARGOCD_ENABLED=false)"
    return 0
  fi

  local tailscale_ingress
  tailscale_ingress="$(hcl_bool "${TAILSCALE_ENABLED:-false}")"
  if [[ "${tailscale_ingress}" != "true" ]]; then
    echo "note: Argo CD ingress disabled (TAILSCALE_ENABLED=false)"
  fi

  local namespace="${ARGOCD_NAMESPACE:-argocd}"
  local release="${ARGOCD_RELEASE:-argocd}"
  local hostname="${ARGOCD_HOSTNAME:-argocd}"
  local helm_repo="${ARGOCD_HELM_REPO:-https://argoproj.github.io/argo-helm}"
  local chart="${ARGOCD_CHART:-argo/argo-cd}"
  local wait_timeout="${ARGOCD_WAIT_TIMEOUT:-10m}"
  local values="${HOMELAB_ROOT}/helm-homelab/argocd/values.yaml"

  if [[ ! -f "${values}" ]]; then
    echo "error: missing ${values}" >&2
    return 1
  fi

  if ! command -v helm >/dev/null 2>&1; then
    echo "==> install Helm"
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi

  echo "==> helm: Argo CD (${release}) → namespace ${namespace}"
  helm_repo_ensure argo "${helm_repo}"

  if ! helm status "${release}" -n "${namespace}" >/dev/null 2>&1; then
    cleanup_orphan_argocd_install "${namespace}"
  fi

  local -a helm_args=(
    upgrade --install "${release}" "${chart}"
    --namespace "${namespace}"
    --create-namespace
    --timeout "${wait_timeout}"
    --hide-notes
    -f "${values}"
  )
  if [[ "${tailscale_ingress}" == "true" ]]; then
    : "${TAILSCALE_TAILNET:?TAILSCALE_TAILNET required for Argo CD URL}"
    helm_args+=(--set "server.ingress.enabled=true")
    helm_args+=(--set-string "server.ingress.hostname=${hostname}")
  else
    helm_args+=(--set "server.ingress.enabled=false")
  fi
  if [[ -n "${ARGOCD_CHART_VERSION:-}" ]]; then
    helm_args+=(--version "${ARGOCD_CHART_VERSION}")
  fi

  helm_install_release "$(helm_stack_install_mode)" "${release}" "${namespace}" true "${helm_args[@]}"
}

show_argocd_summary() {
  load_secrets
  if [[ "$(hcl_bool "${ARGOCD_ENABLED:-true}")" != "true" ]]; then
    return 0
  fi

  local hostname tailnet domain gateway
  hostname="${ARGOCD_HOSTNAME:-argocd}"
  tailnet="${TAILSCALE_TAILNET:-}"
  domain="${GATEWAY_DOMAIN:-}"
  gateway="$(hcl_bool "${GATEWAY_ENABLED:-true}")"

  if [[ "${gateway}" != "true" ]] && [[ "$(hcl_bool "${TAILSCALE_ENABLED:-false}")" != "true" ]]; then
    return 0
  fi

  echo ""
  echo "================================================================"
  echo " Argo CD"
  echo "================================================================"
  echo ""
  if [[ "${gateway}" == "true" ]] && [[ -n "${domain}" ]]; then
    echo "  UI (LAN):  https://argocd.${domain}"
  fi
  if [[ "$(hcl_bool "${TAILSCALE_ENABLED:-false}")" == "true" ]] && [[ -n "${tailnet}" ]]; then
    echo "  UI (VPN):  https://${hostname}.${tailnet}"
  fi
  echo "  User: admin"
  echo ""
  echo "  # initial password:"
  echo "  kubectl -n ${ARGOCD_NAMESPACE:-argocd} get secret argocd-initial-admin-secret \\"
  echo "    -o jsonpath='{.data.password}' | base64 -d; echo"
  echo ""
}

ensure_velero_credentials_secret() {
  local namespace="${1:?namespace required}"
  local secret_name="${2:-velero-credentials}"
  : "${VELERO_S3_ACCESS_KEY:?VELERO_S3_ACCESS_KEY required when VELERO_ENABLED=true}"
  : "${VELERO_S3_SECRET_KEY:?VELERO_S3_SECRET_KEY required when VELERO_ENABLED=true}"

  kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl create secret generic "${secret_name}" \
    --namespace "${namespace}" \
    --from-literal=cloud="[default]
aws_access_key_id=${VELERO_S3_ACCESS_KEY}
aws_secret_access_key=${VELERO_S3_SECRET_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

deploy_velero() {
  if [[ "$(hcl_bool "${VELERO_ENABLED:-false}")" != "true" ]]; then
    echo "skip Velero (VELERO_ENABLED=false)"
    return 0
  fi

  : "${VELERO_S3_URL:?VELERO_S3_URL required when VELERO_ENABLED=true}"
  : "${VELERO_S3_BUCKET:?VELERO_S3_BUCKET required when VELERO_ENABLED=true}"
  : "${VELERO_S3_ACCESS_KEY:?VELERO_S3_ACCESS_KEY required when VELERO_ENABLED=true}"
  : "${VELERO_S3_SECRET_KEY:?VELERO_S3_SECRET_KEY required when VELERO_ENABLED=true}"

  local namespace="${VELERO_NAMESPACE:-velero}"
  local release="${VELERO_RELEASE:-velero}"
  local helm_repo="${VELERO_HELM_REPO:-https://vmware-tanzu.github.io/helm-charts}"
  local chart="${VELERO_CHART:-vmware-tanzu/velero}"
  local wait_timeout="${VELERO_WAIT_TIMEOUT:-10m}"
  local values="${HOMELAB_ROOT}/helm-homelab/velero/values.yaml"
  local s3_insecure schedule_enabled schedule_cron backup_ttl

  s3_insecure="$(hcl_bool "${VELERO_S3_INSECURE:-true}")"
  schedule_enabled="$(hcl_bool "${VELERO_SCHEDULE_ENABLED:-true}")"
  schedule_cron="${VELERO_SCHEDULE_CRON:-0 2 * * *}"
  backup_ttl="${VELERO_BACKUP_TTL:-720h}"

  if [[ ! -f "${values}" ]]; then
    echo "error: missing ${values}" >&2
    return 1
  fi

  if ! command -v helm >/dev/null 2>&1; then
    echo "==> install Helm"
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi

  echo "==> helm: Velero (${release}) → namespace ${namespace}"
  ensure_velero_credentials_secret "${namespace}"
  helm_repo_ensure vmware-tanzu "${helm_repo}"

  local -a helm_args=(
    upgrade --install "${release}" "${chart}"
    --namespace "${namespace}"
    --create-namespace
    --timeout "${wait_timeout}"
    --hide-notes
    -f "${values}"
    --set-string "configuration.backupStorageLocation[0].bucket=${VELERO_S3_BUCKET}"
    --set-string "configuration.backupStorageLocation[0].config.s3Url=${VELERO_S3_URL}"
    --set-string "configuration.backupStorageLocation[0].config.publicUrl=${VELERO_S3_URL}"
    --set-string "configuration.backupStorageLocation[0].config.insecureSkipTLSVerify=${s3_insecure}"
    --set "schedules.k8s-nightly.disabled=$([[ "${schedule_enabled}" == "true" ]] && echo false || echo true)"
    --set-string "schedules.k8s-nightly.schedule=${schedule_cron}"
    --set-string "schedules.k8s-nightly.template.ttl=${backup_ttl}"
  )
  if [[ -n "${VELERO_CHART_VERSION:-}" ]]; then
    helm_args+=(--version "${VELERO_CHART_VERSION}")
  fi

  helm_install_release "$(helm_stack_install_mode)" "${release}" "${namespace}" true "${helm_args[@]}"
}

show_velero_summary() {
  load_secrets
  if [[ "$(hcl_bool "${VELERO_ENABLED:-false}")" != "true" ]]; then
    return 0
  fi

  local namespace schedule_cron backup_ttl
  namespace="${VELERO_NAMESPACE:-velero}"
  schedule_cron="${VELERO_SCHEDULE_CRON:-0 2 * * *}"
  backup_ttl="${VELERO_BACKUP_TTL:-720h}"

  echo ""
  echo "================================================================"
  echo " Velero"
  echo "================================================================"
  echo ""
  echo "  Backend: ${VELERO_S3_URL}/${VELERO_S3_BUCKET}"
  echo "  Mode:    K8s resources only (no volume snapshots)"
  if [[ "$(hcl_bool "${VELERO_SCHEDULE_ENABLED:-true}")" == "true" ]]; then
    echo "  Schedule: velero-k8s-nightly (${schedule_cron}, TTL ${backup_ttl})"
  else
    echo "  Schedule: disabled"
  fi
  echo ""
  echo "  kubectl -n ${namespace} get backupstoragelocation,schedule,backup"
  echo "  kubectl -n ${namespace} create -f - <<'EOF'"
  echo "  apiVersion: velero.io/v1"
  echo "  kind: Backup"
  echo "  metadata:"
  echo "    name: manual-test"
  echo "    namespace: ${namespace}"
  echo "  spec:"
  echo "    snapshotVolumes: false"
  echo "  EOF"
  echo ""
}

show_tailscale_summary() {
  local tailscale_vars="${HOMELAB_ROOT}/ansible/inventories/${ENV_ID}/group_vars/all/tailscale.yml"
  local acl_file="${GENERATED_DIR}/tailscale-acl-fragment.json"
  if [[ ! -f "${tailscale_vars}" ]] || ! grep -q '^tailscale_enabled: true' "${tailscale_vars}"; then
    return 0
  fi

  local inventory="${HOMELAB_ROOT}/ansible/inventories/${ENV_ID}/hosts.yml"
  local proxy_tag="" homelab_cidr="" env_id="" tailnet=""
  if [[ -f "${inventory}" ]]; then
    proxy_tag="$(grep '^    tailscale_proxy_tag:' "${inventory}" | sed -E 's/^[^:]+:[[:space:]]*"?([^"]*)"?/\1/' || true)"
    homelab_cidr="$(grep '^    homelab_network_cidr:' "${inventory}" | sed -E 's/^[^:]+:[[:space:]]*"?([^"]*)"?/\1/' || true)"
    env_id="$(grep '^    env_id:' "${inventory}" | sed -E 's/^[^:]+:[[:space:]]*"?([^"]*)"?/\1/' || true)"
  fi
  tailnet="$(grep '^tailscale_tailnet:' "${tailscale_vars}" | sed -E 's/^tailscale_tailnet:[[:space:]]*"?([^"]*)"?/\1/' || true)"

  echo ""
  echo "================================================================"
  echo " Tailscale (from Terraform: pool + network)"
  echo "================================================================"
  echo ""
  echo "  Environment:      ${env_id}"
  echo "  Proxmox pool:     ${env_id}"
  echo "  Proxy tag:        ${proxy_tag}"
  echo "  Subnet route:     ${homelab_cidr}"
  echo "  ACL: applied automatically via Tailscale API (before operator install)"
  echo ""
  echo "  Ingress: ingressClassName: tailscale"
  if [[ -n "${tailnet}" ]]; then
    echo "  MagicDNS example: myapp.default.svc.${tailnet}"
  fi
  echo ""
}
