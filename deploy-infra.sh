#!/usr/bin/env bash
echo "Starting deploy-infra.sh"
# Full homelab deploy: Terraform (Proxmox VMs) + Ansible (K3s bootstrap).

set -euo pipefail

HOMELAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${HOMELAB_ROOT}/scripts/lib/common.sh"


AUTO_APPROVE=false
INFRA_ONLY=false
HELM_ONLY=false
SERIAL_CLONES=false
HOMELAB_OS=""
ANSIBLE_EXTRA=()

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [-- extra ansible-playbook args]

Full deploy: Proxmox VMs (Terraform) then K8s bootstrap (Ansible or talosctl).

Platform OS (Terraform stack):
  --os=linux          Debian + K3s (default)
  --os=talos          Talos Linux + talosctl bootstrap
  Falls back to secrets.env TALOS_ENABLED when --os is omitted.

Platform toggles (secrets.env — true/false):
  CEPH_STORAGE           Proxmox VM disks on Ceph (false → PROXMOX_DATASTORE_ID / NFS)
  PROXMOX_SHARED_STORAGE Spread VMs across nodes when using shared NFS (default true)
  PROXMOX_DATASTORE_ID   Datastore when CEPH_STORAGE=false (default SSD-storage)
  TAILSCALE_ENABLED      Tailscale operator + Ingress (optional — remote VPN access)
  GATEWAY_ENABLED        Gateway API + MetalLB + cert-manager + Cloudflare TLS (home LAN)
  EXTERNAL_DNS_ENABLED   Cloudflare A records for HTTPRoutes → GATEWAY_LB_IP (default true)
  LONGHORN_ENABLED       Worker data disks + Longhorn Helm
  SNAPSHOT_CONTROLLER_ENABLED  CSI VolumeSnapshot CRDs + controller (Kasten/Longhorn)
  DATADOG_ENABLED        Datadog Agent Helm (needs DATADOG_API_KEY)
  PROMETHEUS_ENABLED     Prometheus + Grafana (kube-prometheus-stack)
  LOKI_ENABLED           Loki log store + Ansible Promtail on all VMs
  ALERTMANAGER_ENABLED   Alertmanager sub-chart (default false)
  ARGOCD_ENABLED         Argo CD Helm bootstrap
  ARGOCD_BOOTSTRAP_ENABLED  Argo app-of-apps from gitops/apps
  SEALED_SECRETS_ENABLED Sealed Secrets controller (GitOps secrets)
  RELOADER_ENABLED       Stakater Reloader
  VELERO_ENABLED         Velero Helm (needs VELERO_S3_* MinIO credentials)
  KASTEN_ENABLED         Veeam Kasten K10 + NFS Location (KASTEN_NFS_*)

Default (no flags):
  1. secrets.env → platform toggles, API keys, network, cluster size
  2. terraform init → plan → prompt "Apply? [y/N]" → apply
  3. ansible inventory (hosts.yml)
  4a. --os=linux:  ansible deploy.yml (K3s → workers → Tailscale operator)
  4b. --os=talos:  ansible HAProxy on LB → talosctl bootstrap
                    (run deploy-tailscale.yml separately for the operator)
  5. fetch kubeconfig (K3s via SSH or Talos via talosctl)
  6. helm workloads (Gateway, Longhorn, Argo CD, …) — same toggles as K3s path
  7. cluster summary

Config:
  secrets.env            platform toggles, API keys, SSH, network, K3S_VERSION
  terrafrom/linux/         Terraform stack for --os=linux
  terrafrom/talos-linux/   Terraform stack for --os=talos
  Each stack has its own terraform.tfvars (sizing, placement, HA)

Options:
  --os=linux|talos    Platform OS / Terraform stack (default: linux, or secrets.env TALOS_ENABLED)
  -y, --yes           Skip terraform apply confirmation
  --infra-only        Terraform + inventory only, skip Ansible
  --helm-only         Skip Terraform/Ansible; deploy Helm workloads only
                      (never installs Tailscale operator; existing one required)
  --serial-clones     Force terraform -parallelism=1 (auto when CEPH_STORAGE=true)
  -h, --help          Show this help

