locals {
  spread_nodes = var.ceph || var.shared_storage
  datastore_id = var.ceph ? var.ceph_datastore_id : var.local_datastore_id

  lb_node_name = local.spread_nodes ? var.lb_node : var.target_node

  cluster_node_slots = [
    for i in range(var.leader_count + var.worker_count) :
    var.proxmox_nodes[(index(var.proxmox_nodes, local.lb_node_name) + 1 + i) % length(var.proxmox_nodes)]
  ]

  leader_node_names = (
    length(var.leader_nodes) >= var.leader_count
    ? slice(var.leader_nodes, 0, var.leader_count)
    : slice(local.cluster_node_slots, 0, var.leader_count)
  )

  worker_node_names = (
    length(var.worker_nodes) >= var.worker_count
    ? slice(var.worker_nodes, 0, var.worker_count)
    : slice(local.cluster_node_slots, var.leader_count, var.leader_count + var.worker_count)
  )

  ha_nodes_for_preferred = {
    for preferred in toset(var.proxmox_nodes) : preferred => {
      for i, node in concat([preferred], [for n in var.proxmox_nodes : n if n != preferred]) :
      node => length(var.proxmox_nodes) - i
    }
  }

  homelab_network_cidr = "${var.ip_base}.0/${var.network_cidr}"
  tailscale_proxy_tag  = "tag:${var.env_id}"

  lb_vm_name    = "${var.env_id}-lb"
  ha_lb_rule_id = "${var.env_id}-lb"
  backup_job_id = "backup-${var.env_id}"

  # k8s-homelab → homelab/k8s (auto from env_id in secrets.env)
  # ASCII only — Proxmox API mangles UTF-8 (◈ ·) and breaks terraform plan/apply.
  backup_env_slug       = join("/", reverse(split("-", var.env_id)))
  backup_notes_template = "[${local.backup_env_slug}] {{guestname}} #{{vmid}} @ {{node}} | {{cluster}}"
}
