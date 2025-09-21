#!/bin/bash
# K3s Proxmox Cluster Deployment Script
# Automates Terraform deployment + Ansible provisioning

set -euo pipefail

# ===== Colors =====
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_status()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ===== Globals =====
PROJECT_ROOT=""
export START_TIME=$(date +%s)

# ===== Helpers =====
# read value from terraform.tfvars (simple "key = value" lines)
tfvar() { grep -E "^\s*$1\s*=" "${PROJECT_ROOT}/terraform/terraform.tfvars" | head -1 | cut -d'=' -f2- | tr -d ' "' || true; }

# ===== Prereqs =====
check_prerequisites() {
  print_status "Checking prerequisites..."

  # Figure out absolute PROJECT_ROOT
  if [[ -f "terraform/main.tf" ]]; then
    PROJECT_ROOT="$(pwd)"
  elif [[ -f "../terraform/main.tf" ]]; then
    PROJECT_ROOT="$(cd .. && pwd)"
    print_status "Running from subdirectory, project root: ${PROJECT_ROOT}"
  else
    local cur; cur="$(pwd)"; local max_depth=5 depth=0
    while [[ $depth -lt $max_depth ]]; do
      if [[ -f "$cur/terraform/main.tf" ]]; then PROJECT_ROOT="$cur"; print_status "Found project root: $PROJECT_ROOT"; break; fi
      local parent; parent="$(dirname "$cur")"; [[ "$parent" == "$cur" ]] && break
      cur="$parent"; ((depth++))
    done
    [[ -z "$PROJECT_ROOT" ]] && { print_error "terraform/main.tf not found. Run from the repo or a subdir."; exit 1; }
  fi

  # terraform.tfvars
  [[ -f "${PROJECT_ROOT}/terraform/terraform.tfvars" ]] || { print_error "Missing terraform/terraform.tfvars"; exit 1; }

  # SSH key
  [[ -f "${PROJECT_ROOT}/ansible/keys/k3s_cluster_key" ]] || {
    print_error "Missing SSH key: ${PROJECT_ROOT}/ansible/keys/k3s_cluster_key"
    echo "  mkdir -p ansible/keys/"
    echo "  ssh-keygen -t rsa -b 2048 -C 'k3s-cluster@proxmox' -f ansible/keys/k3s_cluster_key"
    exit 1
  }

  # Terraform
  command -v terraform >/dev/null || { print_error "Terraform not installed"; exit 1; }

  # Ansible
  command -v ansible-playbook >/dev/null || { print_error "Ansible not installed"; exit 1; }

  # Warn if no local state (remote backend still OK)
  if [[ ! -f "${PROJECT_ROOT}/terraform/terraform.tfstate" ]] && [[ ! -f "${PROJECT_ROOT}/terraform/.terraform/terraform.tfstate" ]]; then
    print_warning "No local terraform state – if using remote backend, this is fine."
  fi

  print_success "Prerequisites OK"
}

