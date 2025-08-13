# K3s Test Application Helm Chart

A comprehensive Helm chart for testing K3s cluster functionality with Ingress, Deployment, Services, and automated tests.

## Overview

This chart deploys a test application that validates:
- **Deployment** - Multi-replica nginx pods
- **Service** - ClusterIP service with load balancing
- **Ingress** - Traefik ingress controller integration
- **ConfigMap** - Custom HTML content
- **ServiceAccount** - RBAC configuration
- **Tests** - Automated connectivity tests

## Quick Start

### Prerequisites

- K3s cluster running and accessible
- `kubectl` configured with cluster access
- `helm` installed (script will install if missing)

### Deploy the Test Application

```bash
# From the helm/ directory
./deploy-test-app.sh
```

The script will:
1. Check prerequisites and install Helm if needed
2. Verify cluster connectivity
3. Deploy the application with Helm
4. Run automated tests
5. Show access information

### Manual Deployment

```bash
# Install the chart
helm install k3s-test-app . --namespace k3s-test --create-namespace

# Upgrade the chart
helm upgrade k3s-test-app . --namespace k3s-test

# Uninstall the chart
helm uninstall k3s-test-app --namespace k3s-test
```

## Configuration

### Default Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `3` |
| `image.repository` | Container image | `nginx` |
| `image.tag` | Image tag | `alpine` |
| `service.type` | Service type | `ClusterIP` |
| `service.port` | Service port | `80` |
| `ingress.enabled` | Enable ingress | `true` |
| `ingress.className` | Ingress class | `traefik` |
| `ingress.hosts[0].host` | Ingress hostname | `k3s-test.local` |

### Custom Values

Create a `custom-values.yaml` file:

```yaml
replicaCount: 5

ingress:
  hosts:
    - host: my-k3s-test.example.com
      paths:
        - path: /
          pathType: Prefix

resources:
  limits:
    cpu: 200m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

Deploy with custom values:
```bash
helm install k3s-test-app . -f custom-values.yaml --namespace k3s-test --create-namespace
```

## Accessing the Application

### Method 1: Direct IP Access (Recommended)

**Via Ingress (Port 80):**
```bash
# Access directly via master node IP
http://<MASTER_NODE_IP>
```

**Via NodePort (Port 30080):**
```bash
# Deploy with IP-optimized configuration
helm upgrade k3s-test-app . -f values-ip-access.yaml -n k3s-test

# Access via NodePort
http://<MASTER_NODE_IP>:30080
```

### Method 2: Port Forward (Local testing)

```bash
kubectl port-forward -n k3s-test svc/k3s-test-app 8080:80
```
Then visit: http://localhost:8080

### Method 3: DNS Access (Optional)

Add to your `/etc/hosts`:
```
<MASTER_NODE_IP> k3s-test.local
```
Then visit: http://k3s-test.local

## Testing

### Run Helm Tests

```bash
helm test k3s-test-app -n k3s-test
```

### Manual Testing

```bash
# Check pods
kubectl get pods -n k3s-test

# Check service
kubectl get svc -n k3s-test

# Check ingress
kubectl get ingress -n k3s-test

# Test service connectivity
kubectl run test-pod --rm -i --tty --image=busybox -- wget -qO- k3s-test-app.k3s-test.svc.cluster.local
```

## Monitoring

### View Logs

```bash
# All pods
kubectl logs -n k3s-test -l app.kubernetes.io/name=k3s-test-app

# Specific pod
kubectl logs -n k3s-test <pod-name>

# Follow logs
kubectl logs -n k3s-test -l app.kubernetes.io/name=k3s-test-app -f
```

### Scale Application

```bash
# Scale up
kubectl scale deployment k3s-test-app -n k3s-test --replicas=5

# Scale down
kubectl scale deployment k3s-test-app -n k3s-test --replicas=1
```

## Troubleshooting

### Common Issues

1. **Pods not starting**
   ```bash
   kubectl describe pods -n k3s-test
   kubectl logs -n k3s-test <pod-name>
   ```

2. **Service not accessible**
   ```bash
   kubectl get endpoints -n k3s-test
   kubectl describe svc k3s-test-app -n k3s-test
   ```

3. **Ingress not working**
   ```bash
   kubectl describe ingress -n k3s-test
   kubectl get ingressclass
   ```

### Cleanup

#### Option 1: Using the Automated Destroy Script (Recommended)

```bash
# Run the automated destroy script
./destroy-test-app.sh
```

The script will:
- Check prerequisites and show what will be destroyed
- Uninstall the Helm release safely
- Clean up all remaining resources (pods, services, configmaps)
- Optionally remove the namespace
- Verify complete destruction
- Provide post-destroy information

#### Option 2: Manual Cleanup

```bash
# Remove the application
helm uninstall k3s-test-app -n k3s-test

# Remove the namespace
kubectl delete namespace k3s-test
```

## Chart Structure

```
helm/
├── Chart.yaml                 # Chart metadata
├── values.yaml               # Default configuration
├── templates/
│   ├── deployment.yaml       # Deployment manifest
│   ├── service.yaml          # Service manifest
│   ├── ingress.yaml          # Ingress manifest
│   ├── serviceaccount.yaml   # ServiceAccount manifest
│   ├── configmap.yaml        # ConfigMap manifest
│   ├── _helpers.tpl          # Template helpers
│   └── tests/
│       └── test-connection.yaml # Helm tests
├── deploy-test-app.sh        # Automated deployment script
└── README.md                 # This file
```

## What the Test Application Shows

The deployed application displays:
- **Cluster Status** - Confirms K3s is running
- **Pod Information** - Shows which pod served the request
- **Load Balancing** - Refresh to see different pods
- **Ingress Functionality** - Traefik routing works
- **Service Discovery** - Internal DNS resolution
- **ConfigMap Mounting** - Custom content delivery

This validates that your K3s cluster is fully functional and ready for production workloads!
