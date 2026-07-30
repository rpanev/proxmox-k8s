# ===== Proxmox API =====
variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API endpoint (any cluster node), e.g. https://172.16.33.2:8006/"
}

variable "proxmox_api_token" {
  type        = string
  description = "API token in format user@realm!tokenid=secret"
  sensitive   = true
}

variable "proxmox_insecure" {
  type        = bool
  description = "Skip TLS verification (self-signed certificates)"
  default     = true
}

variable "proxmox_ssh_agent" {
  type        = bool
  description = "Use SSH agent for provider file/snippet operations"
  default     = true
}

variable "proxmox_ssh_username" {
  type        = string
  description = "SSH username on Proxmox nodes (required when using API token)"
  default     = "root"
}

# ===== Common =====
variable "environment" {
  type        = string
  description = "Environment name used in tags"
  default     = "homelab"
}

variable "target_node" {
  type        = string
  description = "Proxmox node for all VMs when ceph = false"
}

variable "proxmox_nodes" {
  type        = list(string)
  description = "Proxmox node names for round-robin placement when ceph = true"
  default     = ["node1", "node2", "node3", "node4", "node5"]
}

variable "template_name" {
  type        = string
  description = "Cloud-init VM template name (informational)"
}

variable "template_vm_id" {
  type        = number
  description = "VMID of the cloud-init template to clone"
}

variable "template_node" {
  type        = string
  description = "Proxmox node where the template is registered"
  default     = "node1"
}

variable "env_id" {
  type        = string
  description = "Environment ID — Proxmox pool, VM names, and hostnames (e.g. myenv-lb, myenv-leader-01)"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key injected via cloud-init"
}

variable "ssh_user" {
  type        = string
  description = "Default SSH user for cloud-init"
  default     = "root"
}

variable "ssh_password" {
  type        = string
  description = "Optional cloud-init password"
  sensitive   = true
  default     = null
}

# ===== Storage =====
variable "ceph" {
  type        = bool
  description = "true: Ceph storage + spread VMs across proxmox_nodes; false: local storage on target_node"
  default     = true
}

variable "ceph_datastore_id" {
  type        = string
  description = "Proxmox Ceph/RBD storage ID for VM disks when ceph = true"
  default     = "ceph-prod"
}

variable "local_datastore_id" {
  type        = string
  description = "Proxmox local storage ID when ceph = false"
  default     = "local-lvm"
}

variable "create_pool" {
  type        = bool
  description = "Create Proxmox resource pool"
  default     = true
}

# ===== Network (vpc.tf) =====
variable "network_bridge" {
  type        = string
  description = "Linux bridge for VM NICs"
  default     = "vmbr0"
}

variable "network_gateway" {
  type        = string
  description = "Default gateway"
}

variable "network_cidr" {
  type        = number
  description = "CIDR suffix for static IPs"
  default     = 24
}

variable "ip_base" {
  type        = string
  description = "First three octets for static addressing, e.g. 172.16.33"
}

variable "vlan_tag" {
  type        = number
  description = "Optional VLAN tag for VM NICs (0 = untagged)"
  default     = 0
}

variable "dns_domain" {
  type        = string
  description = "Cloud-init DNS search domain"
  default     = "panev.cloud"
}

variable "dns_servers" {
  type        = list(string)
  description = "Cloud-init DNS servers"
  default     = ["1.1.1.1"]
}

variable "cloud_init_upgrade" {
  type        = bool
  description = "Run package upgrade on first boot via cloud-init"
  default     = true
}

variable "vm_cpu_type" {
  type        = string
  description = "QEMU CPU type — EL9/EL10 need host or x86-64-v2+; qemu64/kvm64 cause init kernel panic"
  default     = "host"
}

variable "vm_numa" {
  type        = bool
  description = "Enable NUMA (required when memory hotplug is enabled on the template)"
  default     = true
}

variable "vm_hotplug" {
  type        = string
  description = "Hotplug features: disk, network, usb, memory, cpu (memory requires NUMA)"
  default     = "disk,network,usb,memory,cpu"
}

variable "vm_agent_enabled" {
  type        = bool
  description = "Enable QEMU agent in Proxmox (only effective when vm_wait_for_agent = true)"
  default     = true
}

variable "vm_wait_for_agent" {
  type        = bool
  description = "Wait for qemu-guest-agent on apply/plan refresh — keep false unless agent runs in the guest"
  default     = false
}

# ===== Kubernetes cluster =====
variable "leader_count" {
  type        = number
  description = "Number of K8s leader (control-plane) nodes (max 10, IPs 220-229)"
  default     = 1

  validation {
    condition     = var.leader_count >= 1 && var.leader_count <= 10
    error_message = "leader_count must be between 1 and 10 (IP range 220-229)."
  }

  validation {
    condition     = var.leader_ip_start + var.leader_count - 1 <= 229
    error_message = "Not enough leader IPs in *.220-229 for leader_count."
  }
}

variable "worker_count" {
  type        = number
  description = "Number of K8s worker nodes (max 10, IPs 230-239)"
  default     = 3

  validation {
    condition     = var.worker_count >= 0 && var.worker_count <= 10
    error_message = "worker_count must be between 0 and 10 (IP range 230-239)."
  }

  validation {
    condition     = var.worker_ip_start + var.worker_count - 1 <= 239
    error_message = "Not enough worker IPs in *.230-239 for worker_count."
  }
}

variable "vm_cores" {
  type        = number
  description = "vCPU cores per K8s node"
  default     = 4
}

variable "vm_memory_mb" {
  type        = number
  description = "Memory (MB) per K8s node"
  default     = 8192
}

variable "vm_disk_gb" {
  type        = number
  description = "Disk size (GB) per K8s node"
  default     = 20
}

