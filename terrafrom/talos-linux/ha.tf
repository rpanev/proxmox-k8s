# Proxmox VE 9+ HA — https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/harule
#
# Each VM gets its own node-affinity rule with its Terraform-assigned node as highest
# priority. Mirrors terrafrom/linux/ha.tf for the K3s stack.

# ----- HAProxy LB (Debian — Kubernetes API endpoint) -----

resource "proxmox_haresource" "talos_lb" {
  count = var.lb_enabled && var.ha_enabled ? 1 : 0

  resource_id = "vm:${proxmox_virtual_environment_vm.talos_lb[0].vm_id}"
  state       = "started"
  comment     = "Talos K8s API LB (${var.ip_base}.${var.lb_ip_host}:${var.k3s_api_port})"
  failback    = var.ha_failback

  depends_on = [proxmox_virtual_environment_vm.talos_lb]
}

resource "proxmox_harule" "talos_lb" {
  count = var.lb_enabled && var.ha_enabled ? 1 : 0

  rule      = local.ha_lb_rule_id
  type      = "node-affinity"
  comment   = "Talos LB - preferred node ${local.lb_node_name}"
  resources = [proxmox_haresource.talos_lb[0].resource_id]
  strict    = var.ha_strict
  nodes     = local.ha_nodes_for_preferred[local.lb_node_name]

  depends_on = [proxmox_haresource.talos_lb]
}

# ----- Talos control plane -----

resource "proxmox_haresource" "talos_controlplane" {
  count = var.ha_enabled ? var.controlplane_count : 0

  resource_id = "vm:${proxmox_virtual_environment_vm.talos_controlplane[count.index].vm_id}"
  state       = "started"
  comment     = "Talos control plane ${proxmox_virtual_environment_vm.talos_controlplane[count.index].name}"
  failback    = var.ha_failback

  depends_on = [proxmox_virtual_environment_vm.talos_controlplane]
}

resource "proxmox_harule" "talos_controlplane" {
  count = var.ha_enabled ? var.controlplane_count : 0

  rule      = "${var.env_id}-leader-${format("%02d", count.index + 1)}"
  type      = "node-affinity"
  comment   = "Talos leader - preferred node ${local.controlplane_node_names[count.index]}"
  resources = [proxmox_haresource.talos_controlplane[count.index].resource_id]
  strict    = var.ha_strict
  nodes     = local.ha_nodes_for_preferred[local.controlplane_node_names[count.index]]

  depends_on = [proxmox_haresource.talos_controlplane]
}

# ----- Talos workers -----

resource "proxmox_haresource" "talos_worker" {
  count = var.ha_enabled ? var.worker_count : 0

  resource_id = "vm:${proxmox_virtual_environment_vm.talos_worker[count.index].vm_id}"
  state       = "started"
  comment     = "Talos worker ${proxmox_virtual_environment_vm.talos_worker[count.index].name}"
  failback    = var.ha_failback

  depends_on = [proxmox_virtual_environment_vm.talos_worker]
}

resource "proxmox_harule" "talos_worker" {
  count = var.ha_enabled ? var.worker_count : 0

  rule      = "${var.env_id}-worker-${format("%02d", count.index + 1)}"
  type      = "node-affinity"
  comment   = "Talos worker - preferred node ${local.worker_node_names[count.index]}"
  resources = [proxmox_haresource.talos_worker[count.index].resource_id]
  strict    = var.ha_strict
  nodes     = local.ha_nodes_for_preferred[local.worker_node_names[count.index]]

  depends_on = [proxmox_haresource.talos_worker]
}
