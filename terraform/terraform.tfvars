# ===== Proxmox API Access =====
# Proxmox API URL
pm_api_url = "https://192.168.99.6:8006/api2/json"
# Username and password (if using a token, you may leave these empty and enable the token fields in the provider)
pm_user     = "root@pam"
pm_password = "yourpassword"
# Example token values (if you decide to use a token)
pm_api_token_id     = "root@pam!YourTokenId"
pm_api_token_secret = "token-secret-here"

# ===== Common settings (apply to master and nodes) =====
# Proxmox node where VMs will be created
target_node = "pve1"
# Name/ID of the Proxmox template to clone
template_name = "almalinux9-cloud"
# Enable QEMU agent in the guest OS
enable_agent = true
# SCSI controller and boot disk
scsihw   = "virtio-scsi-pci"
bootdisk = "scsi0"
# Cloud-Init drive and primary disk
cloudinit_storage = "local-lvm"
disk0_size_gb     = 32
# Cache mode and storage for the primary disk
disk0_cache   = "writeback"
disk0_storage = "local-lvm"
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
ssh_public_key = "ssh-ed25519 +++++ terraform@proxmox.dev"
# Path to private key for remote-exec (local to Terraform)
private_key_path = "~/.ssh/id_ed25519"
# Control flags for remote-exec provisioners
remote_exec_master_enabled = true
remote_exec_node_enabled   = true

# ===== Master VM =====
master_count   = 1
master_name    = "k8s-master"
master_cores   = 2
master_sockets = 1
master_memory  = 2048
# Last IP octet for master and fixed VMID
master_ip_host = 230
master_vmid    = 230
# Hostname to set via remote-exec
master_hostname = "k8s-master"
# Tags for master VM
master_tags = "k8s,master,terraform"

# ===== Worker Nodes =====
nodes_count      = 3
node_name_prefix = "k8s-node"

node_cores   = 2
node_sockets = 1
node_memory  = 2048
# Starting IP last octet and VMID for the first node
node_ip_start   = 231
node_vmid_start = 231
# Tags for worker nodes
node_tags = "k8s,worker,terraform"

# ===== SSH access for cloud-init =====
ssh_user     = "root"
ssh_password = "Password123"
