# Proxmox K3s HA Cluster with Terraform + Ansible

![K3s Homelab Architecture](img/homelab-k3s.png)

## Table of Contents

- [What is this?](#what-is-this)
- [Project Overview](#project-overview)
- [Key Components](#key-components)
- [Prerequisites](#prerequisites)
- [Core Configuration](#core-configuration)
- [Deployment Process](#deployment-process)
- [Future Improvements](#future-improvements)
- [Getting Started](#getting-started)
- [Contributing](#contributing)
- [Acknowledgments](#acknowledgments)

## What is this?

This project automates the deployment of a homelab-ready **High Availability K3s Kubernetes cluster** on Proxmox VE. I built this because I was tired of manually configuring VMs and installing K3s components one by one. Now I can spin up a complete HA K3s environment with a single command.

## Project Overview

This toolkit creates a fully functional K3s cluster with multiple master nodes for high availability, worker nodes for your workloads, and an NGINX load balancer to distribute traffic. Everything is defined as code using Terraform and Ansible, making the deployment reproducible and easy to customize.

### Architecture (ASCII)
```text
                          +----------------+
                          |    Nginx LB    |
                          | 192.168.99.220 |
                          +--------+-------+
                                   |
                    +--------------+--------------+
                    |              |              |
         +----------------+  +----------------+  +----------------+
         |   Master 1     |  |   Master 2     |  |   Master 3     |
         | 192.168.99.230 |  | 192.168.99.231 |  | 192.168.99.232 |
         +--------+-------+  +--------+-------+  +--------+-------+
                  |                   |                   |
                  |                   |                   |
                  v                   v                   v
         +----------------+  +----------------+  +----------------+
         |   Worker 1     |  |   Worker 2     |  |   Worker 3     |
         | 192.168.99.240 |  | 192.168.99.241 |  | 192.168.99.242 |
         +----------------+  +----------------+  +----------------+
```

### Important Notes

    ✅ Tested on: AlmaLinux 9 VMs with cloud-init templates
    ⚠️ WSL Limitation: File system issues with Ansible and private keys
    ❌ LXC Not Supported: Kubernetes swap memory configuration errors
    🔧 Requirements: Cloud-init template with SSH key injection


## Key Components

### Terraform
Handles the infrastructure provisioning - creates VMs on Proxmox, configures networking, and sets up storage. The VMs are organized in a pool for easier management.

### Ansible
Takes care of software provisioning - installs K3s on masters and workers, configures the NGINX load balancer, and ensures proper cluster formation with embedded etcd.

### NGINX Load Balancer
Provides a stable entry point to the K3s API server, distributing requests across all master nodes for high availability.

### Helm Charts
Includes a demo application to verify your cluster is working correctly, with tests for deployments, services, and ingress functionality.

## Prerequisites

Before starting, ensure you have:

### On Your Local Machine
- Terraform >= 1.0
- Ansible >= 2.9
- sshpass (for Ansible SSH connections)
- kubectl (for cluster management)
- git (for cloning the repository)

### On Proxmox VE
- Proxmox VE with API access
- Cloud-init template (AlmaLinux 9 recommended)
- Network configuration for VM communication
- Storage for VM disks and templates

### Step 1: SSH Key Setup

Before deploying the cluster, you need to generate SSH keys for secure access.

#### 1.1 Generate Terraform/Ansible Access Keys

These keys will be used by Terraform and Ansible to access and configure the VMs:

```bash
# Generate SSH key pair for external access
ssh-keygen -t ed25519 -C "terraform@proxmox.dev" -f ~/.ssh/id_ed25519

# Set correct permissions
chmod 600 ~/.ssh/id_ed25519
```

When prompted, press enter to leave the passphrase blank.

## Core Configuration

### Proxmox Access
```
pm_api_url = "https://192.168.99.10:8006/api2/json"
pm_api_token_id = "root@pam!terraform-token"
pm_api_token_secret = "your_proxmox_api_token_secret"
```

### Network Configuration
```
ip_base = "192.168.99"
network_cidr = 24
gateway = "192.168.99.1"
```

### VM Layout
- **Masters**: 3 VMs starting at 192.168.99.230 (k8s-master-1, k8s-master-2, k8s-master-3)
- **Workers**: 3 VMs starting at 192.168.99.240 (k8s-node1, k8s-node2, k8s-node3)
- **Load Balancer**: 1 VM at 192.168.99.220 (nginx-lb)

## Deployment Process

### deploy.sh

The main deployment script that orchestrates the entire process:

1. **Prerequisites Check**: Verifies that Terraform, Ansible, and SSH keys are properly set up
2. **Terraform Deployment**: Creates and configures all VMs on Proxmox
3. **Ansible Provisioning**: Installs and configures software on all nodes
4. **Cluster Formation**: Sets up K3s in HA mode with embedded etcd

To deploy the cluster:
```bash
./deploy.sh
```

### Terraform

The Terraform code creates:
- VM templates from cloud images
- Network configuration with proper IP addressing
- Storage allocation and configuration
- VM resources (CPU, memory, disk)

All settings are customizable through `terraform.tfvars`.

### Ansible

The Ansible playbooks handle:
- NGINX load balancer setup for API server access
- First master node initialization with embedded etcd
- Additional master nodes joining the cluster
- Worker nodes configuration and registration

### Helm Demo Application

A test application is included in the `helm/` directory to verify your cluster works correctly:

```bash
cd helm/
./deploy-test-app.sh
```

The demo app validates:
- Pod deployment and scaling
- Service networking
- Ingress controller functionality
- ConfigMap usage

### destroy.sh

When you're done with the cluster, the destroy script cleans everything up:

1. Backs up your kubeconfig
2. Destroys all Terraform-managed resources
3. Removes Ansible inventory
4. Provides cleanup recommendations

To destroy the cluster:
```bash
./destroy.sh
```

## Future Improvements

Planned enhancements:
- Add a second NGINX load balancer for redundancy
- Implement Keepalived for load balancer high availability
- Configure a virtual IP (192.168.99.220) for seamless failover

## Getting Started

1. Clone this repo
2. Configure `terraform/terraform.tfvars` with your Proxmox details
3. Generate SSH keys in `ansible/keys/`
4. Run `./deploy.sh`
5. Use the generated kubeconfig to interact with your new cluster

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Acknowledgments

- [K3s](https://k3s.io/) - Lightweight Kubernetes distribution
- [Proxmox VE](https://www.proxmox.com/en/proxmox-ve) - Virtualization platform
- [Terraform](https://www.terraform.io/) - Infrastructure as Code
- [Ansible](https://www.ansible.com/) - Configuration management

Enjoy your new homelab-ready K3s cluster!

```
[root@dev .kube ]$ kubectl get nodes -o wide
NAME           STATUS   ROLES                       AGE   VERSION        INTERNAL-IP      EXTERNAL-IP   OS-IMAGE                       KERNEL-VERSION                 CONTAINER-RUNTIME
k8s-master-1   Ready    control-plane,etcd,master   19m   v1.33.4+k3s1   192.168.99.230   <none>        AlmaLinux 10.0 (Purple Lion)   6.12.0-55.32.1.el10_0.x86_64   containerd://2.0.5-k3s2
k8s-master-2   Ready    control-plane,etcd,master   17m   v1.33.4+k3s1   192.168.99.231   <none>        AlmaLinux 10.0 (Purple Lion)   6.12.0-55.32.1.el10_0.x86_64   containerd://2.0.5-k3s2
k8s-master-3   Ready    control-plane,etcd,master   17m   v1.33.4+k3s1   192.168.99.232   <none>        AlmaLinux 10.0 (Purple Lion)   6.12.0-55.32.1.el10_0.x86_64   containerd://2.0.5-k3s2
k8s-node1      Ready    <none>                      16m   v1.33.4+k3s1   192.168.99.240   <none>        AlmaLinux 10.0 (Purple Lion)   6.12.0-55.32.1.el10_0.x86_64   containerd://2.0.5-k3s2
k8s-node2      Ready    <none>                      16m   v1.33.4+k3s1   192.168.99.241   <none>        AlmaLinux 10.0 (Purple Lion)   6.12.0-55.32.1.el10_0.x86_64   containerd://2.0.5-k3s2
k8s-node3      Ready    <none>                      16m   v1.33.4+k3s1   192.168.99.242   <none>        AlmaLinux 10.0 (Purple Lion)   6.12.0-55.32.1.el10_0.x86_64   containerd://2.0.5-k3s2
``` 