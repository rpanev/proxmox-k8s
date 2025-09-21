# ===== Proxmox API credentials =====
variable "pm_api_url" {
  type        = string
  description = "Proxmox API URL"
}

# variable "pm_user" {
#   type        = string
#   description = "Proxmox username"
#   default     = "root@pam"
# }

# variable "pm_password" {
#   type        = string
#   description = "Proxmox password"
#   sensitive   = true
# }

variable "pm_api_token_id" {
  type        = string
  description = "Proxmox API token ID (alternative to user/password)"
  default     = ""
}

variable "pm_api_token_secret" {
  type        = string
  description = "Proxmox API token secret (alternative to user/password)"
  default     = ""
  sensitive   = true
}

# ===== Common VM settings =====
variable "target_node" {
  type        = string
  description = "Proxmox node to create VMs on"
}

variable "template_name" {
  type        = string
  description = "Name of the Proxmox template to clone"
}

variable "enable_agent" {
  type        = bool
  description = "Enable QEMU agent"
  default     = true
}

variable "scsihw" {
  type        = string
  description = "SCSI hardware type"
  default     = "virtio-scsi-pci"
}

variable "bootdisk" {
  type        = string
  description = "Boot disk device"
  default     = "scsi0"
}

variable "cloudinit_storage" {
  type        = string
  description = "Storage for cloud-init drive"
  default     = "local-lvm"
}

variable "disk0_size_gb" {
  type        = number
  description = "Size of primary disk in GB"
  default     = 32
}

variable "disk0_cache" {
  type        = string
  description = "Cache mode for primary disk"
  default     = "writeback"
}

variable "disk0_storage" {
  type        = string
  description = "Storage for primary disk"
  default     = "local-lvm"
}

variable "disk0_replicate" {
  type        = bool
  description = "Enable replication for primary disk"
  default     = true
}

variable "net_model" {
  type        = string
  description = "Network interface model"
  default     = "virtio"
}

variable "net_bridge" {
  type        = string
  description = "Network bridge"
  default     = "vmbr0"
}

variable "boot_order" {
  type        = string
  description = "Boot device order"
  default     = "order=scsi0"
}

variable "ip_base" {
  type        = string
  description = "Base IP address (first 3 octets)"
  default     = "192.168.1"
}

variable "network_cidr" {
  type        = number
  description = "Network CIDR suffix"
  default     = 24
}

variable "gateway" {
  type        = string
  description = "Network gateway"
  default     = "192.168.1.1"
}

variable "os_type" {
  type        = string
  description = "OS type for cloud-init"
  default     = "cloud-init"
}

variable "serial_id" {
  type        = number
  description = "Serial device ID"
  default     = 0
}

variable "serial_type" {
  type        = string
  description = "Serial device type"
  default     = "socket"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for VM access"
}

variable "private_key_path" {
  type        = string
  description = "Path to private key for remote-exec and Ansible"
}

# ===== Master VM settings =====
variable "master_count" {
  type        = number
  description = "Number of master VMs to create"
  default     = 1
}

variable "master_name" {
  type        = string
  description = "Master VM name"
  default     = "k8s-master"
}

variable "master_cores" {
  type        = number
  description = "vCPU cores for master"
  default     = 2
}

variable "master_sockets" {
  type        = number
  description = "CPU sockets for master"
  default     = 1
}

variable "master_memory" {
  type        = number
  description = "Memory (MB) for master"
  default     = 2048
}

variable "master_ip_host" {
  type        = number
  description = "Last octet for master IP"
  default     = 230
}

variable "master_vmid" {
  type        = number
  description = "VMID for master"
  default     = 230
}

variable "master_tags" {
  type        = string
  description = "Tags for master VM (comma-separated)"
  default     = "k3s,master,terraform"
}

# ===== Nodes settings =====
variable "nodes_count" {
  type        = number
  description = "Number of worker nodes to create"
  default     = 3
}

variable "node_name_prefix" {
  type        = string
  description = "Prefix for node names"
  default     = "k8s-node"
}

variable "node_cores" {
  type        = number
  description = "vCPU cores for nodes"
  default     = 2
}

variable "node_sockets" {
  type        = number
  description = "CPU sockets for nodes"
  default     = 1
}

variable "node_memory" {
  type        = number
  description = "Memory (MB) for nodes"
  default     = 2048
}

variable "node_ip_start" {
  type        = number
  description = "Starting last octet for node IPs"
  default     = 231
}

variable "node_vmid_start" {
  type        = number
  description = "Starting VMID for nodes"
  default     = 231
}

variable "node_tags" {
  type        = string
  description = "Tags for worker node VMs (comma-separated)"
  default     = "k3s,worker,terraform"
}

# ===== Load Balancer settings =====
variable "nginx_lb_name" {
  type        = string
  description = "Name for the Nginx load balancer VM"
  default     = "k8s-nginx-lb"
}

variable "nginx_lb_cores" {
  type        = number
  description = "vCPU cores for Nginx load balancer"
  default     = 1
}

variable "nginx_lb_sockets" {
  type        = number
  description = "CPU sockets for Nginx load balancer"
  default     = 1
}

variable "nginx_lb_memory" {
  type        = number
  description = "Memory (MB) for Nginx load balancer"
  default     = 1024
}

variable "nginx_lb_ip_host" {
  type        = number
  description = "Last octet for Nginx load balancer IP"
  default     = 201
}

variable "nginx_lb_vmid" {
  type        = number
  description = "VMID for Nginx load balancer"
  default     = 201
}

variable "nginx_lb_tags" {
  type        = string
  description = "Tags for Nginx load balancer VM (comma-separated)"
  default     = "k8s,loadbalancer,nginx,terraform"
}

# ===== SSH access for cloud-init =====
variable "ssh_user" {
  type        = string
  description = "SSH username for cloud-init"
  default     = "user"
}

variable "ssh_password" {
  type        = string
  description = "SSH password for cloud-init"
  sensitive   = true
}