Examples:
  $(basename "$0")                      # full interactive deploy
  $(basename "$0") -y                   # full deploy, no prompts
  $(basename "$0") -y --serial-clones   # first deploy / many new VMs
  $(basename "$0") -y --os=talos --serial-clones
  $(basename "$0") --infra-only         # VMs only
  $(basename "$0") --helm-only          # Helm only (cluster must exist)

Teardown: ./destroy-infra.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) AUTO_APPROVE=true; shift ;;
    --infra-only) INFRA_ONLY=true; shift ;;
    --helm-only) HELM_ONLY=true; shift ;;
    --serial-clones) SERIAL_CLONES=true; shift ;;
    --os=*) HOMELAB_OS="${1#*=}"; shift ;;
    --os)
      [[ $# -ge 2 ]] || { echo "error: --os requires linux or talos" >&2; exit 1; }
      HOMELAB_OS="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift; ANSIBLE_EXTRA=("$@"); break ;;
    *) echo "unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

load_secrets
resolve_homelab_os
apply_platform_toggles
set_tf_dir

if [[ "$(hcl_bool "${CEPH_STORAGE:-false}")" == "true" ]] && ! ${SERIAL_CLONES}; then
  SERIAL_CLONES=true
  echo "==> CEPH_STORAGE=true — terraform -parallelism=1 (serial VM clones on Ceph)"
fi

TALOS_MODE=false
[[ "${HOMELAB_OS}" == "talos" ]] && TALOS_MODE=true

echo "==> platform OS: ${HOMELAB_OS} (terraform: terrafrom/$(terraform_stack_name))"
write_tfvars

TF="$(terraform_bin)"
echo "==> terraform stack: terrafrom/$(terraform_stack_name) (${TF_DIR})"
cd "${TF_DIR}"

if ${HELM_ONLY}; then
  if [[ ! -f "$(kubeconfig_path)" ]]; then
    if ${TALOS_MODE}; then
      echo "error: missing $(kubeconfig_path) — run full deploy or bootstrap-talos.sh first" >&2
      exit 1
    fi
    fetch_kubeconfig
  fi
  deploy_helm_workloads
  show_kubeconfig_summary
  show_gateway_summary
  show_tailscale_summary
  show_longhorn_summary
  show_datadog_summary
  show_prometheus_summary
  show_argocd_summary
  show_sealed_secrets_summary
  show_velero_summary
  show_kasten_summary
  echo "done."
  exit 0
fi

if ! ${TALOS_MODE}; then
  setup_k3s_token
  setup_k3s_version
  write_ansible_k3s_vars
fi
write_ansible_tailscale_vars
write_ansible_longhorn_vars
write_ansible_loki_vars

TF="$(terraform_bin)"
cd "${TF_DIR}"

echo "==> terraform init"
${TF} init -input=false

PLAN_ARGS=(-input=false -out=tfplan)
if ${SERIAL_CLONES}; then
  PLAN_ARGS=(-input=false -parallelism=1 -out=tfplan)
fi

echo "==> terraform plan"
${TF} plan "${PLAN_ARGS[@]}"

if ! ${AUTO_APPROVE}; then
  read -r -p "Apply terraform plan? [y/N] " confirm
  [[ "${confirm,,}" == "y" ]] || { rm -f tfplan; echo "aborted"; exit 1; }
fi

echo "==> terraform apply"
if ${SERIAL_CLONES}; then
  ${TF} apply -parallelism=1 tfplan
else
  ${TF} apply tfplan
fi
rm -f tfplan

echo "==> generate ansible inventory"
generate_inventory

if [[ "$(hcl_bool "${TAILSCALE_ENABLED}")" == "true" ]] && [[ "$(hcl_bool "${TAILSCALE_APPLY_ACL:-true}")" == "true" ]]; then
  apply_tailscale_acl
fi

if ! ${INFRA_ONLY}; then
  if ${TALOS_MODE}; then
    run_ansible_talos_haproxy "${ANSIBLE_EXTRA[@]}"
    bootstrap_talos_cluster
  else
    run_ansible "${ANSIBLE_EXTRA[@]}"
    fetch_kubeconfig
  fi
  deploy_helm_workloads
  show_kubeconfig_summary
  show_gateway_summary
  show_tailscale_summary
  show_longhorn_summary
  show_datadog_summary
  show_prometheus_summary
  show_argocd_summary
  show_sealed_secrets_summary
  show_velero_summary
  show_kasten_summary
fi

echo "done."
