#!/bin/bash

# K3s Proxmox Cluster Destroy Script
# This script safely destroys the entire K3s cluster infrastructure
set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Function to print colored output
print_status()   { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success()  { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning()  { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()    { echo -e "${RED}[ERROR]${NC} $1"; }
print_destroy()  { echo -e "${MAGENTA}[DESTROY]${NC} $1"; }

# Global project root (absolute)
PROJECT_ROOT=""

# Function to check if required files exist
check_prerequisites() {
    print_status "Checking prerequisites..."

    # Determine PROJECT_ROOT (absolute)
    if [[ -f "terraform/main.tf" ]]; then
        PROJECT_ROOT="$(pwd)"
    elif [[ -f "../terraform/main.tf" ]]; then
        PROJECT_ROOT="$(cd .. && pwd)"
        print_status "Running from subdirectory, using parent directory as project root: ${PROJECT_ROOT}"
    else
        # Search upwards for terraform/main.tf (up to 5 levels)
        local current_dir
        current_dir="$(pwd)"
        local max_depth=5 depth=0
        while [[ $depth -lt $max_depth ]]; do
            if [[ -f "$current_dir/terraform/main.tf" ]]; then
                PROJECT_ROOT="$current_dir"
                print_status "Found project root at: $PROJECT_ROOT"
                break
            fi
            local parent_dir
            parent_dir="$(dirname "$current_dir")"
            [[ "$parent_dir" == "$current_dir" ]] && break
            current_dir="$parent_dir"
            ((depth++))
        done

        if [[ -z "$PROJECT_ROOT" ]]; then
            print_error "terraform/main.tf not found. Run this script from the project root or a subdirectory."
            exit 1
        fi
    fi

    # Check if terraform.tfvars exists
    if [[ ! -f "${PROJECT_ROOT}/terraform/terraform.tfvars" ]]; then
        print_error "terraform/terraform.tfvars not found. No configuration to destroy."
        exit 1
    fi

    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install it first."
        exit 1
    fi

    # Warn (but do NOT exit) if no local state (supports remote backends)
    if [[ ! -f "${PROJECT_ROOT}/terraform/terraform.tfstate" ]] && [[ ! -f "${PROJECT_ROOT}/terraform/.terraform/terraform.tfstate" ]]; then
        print_warning "No local Terraform state found. If you use a remote backend, destroy will still proceed."
    fi

    print_success "Prerequisites check passed!"
}

# Function to show what will be destroyed
show_destroy_summary() {
    print_status "Destroy Summary:"
    echo "===================="

    local tfvars="${PROJECT_ROOT}/terraform/terraform.tfvars"
    if [[ -f "$tfvars" ]]; then
        echo "Proxmox Node: $(grep -E '^\s*target_node' "$tfvars" | cut -d'=' -f2 | tr -d ' "' || echo 'Not specified')"
        echo "Template:    $(grep -E '^\s*template_name' "$tfvars" | cut -d'=' -f2 | tr -d ' "' || echo 'Not specified')"
        local ip_base="$(grep -E '^\s*ip_base' "$tfvars" | cut -d'=' -f2 | tr -d ' "')";
        local cidr="$(grep -E '^\s*network_cidr' "$tfvars" | cut -d'=' -f2 | tr -d ' "')";
        [[ -z "$cidr" ]] && cidr="24"
        echo "Network:     ${ip_base}.0/${cidr}"
        echo "Master Count:$(grep -E '^\s*master_count' "$tfvars" | cut -d'=' -f2 | tr -d ' "' || echo '1')"
        echo "Worker Count:$(grep -E '^\s*nodes_count'  "$tfvars" | cut -d'=' -f2 | tr -d ' "' || echo '3')"
    fi
    echo "===================="
    echo

    print_destroy "The following resources will be DESTROYED:"
    echo "• All K3s HA cluster VMs (masters + workers)"
    echo "• Proxmox pool 'k8s'"
    echo "• VM network configurations"
    echo "• VM storage and disks"
    echo "• All associated cloud-init configurations"
    echo "• HA embedded etcd cluster data"
    echo
    print_warning "This action is IRREVERSIBLE!"
    echo
}

# Function to backup kubeconfig before destroy
backup_kubeconfig() {
    print_status "Backing up kubeconfig (if exists)..."
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"

    local kcfg1="${PROJECT_ROOT}/kubeconfig"
    local kcfg2="${PROJECT_ROOT}/terraform/kubeconfig"

    local found=0
    if [[ -f "$kcfg1" ]]; then
        cp -f "$kcfg1" "${kcfg1}.backup.${ts}"
        print_success "Backed up: ${kcfg1} -> ${kcfg1}.backup.${ts}"
        found=1
    fi
    if [[ -f "$kcfg2" ]]; then
        cp -f "$kcfg2" "${kcfg2}.backup.${ts}"
        print_success "Backed up: ${kcfg2} -> ${kcfg2}.backup.${ts}"
        found=1
    fi
    [[ $found -eq 0 ]] && print_status "No kubeconfig found to backup."
}

# Main destroy function
destroy_cluster() {
    print_destroy "Starting K3s Proxmox cluster destruction..."
    echo

    # Enter terraform dir safely and restore later
    pushd "${PROJECT_ROOT}/terraform" >/dev/null || { print_error "Failed to enter terraform directory!"; exit 1; }

    # Step 1: Terraform Plan Destroy
    print_status "Step 1/2: Creating Terraform destroy plan..."
    if terraform plan -destroy -out=destroy.tfplan; then
        print_success "Terraform destroy plan created successfully!"
    else
        print_error "Terraform destroy plan failed!"
        rm -f destroy.tfplan || true
        popd >/dev/null
        exit 1
    fi
    echo

    # Final confirmation
    print_warning "!!! FINAL CONFIRMATION !!!"
    echo "You are about to PERMANENTLY DESTROY the entire K3s cluster!"
    echo "This includes:"
    echo "  • All VMs and their data"
    echo "  • All Kubernetes workloads and persistent volumes"
    echo "  • All cluster configurations"
    echo "  • Proxmox pool and VM tags"
    echo
    print_error "THIS CANNOT BE UNDONE!"
    echo
    read -p "Type 'DESTROY' (in capitals) to confirm: " -r
    if [[ $REPLY != "DESTROY" ]]; then
        print_warning "Destruction cancelled by user."
        rm -f destroy.tfplan
        popd >/dev/null
        exit 0
    fi

    # Step 2: Terraform Destroy
    print_destroy "Step 2/2: Destroying Terraform infrastructure..."
    echo "This may take several minutes depending on your environment..."
    echo

    if terraform apply destroy.tfplan; then
        print_success "Terraform destruction completed successfully!"
        rm -f destroy.tfplan
    else
        print_error "Terraform destruction failed!"
        print_warning "Some resources may still exist. Check Proxmox manually."
        rm -f destroy.tfplan
        popd >/dev/null
        exit 1
    fi

    # Restore original directory
    popd >/dev/null
}

# Function to remove Ansible inventory file
remove_ansible_inventory() {
    print_status "Removing Ansible inventory file..."

    local INVENTORY_FILE="${PROJECT_ROOT}/ansible/k8s-deploy"
    print_status "Looking for inventory file at: ${INVENTORY_FILE}"

    if [[ -f "${INVENTORY_FILE}" ]]; then
        rm -f "${INVENTORY_FILE}"
        print_success "Ansible inventory file removed."
    else
        print_warning "No Ansible inventory file found to remove."

        local ans_dir="${PROJECT_ROOT}/ansible"
        if [[ -d "${ans_dir}" ]]; then
            print_status "Contents of ${ans_dir}:"
            ls -la "${ans_dir}"
        else
            print_warning "Ansible directory not found at ${ans_dir}"
        fi
    fi
}

# Function to show post-destroy cleanup
show_post_destroy() {
    echo
    print_success "K3s Cluster Destruction Complete!"
    echo
    print_status "Post-destroy cleanup recommendations:"
    echo "1. Verify in Proxmox that all VMs are removed:"
    echo "   • Check VMs list in Proxmox web interface"
    echo "   • Verify pool 'k8s' is removed"
    echo
    echo "2. Clean up local files (optional):"
    echo "   rm -f ${PROJECT_ROOT}/kubeconfig ${PROJECT_ROOT}/kubeconfig.backup.*"
    echo "   rm -f ${PROJECT_ROOT}/terraform/kubeconfig ${PROJECT_ROOT}/terraform/kubeconfig.backup.*"
    echo "   rm -f ${PROJECT_ROOT}/terraform/terraform.tfstate*"
    echo "   rm -rf ${PROJECT_ROOT}/terraform/.terraform/"
    echo
    echo "3. If you plan to redeploy:"
    echo "   • Keep terraform.tfvars with your configuration"
    echo "   • Keep SSH keys in ansible/keys/"
    echo "   • Run ./deploy.sh when ready"
    echo
    print_status "Destruction completed successfully!"
}

# Function to handle cleanup on script interruption
cleanup() {
    print_warning "Script interrupted. Cleaning up..."
    if [[ -n "${PROJECT_ROOT:-}" ]]; then
        rm -f "${PROJECT_ROOT}/terraform/destroy.tfplan" || true
    fi
    exit 1
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Main script execution
main() {
    echo "=================================================="
    echo "    K3s Proxmox Cluster Destroy Script"
    echo "=================================================="
    echo

    check_prerequisites

    print_status "Project root directory: ${PROJECT_ROOT}"
    if [[ -d "${PROJECT_ROOT}/ansible" ]]; then
        print_status "Ansible directory exists"
    else
        print_warning "Ansible directory not found at ${PROJECT_ROOT}/ansible"
    fi

    show_destroy_summary
    backup_kubeconfig
    destroy_cluster
    remove_ansible_inventory
    show_post_destroy
}

# Run main function
main "$@"

