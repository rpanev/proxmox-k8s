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
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_destroy() {
    echo -e "${MAGENTA}[DESTROY]${NC} $1"
}

# Function to check if required files exist
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if we're in the project root directory
    if [[ ! -f "terraform/main.tf" ]]; then
        print_error "terraform/main.tf not found. Please run this script from the project root directory."
        exit 1
    fi
    
    # Check if terraform.tfvars exists
    if [[ ! -f "terraform/terraform.tfvars" ]]; then
        print_error "terraform/terraform.tfvars not found. No configuration to destroy."
        exit 1
    fi
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check if terraform state exists
    if [[ ! -f "terraform/terraform.tfstate" ]] && [[ ! -f "terraform/.terraform/terraform.tfstate" ]]; then
        print_warning "No Terraform state found. Nothing to destroy."
        echo "If you have resources that need manual cleanup, please check Proxmox directly."
        exit 0
    fi
    
    print_success "Prerequisites check passed!"
}

# Function to show what will be destroyed
show_destroy_summary() {
    print_status "Destroy Summary:"
    echo "===================="
    
    # Extract key values from terraform.tfvars
    if [[ -f "terraform/terraform.tfvars" ]]; then
        echo "Proxmox Node: $(grep '^target_node' terraform/terraform.tfvars | cut -d'=' -f2 | tr -d ' "' || echo 'Not specified')"
        echo "Template: $(grep '^template_name' terraform/terraform.tfvars | cut -d'=' -f2 | tr -d ' "' || echo 'Not specified')"
        echo "Network: $(grep '^ip_base' terraform/terraform.tfvars | cut -d'=' -f2 | tr -d ' "' || echo 'Not specified').0/$(grep '^network_cidr' terraform/terraform.tfvars | cut -d'=' -f2 | tr -d ' "' || echo '24')"
        echo "Master Count: $(grep '^master_count' terraform/terraform.tfvars | cut -d'=' -f2 | tr -d ' "' || echo '1')"
        echo "Worker Count: $(grep '^nodes_count' terraform/terraform.tfvars | cut -d'=' -f2 | tr -d ' "' || echo '3')"
    fi
    echo "===================="
    echo
    
    print_destroy "The following resources will be DESTROYED:"
    echo "• All K3s cluster VMs (master + worker nodes)"
    echo "• Proxmox pool 'k8s'"
    echo "• VM network configurations"
    echo "• VM storage and disks"
    echo "• All associated cloud-init configurations"
    echo
    print_warning "This action is IRREVERSIBLE!"
    echo
}

# Function to backup kubeconfig before destroy
backup_kubeconfig() {
    print_status "Backing up kubeconfig (if exists)..."
    
    if [[ -f "kubeconfig" ]]; then
        local backup_name="kubeconfig.backup.$(date +%Y%m%d_%H%M%S)"
        cp kubeconfig "$backup_name"
        print_success "Kubeconfig backed up as: $backup_name"
    else
        print_status "No kubeconfig found to backup."
    fi
}

# Main destroy function
destroy_cluster() {
    print_destroy "Starting K3s Proxmox cluster destruction..."
    echo
    
    # Change to terraform directory
    cd terraform || {
        print_error "Failed to change to terraform directory!"
        exit 1
    }
    
    # Step 1: Terraform Plan Destroy
    print_status "Step 1/2: Creating Terraform destroy plan..."
    if terraform plan -destroy -out=destroy.tfplan; then
        print_success "Terraform destroy plan created successfully!"
    else
        print_error "Terraform destroy plan failed!"
        cd ..
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
        cd ..
        exit 0
    fi
    
    # Step 2: Terraform Destroy
    print_destroy "Step 2/2: Destroying Terraform infrastructure..."
    echo "This may take 5-10 minutes depending on your environment..."
    echo
    
    if terraform apply destroy.tfplan; then
        print_success "Terraform destruction completed successfully!"
        rm -f destroy.tfplan
    else
        print_error "Terraform destruction failed!"
        print_warning "Some resources may still exist. Check Proxmox manually."
        rm -f destroy.tfplan
        cd ..
        exit 1
    fi
    
    # Return to project root
    cd ..
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
    echo "   rm -f kubeconfig kubeconfig.backup.*"
    echo "   rm -f terraform/terraform.tfstate*"
    echo "   rm -rf terraform/.terraform/"
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
    rm -f terraform/destroy.tfplan
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
    show_destroy_summary
    backup_kubeconfig
    destroy_cluster
    show_post_destroy
}

# Run main function
main "$@"
