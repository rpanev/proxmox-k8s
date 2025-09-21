# K3s HA Cluster Ansible Configuration

This directory contains Ansible playbooks for configuring a High Availability K3s Kubernetes cluster on Proxmox VMs.

## Installed Ansible Collections

The following Ansible collections are required for these playbooks:

```bash
# Install Ansible Core
sudo dnf install -y ansible-core

# Install required collections
ansible-galaxy collection install ansible.posix
ansible-galaxy collection install ansible.builtin
```

## Playbooks

- `install-first-master.yml` - Configures the first master node with cluster-init
- `install-additional-master.yml` - Adds additional master nodes to the HA cluster
- `install-workers.yml` - Configures worker nodes to join the cluster

## Directory Structure

- `keys/` - Contains SSH keys for cluster communication
- `templates/` - Jinja2 templates for configuration files

## Usage

The playbooks are automatically executed by the `deploy.sh` script in the parent directory. The script:

1. Generates an inventory file based on Terraform outputs
2. Runs the playbooks in the correct order
3. Configures SSH keys and access between nodes

## Configuration

The main configuration is defined in `terraform.tfvars` in the parent directory's terraform folder. Key settings include:

- Master count: 3
- Worker count: 3
- Network configuration: 192.168.99.0/24
- Master IPs: Starting at 192.168.99.230
- Worker IPs: Starting at 192.168.99.240
