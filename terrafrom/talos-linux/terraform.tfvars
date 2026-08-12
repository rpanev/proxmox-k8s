# Talos cluster — sizing, placement, templates.
# Secrets: ../../secrets.env → secrets.auto.tfvars (via deploy-infra.sh)

# ===== Talos cloud image (control plane + workers) =====
template_name  = "talos-os"
template_vm_id = 9006
template_node  = "node1"

# ===== HAProxy LB (Debian cloud-init — NOT Talos) =====
lb_enabled        = true
lb_vmid           = 210
lb_ip_host        = 210
lb_node           = "node1"
lb_template_name  = "Debian13-cloud"
lb_template_vm_id = 9003
lb_template_node  = "node1"
lb_cores          = 2
lb_memory_mb      = 2048
lb_disk_gb        = 10

# ===== Storage =====
ceph              = true
ceph_datastore_id = "ceph-prod"
local_datastore_id = "local-lvm"
create_pool       = true

# ===== VM sizing =====
vm_cores     = 4
vm_memory_mb = 8192
vm_disk_gb   = 32
# Longhorn data disk on workers (scsi1 — UserVolumeConfig in bootstrap-talos.sh)
worker_data_disk_enabled = true
worker_data_disk_gb      = 50

cloud_init_upgrade = false
vm_numa            = true
# No memory hotplug — virtio-balloon leaves ~806 MiB visible to Talos
vm_hotplug = "disk,network,usb,cpu"

# ===== VMID / IP (same range as terrafrom/linux K3s homelab) =====
controlplane_vmid_start = 220
worker_vmid_start       = 230
controlplane_ip_start   = 220
worker_ip_start         = 230

# Proxmox placement (3 CP + 3 workers; node4 has two VMs)
proxmox_nodes      = ["node1", "node2", "node3", "node4", "node5"]
controlplane_nodes = ["node4", "node2", "node3"]
worker_nodes       = ["node5", "node1", "node4"]

k3s_api_port = 6443

# ===== Proxmox HA (ha.tf) =====
ha_enabled  = true
ha_failback = true
ha_strict   = false

# ===== Proxmox backup (backup.tf — pool members via PBS) =====
backup_enabled  = true
backup_schedule = "03:00"
backup_storage  = "PBS_HomeLAB"
backup_mode     = "snapshot"
backup_compress = "zstd"
# backup_notes_template — auto from env_id (k8s-homelab → homelab/k8s · …)
