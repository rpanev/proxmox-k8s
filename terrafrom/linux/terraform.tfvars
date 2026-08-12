# Homelab Proxmox config — edit here.
# Secrets, network, leader/worker count: secrets.env → secrets.auto.tfvars

# ===== Common =====
environment    = "homelab"
target_node    = "node2"
# Placement: 3 leaders + 3 workers across node1–node5 (node4 has two VMs)
proxmox_nodes  = ["node1", "node2", "node3", "node4", "node5"]

# ===== Storage =====
# Overridden by secrets.env → secrets.auto.tfvars (CEPH_STORAGE / PROXMOX_*)
ceph                 = false
ceph_datastore_id    = "ceph-prod"
shared_storage       = true
local_datastore_id   = "SSD-storage"
create_pool          = true

cloud_init_upgrade = false
vm_numa         = true
vm_hotplug      = "disk,network,usb,memory,cpu"
vm_agent_enabled = true
vm_wait_for_agent = false

# ===== Kubernetes cluster =====
vm_cores     = 4
vm_memory_mb = 8192
vm_disk_gb   = 20
# Longhorn data disk on workers (scsi1, raw — formatted by Ansible)
worker_data_disk_enabled = true
worker_data_disk_gb      = 50

leader_vmid_start = 220
worker_vmid_start = 230
leader_ip_start   = 220
worker_ip_start   = 230

# ===== K3s HAProxy LB =====
lb_enabled   = true
lb_vmid      = 210
lb_ip_host   = 210
lb_node      = "node1"
# Placement: first N entries used; LEADER_COUNT/WORKER_COUNT come from secrets.env
# IPs from secrets.env: IP_BASE=172.16.33 → LB .210, leaders .220+, workers .230+
leader_nodes = ["node4", "node2", "node3"]
worker_nodes = ["node5", "node1", "node4"]
lb_cores     = 2
lb_memory_mb = 2048
lb_disk_gb   = 10
k3s_api_port = 6443

# ===== Proxmox HA =====
ha_enabled  = true
ha_failback = true
ha_strict   = false

# ===== Firewall =====
manage_acl      = false
manage_firewall = false

# ===== Backup =====
backup_enabled        = true
backup_schedule       = "00:00"
backup_storage        = "PBS_HomeLAB"
backup_mode           = "snapshot"
backup_compress       = "zstd"
# backup_notes_template — auto from env_id (k8s-homelab → ◈ homelab/k8s · …)