# ===== Version/Token =====
setup_k3s_version_and_token() {
  # Latest K3s tag (best-effort)
  local default_ver="v1.33.3+k3s1"
  if command -v curl >/dev/null && command -v jq >/dev/null; then
    local ver; ver=$(curl -s https://api.github.com/repos/k3s-io/k3s/releases/latest | jq -r '.tag_name' 2>/dev/null || echo "$default_ver")
    [[ -z "$ver" || "$ver" == "null" ]] && ver="$default_ver"
    export K3S_VERSION="${K3S_VERSION:-$ver}"
  else
    export K3S_VERSION="${K3S_VERSION:-$default_ver}"
    print_warning "curl/jq not found, using default K3s: $K3S_VERSION"
  fi

  # Token
  if command -v openssl >/dev/null; then
    export K3S_TOKEN="K3S-$(openssl rand -hex 8)-HA-TOKEN"
  else
    # fallback
    export K3S_TOKEN="K3S-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')-HA-TOKEN"
  fi
}

# ===== Summary =====
show_summary() {
  print_status "Deployment Summary:"
  echo "===================="
  local tf="${PROJECT_ROOT}/terraform/terraform.tfvars"
  [[ -f "$tf" ]] && {
    echo "Proxmox Node: $(tfvar target_node || echo 'Not specified')"
    echo "Template:    $(tfvar template_name || echo 'Not specified')"
    local ip_base="$(tfvar ip_base)"; local cidr="$(tfvar network_cidr)"; [[ -z "$cidr" ]] && cidr=24
    echo "Network:     ${ip_base}.0/${cidr}"
    echo "Master Count:$(tfvar master_count || echo '1')"
    echo "Worker Count:$(tfvar nodes_count  || echo '3')"
  }
  echo "K3s Version: ${K3S_VERSION}"
  echo "K3s HA Token: ${K3S_TOKEN}"
  echo "===================="
  echo
}

# ===== Terraform Deploy =====
deploy_cluster() {
  print_status "Starting K3s Proxmox cluster deployment..."
  echo

  pushd "${PROJECT_ROOT}/terraform" >/dev/null || { print_error "Cannot enter terraform dir"; exit 1; }

  print_status "Step 1/4: terraform init"
  terraform init || { print_error "terraform init failed"; popd >/dev/null; exit 1; }
  print_success "Init OK"; echo

  print_status "Step 2/4: terraform validate"
  terraform validate || { print_error "terraform validate failed"; popd >/dev/null; exit 1; }
  print_success "Validate OK"; echo

  print_status "Step 3/4: terraform fmt"
  terraform fmt -check -recursive || { print_error "terraform fmt failed"; popd >/dev/null; exit 1; }
  print_success "Fmt OK"; echo

  print_status "Step 4/4: terraform plan"
  terraform plan -out=tfplan || { print_error "terraform plan failed"; popd >/dev/null; exit 1; }
  print_success "Plan OK"; echo

  print_warning "Ready to create:"
  echo "  • Proxmox VMs, networking, storage"
  echo "  • K3s cluster bootstrap"
  echo "  • SSH keys and access"
  read -p "Continue? (yes/no): " -r
  if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    print_warning "Deployment cancelled by user."
    rm -f tfplan
    popd >/dev/null
    exit 0
  fi

  print_status "Step 4/4: terraform apply"
  terraform apply tfplan || { print_error "terraform apply failed"; rm -f tfplan; popd >/dev/null; exit 1; }
  rm -f tfplan
  print_success "Terraform apply OK"

  popd >/dev/null
}

# ===== Inventory generation =====
generate_ansible_inventory() {
  print_status "Generating Ansible inventory..."

  local MASTER_COUNT="$(tfvar master_count)"; [[ -z "$MASTER_COUNT" ]] && MASTER_COUNT=1
  local WORKER_COUNT="$(tfvar nodes_count)";  [[ -z "$WORKER_COUNT" ]] && WORKER_COUNT=3

  local IP_BASE="$(tfvar ip_base)";                 [[ -z "$IP_BASE" ]] && IP_BASE="192.168.99"
  local MASTER_IP_HOST="$(tfvar master_ip_host)";   [[ -z "$MASTER_IP_HOST" ]] && MASTER_IP_HOST=230
  local NODE_IP_START="$(tfvar node_ip_start)";     [[ -z "$NODE_IP_START" ]] && NODE_IP_START=240
  local LB_IP_HOST="$(tfvar nginx_lb_ip_host)";     [[ -z "$LB_IP_HOST" ]] && LB_IP_HOST=201

  local SSH_USER="$(tfvar ssh_user)";               [[ -z "$SSH_USER" ]] && SSH_USER="root"
  local PRIVATE_KEY_PATH="$(tfvar private_key_path)"; [[ -z "$PRIVATE_KEY_PATH" ]] && PRIVATE_KEY_PATH="~/.ssh/id_ed25519"
  PRIVATE_KEY_PATH=${PRIVATE_KEY_PATH/#\~/$HOME}

  local MASTER_NAME="$(tfvar master_name)";         [[ -z "$MASTER_NAME" ]] && MASTER_NAME="k8s-master"
  local NODE_NAME_PREFIX="$(tfvar node_name_prefix)"; [[ -z "$NODE_NAME_PREFIX" ]] && NODE_NAME_PREFIX="k8s-node"
  local LB_NAME="$(tfvar nginx_lb_name)";           [[ -z "$LB_NAME" ]] && LB_NAME="k8s-nginx-lb"

  mkdir -p "${PROJECT_ROOT}/ansible"
  local INVENTORY_FILE="${PROJECT_ROOT}/ansible/k8s-deploy"

  {
    echo "# Ansible inventory for K3s cluster"
    echo "# Generated on $(date)"
    echo
    echo "[nginx_lb]"
    echo "${LB_NAME} ansible_host=${IP_BASE}.${LB_IP_HOST} ansible_port=22 ansible_user=${SSH_USER} ansible_ssh_private_key_file=${PRIVATE_KEY_PATH} ansible_ssh_common_args='-o StrictHostKeyChecking=no'"
    echo
    echo "[master]"
    for ((i=1; i<=MASTER_COUNT; i++)); do
      local ip="${IP_BASE}.$((MASTER_IP_HOST + i - 1))"
      echo "${MASTER_NAME}-${i} ansible_host=${ip} ansible_port=22 ansible_user=${SSH_USER} ansible_ssh_private_key_file=${PRIVATE_KEY_PATH} ansible_ssh_common_args='-o StrictHostKeyChecking=no'"
    done
    echo
    echo "[first_master]"
    echo "${MASTER_NAME}-1 ansible_host=${IP_BASE}.${MASTER_IP_HOST} ansible_port=22 ansible_user=${SSH_USER} ansible_ssh_private_key_file=${PRIVATE_KEY_PATH} ansible_ssh_common_args='-o StrictHostKeyChecking=no'"
    echo
    if (( MASTER_COUNT > 1 )); then
      echo "[additional_masters]"
      for ((i=2; i<=MASTER_COUNT; i++)); do
        local ip="${IP_BASE}.$((MASTER_IP_HOST + i - 1))"
        echo "${MASTER_NAME}-${i} ansible_host=${ip} ansible_port=22 ansible_user=${SSH_USER} ansible_ssh_private_key_file=${PRIVATE_KEY_PATH} ansible_ssh_common_args='-o StrictHostKeyChecking=no'"
      done
      echo
    fi
    echo "[worker]"
    for ((i=1; i<=WORKER_COUNT; i++)); do
      local ip="${IP_BASE}.$((NODE_IP_START + i - 1))"
      echo "${NODE_NAME_PREFIX}${i} ansible_host=${ip} ansible_port=22 ansible_user=${SSH_USER} ansible_ssh_private_key_file=${PRIVATE_KEY_PATH} ansible_ssh_common_args='-o StrictHostKeyChecking=no'"
    done
    echo
    echo "[all:vars]"
    echo "ansible_python_interpreter=auto_silent"
    echo "master_private_ip=${IP_BASE}.${MASTER_IP_HOST}"
    echo "loadbalancer_ip=${IP_BASE}.${LB_IP_HOST}"
  } > "$INVENTORY_FILE"

  print_success "Inventory: ${INVENTORY_FILE}"
  cat "$INVENTORY_FILE"; echo
}

# ===== Ansible provisioning =====
run_ansible_playbooks() {
  print_status "Waiting 30s for VMs to boot..."
  for i in {30..1}; do echo -ne "\rWaiting $i s...   "; sleep 1; done
  echo -e "\rWait complete. Starting Ansible...\n"

  # Re-read values here (don't rely on other funcs)
  local MASTER_COUNT="$(tfvar master_count)"; [[ -z "$MASTER_COUNT" ]] && MASTER_COUNT=1
  local WORKER_COUNT="$(tfvar nodes_count)";  [[ -z "$WORKER_COUNT" ]] && WORKER_COUNT=3
  local IP_BASE="$(tfvar ip_base)";           [[ -z "$IP_BASE" ]] && IP_BASE="192.168.99"
  local MASTER_IP_HOST="$(tfvar master_ip_host)"; [[ -z "$MASTER_IP_HOST" ]] && MASTER_IP_HOST=230
  local LB_IP_HOST="$(tfvar nginx_lb_ip_host)"; [[ -z "$LB_IP_HOST" ]] && LB_IP_HOST=201

  # Define the loadbalancer IP that will be used in multiple places
  local LOADBALANCER_IP="${IP_BASE}.${LB_IP_HOST}"

  local SSH_USER="$(tfvar ssh_user)"; [[ -z "$SSH_USER" ]] && SSH_USER="root"
  local PRIVATE_KEY_PATH="$(tfvar private_key_path)"; [[ -z "$PRIVATE_KEY_PATH" ]] && PRIVATE_KEY_PATH="~/.ssh/id_ed25519"
  PRIVATE_KEY_PATH=${PRIVATE_KEY_PATH/#\~/$HOME}

  local INVENTORY_FILE="${PROJECT_ROOT}/ansible/k8s-deploy"
  [[ -f "$INVENTORY_FILE" ]] || { print_error "Inventory not found: $INVENTORY_FILE"; exit 1; }

  # Minimal Ansible noise
  export ANSIBLE_STDOUT_CALLBACK=minimal ANSIBLE_VERBOSITY=0 ANSIBLE_DISPLAY_SKIPPED_HOSTS=False \
         ANSIBLE_DISPLAY_OK_HOSTS=False ANSIBLE_SYSTEM_WARNINGS=False ANSIBLE_DEPRECATION_WARNINGS=False \
         ANSIBLE_COMMAND_WARNINGS=False PYTHONUNBUFFERED=1

  # Step 1: Nginx Load Balancer
  print_status "Step 1/4: Nginx Load Balancer..."
  if ansible-playbook -i "$INVENTORY_FILE" "${PROJECT_ROOT}/ansible/install-nginx-lb.yml" 2>/tmp/ansible_errors.log; then
    print_success "Nginx Load Balancer OK"
  else
    local rc=$?; print_error "Nginx Load Balancer failed (exit ${rc})"
    [[ -s /tmp/ansible_errors.log ]] && { print_status "Error log:"; cat /tmp/ansible_errors.log; }
    exit 1
  fi; echo

  # Step 2: first master
  print_status "Step 2/4: First master..."
  if ansible-playbook -i "$INVENTORY_FILE" "${PROJECT_ROOT}/ansible/install-first-master.yml" \
       --extra-vars "k3s_token=${K3S_TOKEN} loadbalancer_ip=${LOADBALANCER_IP}" 2>/tmp/ansible_errors.log; then
    print_success "First master OK"
  else
    local rc=$?; print_error "First master failed (exit ${rc})"
    [[ -s /tmp/ansible_errors.log ]] && { print_status "Error log:"; cat /tmp/ansible_errors.log; }
    exit 1
  fi; echo

  # Step 3: additional masters
  if (( MASTER_COUNT > 1 )); then
    print_status "Step 3/4: Additional masters..."
    local FIRST_MASTER_IP="${IP_BASE}.${MASTER_IP_HOST}"
    if ansible-playbook -i "$INVENTORY_FILE" "${PROJECT_ROOT}/ansible/install-additional-master.yml" \
         --extra-vars "first_master_ip=${FIRST_MASTER_IP} k3s_token=${K3S_TOKEN} loadbalancer_ip=${LOADBALANCER_IP}" 2>/tmp/ansible_errors.log; then
      print_success "Additional masters OK"
    else
      local rc=$?; print_error "Additional masters failed (exit ${rc})"
      [[ -s /tmp/ansible_errors.log ]] && { print_status "Error log:"; cat /tmp/ansible_errors.log; }
      exit 1
    fi
  else
    print_status "No additional masters."
  fi; echo

  # Step 4: workers
  if (( WORKER_COUNT > 0 )); then
    print_status "Step 4/4: Workers..."
    if ansible-playbook -i "$INVENTORY_FILE" "${PROJECT_ROOT}/ansible/install-workers.yml" \
         --extra-vars "loadbalancer_ip=${LOADBALANCER_IP} k3s_token=${K3S_TOKEN}" 2>/tmp/ansible_errors.log; then
      print_success "Workers OK"
    else
      local rc=$?; print_error "Workers failed (exit ${rc})"
      [[ -s /tmp/ansible_errors.log ]] && { print_status "Error log:"; cat /tmp/ansible_errors.log; }
      exit 1
    fi
  else
    print_status "No workers."
  fi; echo

  print_success "K3s provisioning completed"
}

# ===== Post-deploy info =====
show_post_deployment() {
  local END_TIME; END_TIME=$(date +%s)
  local DURATION=$((END_TIME - START_TIME))
  local MINUTES=$((DURATION / 60)); local SECONDS=$((DURATION % 60))

  echo
  print_success "K3s HA Cluster Deployment Complete! (Duration: ${MINUTES}m ${SECONDS}s)"
  echo
  print_status "Next steps:"
  echo "1) Outputs:"
  echo "   cd terraform && terraform output"
  echo
  echo "2) Kubeconfig:"
  echo "   cd terraform && \$(terraform output -raw kubeconfig_command)"
  echo "   kubectl --kubeconfig ./kubeconfig get nodes -o wide"
  echo
  echo "3) SSH shortcuts:"
  echo "   Masters: cd terraform && terraform output master_ssh_connections"
  echo "   Workers: cd terraform && terraform output worker_ssh_connections"
  echo
  echo "4) HA verification:"
  echo "   kubectl --kubeconfig ./kubeconfig get nodes --show-labels"
  echo "   # masters should have: control-plane,etcd,master"
  echo
  echo "5) Use the generated inventory for extras:"
  echo "   ansible-playbook -i ${PROJECT_ROOT}/ansible/k8s-deploy your-custom-playbook.yml"
  echo
}

# ===== Cleanup on interrupt =====
cleanup() {
  print_warning "Interrupted. Cleaning up..."
  [[ -n "${PROJECT_ROOT:-}" ]] && rm -f "${PROJECT_ROOT}/terraform/tfplan" || true
  exit 1
}
trap cleanup SIGINT SIGTERM

# ===== Help =====
show_help() {
  echo "Usage: $0 [--help|-h]"
  echo "Deploy K3s HA cluster on Proxmox (Terraform + Ansible)."
}

# ===== Main =====
main() {
  echo "================================================="
  echo "    K3s HA Proxmox Cluster Deployment Script"
  echo "================================================="
  echo

  if [[ $# -gt 0 ]]; then
    case "$1" in
      --help|-h) show_help; exit 0 ;;
      *) print_error "Unknown option: $1"; show_help; exit 1 ;;
    esac
  fi

  check_prerequisites
  setup_k3s_version_and_token
  show_summary
  deploy_cluster
  generate_ansible_inventory
  run_ansible_playbooks
  show_post_deployment
}

main "$@"
