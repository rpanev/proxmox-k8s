#!/usr/bin/env bash
# Full homelab teardown: Terraform destroys all VMs and Proxmox resources.

set -euo pipefail

HOMELAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${HOMELAB_ROOT}/scripts/lib/common.sh"

AUTO_APPROVE=false
SERIAL_DESTROY=false
HOMELAB_OS=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Destroy entire homelab stack:
  - Tailscale devices + ACL entries for this project (API)
  - Cloudflare DNS A/TXT records from external-dns (API)
  - Terraform (terrafrom/linux or terrafrom/talos-linux per --os or secrets.env)
  - Generated files: inventory, kubeconfig, k3s token, secrets.auto.tfvars

K3s workloads (Argo CD, Tailscale operator pods) are removed with the VMs.
secrets.env is kept (user config).

Default (no flags):
  1. secrets.env → secrets.auto.tfvars (for destroy)
  2. Prompt: type 'destroy' to confirm
  3. Tailscale cleanup (if TAILSCALE_ENABLED)
  4. Cloudflare DNS cleanup (if EXTERNAL_DNS_ENABLED + GATEWAY_ENABLED)
  5. terraform destroy
  6. remove generated inventory / kubeconfig / secrets / secrets.auto.tfvars

Options:
  --os=linux|talos    Platform OS / Terraform stack (default: linux, or secrets.env TALOS_ENABLED)
  -y, --yes           Destroy without typing 'destroy'
  --serial-destroy    Force terraform destroy -parallelism=1 (auto when CEPH_STORAGE=true)
  -h, --help          Show this help

Examples:
  $(basename "$0") -y --os=talos
  $(basename "$0") -y                 # auto-destroy

Deploy: ./deploy-infra.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) AUTO_APPROVE=true; shift ;;
    --serial-destroy) SERIAL_DESTROY=true; shift ;;
    --os=*) HOMELAB_OS="${1#*=}"; shift ;;
    --os)
      [[ $# -ge 2 ]] || { echo "error: --os requires linux or talos" >&2; exit 1; }
      HOMELAB_OS="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

load_secrets
resolve_homelab_os
apply_platform_toggles
set_tf_dir

if [[ "$(hcl_bool "${CEPH_STORAGE:-false}")" == "true" ]] && ! ${SERIAL_DESTROY}; then
  SERIAL_DESTROY=true
  echo "==> CEPH_STORAGE=true — terraform destroy -parallelism=1 (serial on Ceph)"
fi

write_tfvars

TF="$(terraform_bin)"
echo "==> platform OS: ${HOMELAB_OS} (terraform: terrafrom/$(terraform_stack_name))"
echo "==> terraform stack: ${TF_DIR}"
cd "${TF_DIR}"

if [[ ! -f terraform.tfstate ]]; then
  echo "error: no terraform state in ${TF_DIR}" >&2
  exit 1
fi

${TF} init -input=false

DESTROY_ARGS=(-input=false)
if ${SERIAL_DESTROY}; then
  DESTROY_ARGS+=(-parallelism=1)
fi
if ${AUTO_APPROVE}; then
  DESTROY_ARGS+=(-auto-approve)
else
  read -r -p "Destroy ALL homelab resources? Type 'destroy' to confirm: " confirm
  [[ "${confirm}" == "destroy" ]] || { echo "aborted"; exit 1; }
fi

cleanup_tailscale_homelab || {
  if ! ${AUTO_APPROVE}; then
    read -r -p "Tailscale cleanup failed. Continue with terraform destroy? [y/N] " continue_destroy
    [[ "${continue_destroy,,}" == "y" ]] || { echo "aborted"; exit 1; }
  else
    echo "warning: Tailscale cleanup failed; continuing with terraform destroy" >&2
  fi
}

cleanup_external_dns_homelab || {
  if ! ${AUTO_APPROVE}; then
    read -r -p "Cloudflare DNS cleanup failed. Continue with terraform destroy? [y/N] " continue_destroy
    [[ "${continue_destroy,,}" == "y" ]] || { echo "aborted"; exit 1; }
  else
    echo "warning: Cloudflare DNS cleanup failed; continuing with terraform destroy" >&2
  fi
}

echo "==> terraform destroy"
${TF} destroy "${DESTROY_ARGS[@]}"

cleanup_deploy_artifacts

echo "done."
