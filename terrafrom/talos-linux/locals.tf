locals {
  # Ceph RBD or shared NFS (SSD-storage): spread VMs; local-lvm alone: pin to target_node
  spread_nodes = var.ceph || var.shared_storage
  datastore_id = var.ceph ? var.ceph_datastore_id : var.local_datastore_id

  lb_vm_name   = "${var.env_id}-lb"
  lb_node_name = local.spread_nodes ? var.lb_node : var.target_node

  cluster_node_slots = [
    for i in range(var.controlplane_count + var.worker_count) :
    var.proxmox_nodes[i % length(var.proxmox_nodes)]
  ]

  controlplane_node_names = (
    length(var.controlplane_nodes) >= var.controlplane_count
    ? slice(var.controlplane_nodes, 0, var.controlplane_count)
    : slice(local.cluster_node_slots, 0, var.controlplane_count)
  )

  worker_node_names = (
    length(var.worker_nodes) >= var.worker_count
    ? slice(var.worker_nodes, 0, var.worker_count)
    : slice(local.cluster_node_slots, var.controlplane_count, var.controlplane_count + var.worker_count)
  )

  network_cidr = "${var.ip_base}.0/${var.network_cidr}"

  ha_nodes_for_preferred = {
    for preferred in toset(var.proxmox_nodes) : preferred => {
      for i, node in concat([preferred], [for n in var.proxmox_nodes : n if n != preferred]) :
      node => length(var.proxmox_nodes) - i
    }
  }

  ha_lb_rule_id = "${var.env_id}-lb"

  backup_job_id         = "backup-${var.env_id}"
  backup_env_slug       = join("/", reverse(split("-", var.env_id)))
  backup_notes_template = "[${local.backup_env_slug}] {{guestname}} #{{vmid}} @ {{node}} | {{cluster}}"
}
