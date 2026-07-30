#!/usr/bin/env bash
# Generate ansible/inventories/<ENV_ID>/hosts.yml from terraform output.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_secrets
apply_platform_toggles
set_tf_dir

if [[ "$(hcl_bool "${TALOS_ENABLED:-false}")" != "true" ]]; then
  setup_k3s_token
  setup_k3s_version
  write_ansible_k3s_vars
fi
write_ansible_tailscale_vars

TF="$(terraform_bin)"
INVENTORY_DIR="${HOMELAB_ROOT}/ansible/inventories/${ENV_ID}"
OUTPUT="${INVENTORY_DIR}/hosts.yml"

cd "${TF_DIR}"

if [[ ! -f terraform.tfstate ]]; then
  echo "error: no terraform state — run deploy-infra.sh first" >&2
  exit 1
fi

mkdir -p "${INVENTORY_DIR}"

export SSH_USER="${SSH_USER:-root}"
export ENV_ID
export TALOS_ENABLED="${TALOS_ENABLED:-false}"
export K3S_TOKEN="${K3S_TOKEN:-}"
export K3S_VERSION="${K3S_VERSION:-}"
export ANSIBLE_SSH_PRIVATE_KEY_FILE="${ANSIBLE_SSH_PRIVATE_KEY_FILE:-}"

${TF} output -json | python3 "${SCRIPT_DIR}/generate-inventory.py" >"${OUTPUT}.tmp"
mv "${OUTPUT}.tmp" "${OUTPUT}"
chmod 644 "${OUTPUT}"

echo "wrote ${OUTPUT}"
generate_tailscale_acl
