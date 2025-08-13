#!/bin/bash

# K3s Test Application Destroy Script
# This script safely removes the test application and all associated resources

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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH."
        exit 1
    fi
    
    # Check if helm is available
    if ! command -v helm &> /dev/null; then
        print_error "Helm is not installed."
        exit 1
    fi
    
    # Test cluster connectivity
    print_status "Testing cluster connectivity..."
    if kubectl get nodes &> /dev/null; then
        print_success "Cluster connectivity verified!"
    else
        print_error "Cannot connect to K3s cluster. Check kubeconfig and cluster status."
        exit 1
    fi
    
    print_success "Prerequisites check passed!"
}

# Function to show what will be destroyed
show_destroy_summary() {
    print_status "Destroy Summary:"
    echo "===================="
    
    # Check if Helm release exists
    if helm list -n k3s-test | grep -q k3s-test-app; then
        echo "Helm Release: k3s-test-app (FOUND)"
        helm list -n k3s-test
        echo
    else
        echo "Helm Release: k3s-test-app (NOT FOUND)"
        echo
    fi
    
    # Check if namespace exists and has resources
    if kubectl get namespace k3s-test &>/dev/null; then
        echo "Namespace: k3s-test (EXISTS)"
        echo "Resources in namespace:"
        kubectl get all -n k3s-test 2>/dev/null || echo "  No resources found"
        echo
    else
        echo "Namespace: k3s-test (NOT FOUND)"
        echo
    fi
    
    # Check for any test pods or jobs
    if kubectl get pods -A | grep -q k3s-test; then
        echo "Test pods found:"
        kubectl get pods -A | grep k3s-test
        echo
    fi
    
    echo "===================="
    echo
    
    print_destroy "The following will be DESTROYED:"
    echo "• Helm release 'k3s-test-app'"
    echo "• All pods, services, deployments in k3s-test namespace"
    echo "• ConfigMaps and ServiceAccounts"
    echo "• Test pods and jobs"
    echo "• Namespace 'k3s-test' (optional)"
    echo
}

# Function to destroy the application
destroy_application() {
    print_destroy "Starting K3s test application destruction..."
    echo
    
    # Step 1: Uninstall Helm release
    print_status "Step 1/3: Uninstalling Helm release..."
    if helm list -n k3s-test | grep -q k3s-test-app; then
        if helm uninstall k3s-test-app -n k3s-test; then
            print_success "Helm release uninstalled successfully!"
        else
            print_error "Failed to uninstall Helm release!"
            exit 1
        fi
    else
        print_warning "Helm release 'k3s-test-app' not found, skipping..."
    fi
    echo
    
    # Step 2: Clean up any remaining resources
    print_status "Step 2/3: Cleaning up remaining resources..."
    
    # Delete any test pods that might be left
    if kubectl get pods -n k3s-test 2>/dev/null | grep -q test; then
        print_status "Removing test pods..."
        kubectl delete pods -n k3s-test -l "helm.sh/hook=test" --ignore-not-found=true
    fi
    
    # Delete any remaining resources with our labels
    kubectl delete all -n k3s-test -l app.kubernetes.io/name=k3s-test-app --ignore-not-found=true
    kubectl delete configmaps -n k3s-test -l app.kubernetes.io/name=k3s-test-app --ignore-not-found=true
    kubectl delete serviceaccounts -n k3s-test -l app.kubernetes.io/name=k3s-test-app --ignore-not-found=true
    
    print_success "Resource cleanup completed!"
    echo
    
    # Step 3: Handle namespace
    print_status "Step 3/3: Handling namespace..."
    if kubectl get namespace k3s-test &>/dev/null; then
        # Check if namespace has any remaining resources
        REMAINING_RESOURCES=$(kubectl get all -n k3s-test --no-headers 2>/dev/null | wc -l)
        
        if [ "$REMAINING_RESOURCES" -eq 0 ]; then
            print_warning "Namespace 'k3s-test' is empty."
            read -p "Do you want to delete the namespace? (y/n): " -r
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                kubectl delete namespace k3s-test
                print_success "Namespace 'k3s-test' deleted!"
            else
                print_status "Namespace 'k3s-test' kept as requested."
            fi
        else
            print_warning "Namespace 'k3s-test' contains other resources:"
            kubectl get all -n k3s-test
            print_status "Namespace kept to preserve other resources."
        fi
    else
        print_status "Namespace 'k3s-test' not found, nothing to clean up."
    fi
    echo
}

# Function to verify destruction
verify_destruction() {
    print_status "Verifying destruction..."
    
    # Check Helm releases
    if helm list -n k3s-test | grep -q k3s-test-app; then
        print_error "Helm release still exists!"
        return 1
    fi
    
    # Check for remaining pods
    if kubectl get pods -n k3s-test -l app.kubernetes.io/name=k3s-test-app 2>/dev/null | grep -q k3s-test-app; then
        print_error "Some pods still exist!"
        return 1
    fi
    
    # Check for services
    if kubectl get svc -n k3s-test -l app.kubernetes.io/name=k3s-test-app 2>/dev/null | grep -q k3s-test-app; then
        print_error "Some services still exist!"
        return 1
    fi
    
    print_success "Destruction verified - all resources removed!"
    return 0
}

# Function to show post-destroy information
show_post_destroy() {
    echo
    print_success "K3s Test Application Destruction Complete!"
    echo
    print_status "What was removed:"
    echo "Helm release 'k3s-test-app'"
    echo "All pods, services, and deployments"
    echo "ConfigMaps and ServiceAccounts"
    echo "Test pods and jobs"
    echo
    
    print_status "Cluster status:"
    echo "• K3s cluster: Still running"
    echo "• Other applications: Unaffected"
    echo "• NodePort 30080: Now available for other uses"
    echo
    
    print_status "To redeploy the test application:"
    echo "./deploy-test-app.sh"
    echo
    
    print_status "To check cluster status:"
    echo "kubectl get nodes"
    echo "kubectl get pods -A"
}

# Function to handle cleanup on script interruption
cleanup() {
    print_warning "Script interrupted. Some resources may still exist."
    print_status "Run the script again to complete cleanup."
    exit 1
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Main script execution
main() {
    echo "=================================================="
    echo "    K3s Test Application Destroy Script"
    echo "=================================================="
    echo
    
    check_prerequisites
    show_destroy_summary
    
    # Confirmation
    print_warning "Are you sure you want to destroy the K3s test application?"
    read -p "Type 'yes' to confirm: " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_warning "Destruction cancelled by user."
        exit 0
    fi
    
    destroy_application
    
    if verify_destruction; then
        show_post_destroy
    else
        print_error "Some resources may not have been completely removed."
        print_status "Check manually with: kubectl get all -n k3s-test"
        exit 1
    fi
}

# Run main function
main "$@"