variable "worker_data_disk_enabled" {
  type        = bool
  description = "Attach a dedicated data disk to each worker VM (for Longhorn)"
  default     = true
}

variable "worker_data_disk_gb" {
  type        = number
  description = "Dedicated Longhorn data disk size (GB) per worker VM"
  default     = 30
}

variable "vm_tags" {
  type        = list(string)
  description = "Tags applied to all K8s VMs"
  default     = ["k8s", "terraform"]
}

variable "leader_vmid_start" {
  type        = number
  description = "Starting VMID for leader nodes (aligned with IP range 220-229)"
  default     = 220
}

variable "worker_vmid_start" {
  type        = number
  description = "Starting VMID for worker nodes (aligned with IP range 230-239)"
  default     = 230
}

variable "leader_ip_start" {
  type        = number
  description = "Last octet for the first leader IP (range 220-229)"
  default     = 220

  validation {
    condition     = var.leader_ip_start >= 220 && var.leader_ip_start <= 229
    error_message = "Leader IPs must use last octet in 220-229."
  }
}

variable "worker_ip_start" {
  type        = number
  description = "Last octet for the first worker IP (range 230-239)"
  default     = 230

  validation {
    condition     = var.worker_ip_start >= 230 && var.worker_ip_start <= 239
    error_message = "Worker IPs must use last octet in 230-239."
  }
}

# ===== K3s Load Balancer (k8s-lb.tf) =====
variable "lb_enabled" {
  type        = bool
  description = "Deploy HAProxy VM for K3s API load balancing"
  default     = true
}

# lb_name derived from env_id in locals.tf (${env_id}-lb)

variable "lb_vmid" {
  type        = number
  description = "Proxmox VMID for the load balancer"
  default     = 210
}

variable "lb_ip_host" {
  type        = number
  description = "Last octet for LB static IP (range 200-219, before leaders)"
  default     = 210

  validation {
    condition     = var.lb_ip_host >= 200 && var.lb_ip_host <= 219
    error_message = "LB IP must use last octet in 200-219."
  }
}

variable "lb_node" {
  type        = string
  description = "Proxmox node for the HAProxy LB VM"
  default     = "node1"
}

variable "leader_nodes" {
  type        = list(string)
  description = "Preferred Proxmox nodes for leaders (first N used). Shorter than leader_count = auto-spread."
  default     = []
}

variable "worker_nodes" {
  type        = list(string)
  description = "Preferred Proxmox nodes for workers (first N used). Shorter than worker_count = auto-spread."
  default     = []
}

variable "lb_cores" {
  type        = number
  description = "vCPU cores for HAProxy LB"
  default     = 2
}

variable "lb_memory_mb" {
  type        = number
  description = "Memory (MB) for HAProxy LB"
  default     = 2048
}

variable "lb_disk_gb" {
  type        = number
  description = "Disk size (GB) for HAProxy LB"
  default     = 10
}

variable "k3s_api_port" {
  type        = number
  description = "Kubernetes API port fronted by HAProxy"
  default     = 6443
}

# ===== Proxmox HA (ha.tf) =====
variable "ha_enabled" {
  type        = bool
  description = "Register LB VM in Proxmox HA (PVE 9+ rules)"
  default     = true
}

# HA rule names derived from env_id in locals.tf and ha.tf

variable "ha_failback" {
  type        = bool
  description = "Automatically fail back LB to preferred node when available"
  default     = true
}

variable "ha_strict" {
  type        = bool
  description = "Strict node affinity — LB only runs on listed nodes"
  default     = false
}

# ===== IAM (iam.tf) =====
variable "manage_acl" {
  type        = bool
  description = "Manage Proxmox ACL entries via Terraform"
  default     = false
}

variable "terraform_acl_role" {
  type        = string
  description = "Proxmox role assigned to the Terraform API token user"
  default     = "PVEAdmin"
}

variable "terraform_acl_path" {
  type        = string
  description = "ACL path, e.g. /"
  default     = "/"
}

# ===== Firewall (security-groups.tf) =====
variable "manage_firewall" {
  type        = bool
  description = "Manage datacenter firewall rules via Terraform"
  default     = false
}

variable "firewall_allowed_cidrs" {
  type        = list(string)
  description = "Source CIDRs allowed to reach homelab services"
  default     = ["172.16.0.0/16"]
}

# ===== Backup (backup.tf) =====
variable "backup_enabled" {
  type        = bool
  description = "Create nightly backup job for VMs in the homelab pool"
  default     = true
}

variable "backup_job_id" {
  type        = string
  description = "Proxmox backup job identifier (default: backup-<env_id> via locals)"
  default     = null
}

variable "backup_schedule" {
  type        = string
  description = "Backup schedule (Proxmox calendar format, e.g. 00:00 for daily midnight)"
  default     = "00:00"
}

variable "backup_storage" {
  type        = string
  description = "Backup storage target (PBS datastore name)"
  default     = "PBS_HomeLAB"
}

variable "backup_mode" {
  type        = string
  description = "Backup mode: snapshot, suspend, or stop"
  default     = "snapshot"
}

variable "backup_compress" {
  type        = string
  description = "Compression: 0, 1, gzip, lzo, or zstd"
  default     = "zstd"
}

variable "backup_notes_template" {
  type        = string
  description = "Override PBS backup notes template. Empty = auto from env_id (e.g. k8s-homelab → homelab/k8s). Proxmox vars: {{guestname}}, {{vmid}}, {{node}}, {{cluster}}"
  default     = ""
}

variable "backup_prune_backups" {
  type        = map(string)
  description = "Retention policy, e.g. { keep-daily = \"7\" }. Empty = PBS storage default."
  default     = {}
}
