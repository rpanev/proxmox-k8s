# ===== Proxmox API =====
variable "proxmox_endpoint" {
  type = string
}

variable "proxmox_api_token" {
  type      = string
  sensitive = true
}

variable "proxmox_insecure" {
  type    = bool
  default = true
}

variable "proxmox_ssh_agent" {
  type    = bool
  default = true
}

variable "proxmox_ssh_username" {
  type    = string
  default = "root"
}

# ===== Environment =====
variable "env_id" {
  type        = string
  description = "Proxmox pool + VM name prefix (e.g. talos-homelab)"
}

variable "vm_tags" {
  type    = list(string)
  default = ["talos", "terraform"]
}

# ===== Template (Talos cloud image on Proxmox) =====
variable "template_name" {
  type        = string
  description = "Informational template name"
}

variable "template_vm_id" {
  type = number
}

variable "template_node" {
  type    = string
  default = "node4"
}

# ===== Storage =====
variable "ceph" {
  type        = bool
  default     = false
  description = "Use Ceph RBD datastore (ceph_datastore_id) for VM disks"
}

variable "ceph_datastore_id" {
  type    = string
  default = "ceph-prod"
}

variable "shared_storage" {
  type        = bool
  default     = true
  description = "Spread VMs across proxmox_nodes when using shared NFS (e.g. SSD-storage)"
}

variable "local_datastore_id" {
  type        = string
  default     = "SSD-storage"
  description = "Proxmox datastore when ceph = false (NFS SSD-storage or local-lvm)"
}

variable "target_node" {
  type        = string
  description = "Single Proxmox node when neither ceph nor shared_storage"
  default     = "node1"
}

variable "proxmox_nodes" {
  type    = list(string)
  default = ["node1", "node2", "node3", "node4", "node5"]
}

variable "create_pool" {
  type    = bool
  default = true
}

# ===== Network =====
variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "network_gateway" {
  type = string
}

variable "network_cidr" {
  type    = number
  default = 24
}

variable "ip_base" {
  type = string
}

variable "vlan_tag" {
  type    = number
  default = 0
}

variable "dns_domain" {
  type    = string
  default = "panev.cloud"
}

variable "dns_servers" {
  type    = list(string)
  default = ["1.1.1.1"]
}

# ===== Cluster size =====
variable "controlplane_count" {
  type    = number
  default = 1
}

variable "worker_count" {
  type    = number
  default = 1
}

# ===== VM sizing =====
variable "vm_cores" {
  type    = number
  default = 4
}

variable "vm_memory_mb" {
  type    = number
  default = 8192
}

variable "vm_disk_gb" {
  type    = number
  default = 32
}

variable "worker_data_disk_enabled" {
  type    = bool
  default = true
}

variable "worker_data_disk_gb" {
  type    = number
  default = 50
}

variable "vm_cpu_type" {
  type    = string
  default = "host"
}

variable "vm_numa" {
  type    = bool
  default = true
}

variable "vm_hotplug" {
  type    = string
  # Exclude memory: virtio-balloon leaves ~806 MiB visible to Talos (health never passes).
  default = "disk,network,usb,cpu"
}

variable "cloud_init_upgrade" {
  type    = bool
  default = false
}

# ===== VMID / IP offsets (keep clear of k8s-homelab 210–232) =====
variable "controlplane_vmid_start" {
  type    = number
  default = 240
}

variable "worker_vmid_start" {
  type    = number
  default = 250
}

variable "controlplane_ip_start" {
  type    = number
  default = 240
}

variable "worker_ip_start" {
  type    = number
  default = 250
}

# ===== Placement overrides (optional) =====
variable "controlplane_nodes" {
  type    = list(string)
  default = []
}

variable "worker_nodes" {
  type    = list(string)
  default = []
}

# ===== SSH / cloud-init (HAProxy LB VM only — Talos nodes have no SSH) =====
variable "ssh_user" {
  type    = string
  default = "root"
}

variable "ssh_password" {
  type      = string
  sensitive = true
  default   = null
}

variable "ssh_public_key" {
  type = string
}

variable "vm_agent_enabled" {
  type    = bool
  default = true
}

variable "vm_wait_for_agent" {
  type    = bool
  default = false
}

# ===== HAProxy LB VM (Debian cloud-init template — not Talos) =====
variable "lb_enabled" {
  type    = bool
  default = true
}

variable "lb_vmid" {
  type    = number
  default = 238
}

variable "lb_ip_host" {
  type        = number
  description = "Last octet of LB IP (e.g. 238 → 192.168.99.238)"
  default     = 238
}

variable "lb_node" {
  type    = string
  default = "node4"
}

variable "lb_cores" {
  type    = number
  default = 2
}

variable "lb_memory_mb" {
  type    = number
  default = 2048
}

variable "lb_disk_gb" {
  type    = number
  default = 10
}

variable "lb_template_name" {
  type        = string
  description = "Cloud-init template for the HAProxy LB VM"
  default     = "Debian13-cloud"
}

variable "lb_template_vm_id" {
  type    = number
  default = 9003
}

variable "lb_template_node" {
  type    = string
  default = "node1"
}

variable "k3s_api_port" {
  type    = number
  default = 6443
  description = "Kubernetes API port (Talos uses upstream K8s on 6443)"
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

# ===== Proxmox HA (ha.tf) =====
variable "ha_enabled" {
  type        = bool
  description = "Register Talos VMs + LB in Proxmox HA (PVE 9+ rules)"
  default     = true
}

variable "ha_failback" {
  type        = bool
  description = "Automatically fail back VMs to preferred node when available"
  default     = true
}

variable "ha_strict" {
  type        = bool
  description = "Strict node affinity — VM only runs on listed nodes"
  default     = false
}
