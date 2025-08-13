#!/bin/bash

# K3s Test Application Deployment Script
# This script deploys the test application to validate K3s cluster functionality

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

print_deploy() {
    echo -e "${MAGENTA}[DEPLOY]${NC} $1"
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
        print_error "Helm is not installed. Installing Helm..."
        install_helm
    fi
    
    # Check if kubeconfig exists
    if [[ ! -f "../kubeconfig" ]] && [[ ! -f "$HOME/.kube/config" ]]; then
        print_error "No kubeconfig found. Please copy kubeconfig from master node first."
        echo "Run: cd terraform && \$(terraform output -raw kubeconfig_command)"
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

# Function to install Helm
install_helm() {
    print_status "Installing Helm..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
    print_success "Helm installed successfully!"
}

# Function to show deployment info
show_deployment_info() {
    print_status "K3s Test Application Deployment"
    echo "=================================="
    echo "Chart: k3s-test-app"
    echo "Namespace: k3s-test"
    echo "Replicas: 3"
    echo "Image: nginx:alpine"
    echo "Service: NodePort (30080)"
    echo "Access: Direct IP"
    echo "=================================="
    echo
}

# Function to deploy the application
deploy_application() {
    print_deploy "Deploying K3s test application..."
    
    # Create namespace if it doesn't exist
    kubectl create namespace k3s-test --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy with Helm
    print_status "Installing Helm chart..."
    if helm upgrade --install k3s-test-app . \
        --namespace k3s-test \
        --create-namespace \
        --wait \
        --timeout=300s; then
        print_success "Application deployed successfully!"
    else
        print_error "Deployment failed!"
        exit 1
    fi
    
    # Wait for pods to be ready
    print_status "Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=k3s-test-app -n k3s-test --timeout=300s
    
    print_success "All pods are ready!"
}

# Function to run tests
run_tests() {
    print_status "Running Helm tests..."
    
    if helm test k3s-test-app -n k3s-test; then
        print_success "All tests passed!"
    else
        print_warning "Some tests failed. Check the logs above."
    fi
}

# Function to show access information
show_access_info() {
    echo
    print_success "🎉 K3s Test Application Deployed Successfully!"
    echo
    print_status "Access Information:"
    echo "==================="
    
    # Get master node IP
    MASTER_IP=$(kubectl get nodes -o wide | grep master | awk '{print $6}' | head -1)
    if [[ -z "$MASTER_IP" ]]; then
        MASTER_IP="<MASTER_NODE_IP>"
    fi
    
    # Get service info
    echo "Service:"
    kubectl get svc -n k3s-test k3s-test-app
    echo
    
    # Get ingress info (only if enabled)
    if kubectl get ingress -n k3s-test k3s-test-app &>/dev/null; then
        echo "Ingress:"
        kubectl get ingress -n k3s-test k3s-test-app
        echo
    else
        echo "Ingress: Disabled (using NodePort for direct IP access)"
        echo
    fi
    
    # Get pods info
    echo "Pods:"
    kubectl get pods -n k3s-test -l app.kubernetes.io/name=k3s-test-app
    echo
    
    print_status "Access Methods:"
    echo "1. Via NodePort (Direct IP Access):"
    echo "   http://$MASTER_IP:30080"
    echo
    echo "2. Via Port Forward (Local testing):"
    echo "   kubectl port-forward -n k3s-test svc/k3s-test-app 8080:80"
    echo "   Then visit: http://localhost:8080"
    echo
    echo "3. Via Ingress (if enabled):"
    echo "   helm upgrade k3s-test-app . --set ingress.enabled=true -n k3s-test"
    echo "   http://k3s-test.local (requires DNS setup)"
    echo
    
    print_status "Useful Commands:"
    echo "• View logs: kubectl logs -n k3s-test -l app.kubernetes.io/name=k3s-test-app"
    echo "• Scale app: kubectl scale deployment k3s-test-app -n k3s-test --replicas=5"
    echo "• Delete app: helm uninstall k3s-test-app -n k3s-test"
    echo "• Run tests: helm test k3s-test-app -n k3s-test"
    echo
    
    print_status "For IP-optimized deployment, use:"
    echo "helm upgrade k3s-test-app . -f values-ip-access.yaml -n k3s-test"
}

# Main function
main() {
    echo "=================================================="
    echo "    K3s Test Application Deployment"
    echo "=================================================="
    echo
    
    check_prerequisites
    show_deployment_info
    deploy_application
    run_tests
    show_access_info
}

# Run main function
main "$@"
