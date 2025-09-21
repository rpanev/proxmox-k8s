# ===== Proxmox API Access =====
# Proxmox API URL
pm_api_url = "https://192.168.99.10:8006/api2/json"
# Username and password (if using a token, you may leave these empty and enable the token fields in the provider)
# pm_user     = "root@pam"
# pm_password = "Password123"
# Example token values (if you decide to use a token)
pm_api_token_id     = "root@pam!terraform-token"
pm_api_token_secret = "your_api_key"

# ===== Common settings (apply to master and nodes) =====
# Proxmox node where VMs will be created
target_node = "pve02"
# Name/ID of the Proxmox template to clone
template_name = "almalinux10-cloud"
# Enable QEMU agent in the guest OS
enable_agent = true
# SCSI controller and boot disk
scsihw   = "virtio-scsi-pci"
bootdisk = "scsi0"
# Cloud-Init drive and primary disk
cloudinit_storage = "M2.Storage"
disk0_size_gb     = 30
# Cache mode and storage for the primary disk
disk0_cache   = "writeback"
disk0_storage = "M2.Storage"
# Disk replication (if available in the cluster)
disk0_replicate = true
# Network settings (NIC model and bridge)
net_model  = "virtio"
net_bridge = "vmbr0"
# Boot device order
boot_order = "order=scsi0"
# Network addressing
ip_base      = "192.168.99"
network_cidr = 24
gateway      = "192.168.99.1"
# OS type for cloud-init
os_type = "cloud-init"
# Serial device (for console)
serial_id   = 0
serial_type = "socket"
# SSH public key for access
ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1 dev@panev.cloud"
# Path to private key for remote-exec (local to Terraform)
private_key_path = "~/.ssh/id_ed25519"

# ===== Master VM =====
master_count   = 3
master_name    = "k8s-master"
master_cores   = 2
master_sockets = 2
master_memory  = 4096
# Last IP octet for master and fixed VMID
master_ip_host = 230
master_vmid    = 230
# Tags for master VM
master_tags = "k8s,master,terraform"

# ===== Worker Nodes =====
nodes_count      = 3
node_name_prefix = "k8s-node"

node_cores   = 2
node_sockets = 2
node_memory  = 4096
# Starting IP last octet and VMID for the first node
node_ip_start   = 240
node_vmid_start = 240
# Tags for worker nodes
node_tags = "k8s,worker,terraform"

# ===== Load Balancer =====
nginx_lb_name    = "k8s-nginx-lb"
nginx_lb_cores   = 1
nginx_lb_sockets = 1
nginx_lb_memory  = 1024
nginx_lb_ip_host = 220
nginx_lb_vmid    = 220
nginx_lb_tags    = "k8s,loadbalancer,nginx,terraform"

# ===== SSH access for cloud-init =====
ssh_user     = "root"
ssh_password = "Password123"
