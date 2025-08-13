#!/bin/bash

# K3s Proxmox Cluster Deployment Script
# This script automates the Terraform deployment process

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
        print_error "terraform/terraform.tfvars not found. Please create and configure it first."
        exit 1
    fi
    
    # Check if SSH keys exist
    if [[ ! -f "ansible/keys/k3s_cluster_key" ]]; then
        print_error "K3s cluster SSH keys not found. Please generate them first:"
        echo "  mkdir -p ansible/keys/"
        echo "  ssh-keygen -t rsa -b 2048 -C 'k3s-cluster@proxmox' -f ansible/keys/k3s_cluster_key"
        exit 1
    fi
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Ansible is installed
    if ! command -v ansible-playbook &> /dev/null; then
        print_error "Ansible is not installed. Please install it first."
        exit 1
    fi
    
    print_success "Prerequisites check passed!"
}

# Function to show deployment summary
show_summary() {
    print_status "Deployment Summary:"
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
}

# Main deployment function
deploy_cluster() {
    print_status "Starting K3s Proxmox cluster deployment..."
    echo
    
    # Change to terraform directory
    cd terraform || {
        print_error "Failed to change to terraform directory!"
        exit 1
    }
    
    # Step 1: Terraform Init
    print_status "Step 1/4: Initializing Terraform..."
    if terraform init; then
        print_success "Terraform initialization completed!"
    else
        print_error "Terraform initialization failed!"
        cd ..
        exit 1
    fi
    echo
    
    # Step 2: Terraform Validate
    print_status "Step 2/4: Validating Terraform configuration..."
    if terraform validate; then
        print_success "Terraform validation passed!"
    else
        print_error "Terraform validation failed!"
        cd ..
        exit 1
    fi
    echo
    
    # Step 3: Terraform Plan
    print_status "Step 3/4: Creating Terraform execution plan..."
    if terraform plan -out=tfplan; then
        print_success "Terraform plan created successfully!"
    else
        print_error "Terraform plan failed!"
        cd ..
        exit 1
    fi
    echo
    
    # Ask for confirmation before apply
    print_warning "Ready to deploy the K3s cluster. This will:"
    echo "  • Create VMs on Proxmox"
    echo "  • Configure networking and storage"
    echo "  • Install and configure K3s cluster"
    echo "  • Set up SSH keys and access"
    echo
    read -p "Do you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_warning "Deployment cancelled by user."
        rm -f tfplan
        cd ..
        exit 0
    fi
    
    # Step 4: Terraform Apply
    print_status "Step 4/4: Applying Terraform configuration..."
    echo "This may take 10-15 minutes depending on your environment..."
    echo
    
    if terraform apply tfplan; then
        print_success "Terraform deployment completed successfully!"
        rm -f tfplan
    else
        print_error "Terraform deployment failed!"
        rm -f tfplan
        cd ..
        exit 1
    fi
    
    # Return to project root
    cd ..
}

# Function to show post-deployment instructions
show_post_deployment() {
    echo
    print_success "K3s Cluster Deployment Complete!"
    echo
    print_status "Next steps:"
    echo "1. Get cluster access information:"
    echo "   cd terraform && terraform output"
    echo
    echo "2. Copy kubeconfig from master:"
    echo "   cd terraform && \$(terraform output -raw kubeconfig_command)"
    echo
    echo "3. Test cluster connectivity:"
    echo "   kubectl --kubeconfig ./kubeconfig get nodes"
    echo
    echo "4. SSH access to nodes:"
    echo "   Master:  cd terraform && \$(terraform output -raw master_ssh_connection)"
    echo "   Workers: cd terraform && terraform output worker_ssh_connections"
    echo
    print_status "For troubleshooting, check the README.md file."
}

# Function to handle cleanup on script interruption
cleanup() {
    print_warning "Script interrupted. Cleaning up..."
    rm -f terraform/tfplan
    exit 1
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Main script execution
main() {
    echo "=================================================="
    echo "    K3s Proxmox Cluster Deployment Script"
    echo "=================================================="
    echo
    
    check_prerequisites
    show_summary
    deploy_cluster
    show_post_deployment
}

# Run main function
main "$@"
