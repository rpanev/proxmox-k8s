# Proxmox VE 9+ HA — https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/harule
#
# Each VM gets its own node-affinity rule with its Terraform-assigned node as highest
# priority. A shared rule with one node first pulled every HA resource onto that node.

# ----- HAProxy LB -----

resource "proxmox_haresource" "k8s_lb" {
  count = var.lb_enabled && var.ha_enabled ? 1 : 0

  resource_id = "vm:${proxmox_virtual_environment_vm.k8s_lb[0].vm_id}"
  state       = "started"
  comment     = "K8s HAProxy API LB (${var.ip_base}.${var.lb_ip_host}:${var.k3s_api_port})"
  failback    = var.ha_failback

  depends_on = [proxmox_virtual_environment_vm.k8s_lb]
}

resource "proxmox_harule" "k8s_lb" {
  count = var.lb_enabled && var.ha_enabled ? 1 : 0

  rule      = local.ha_lb_rule_id
  type      = "node-affinity"
  comment   = "K8s LB - preferred node ${local.lb_node_name}"
  resources = [proxmox_haresource.k8s_lb[0].resource_id]
  strict    = var.ha_strict
  nodes     = local.ha_nodes_for_preferred[local.lb_node_name]

  depends_on = [proxmox_haresource.k8s_lb]
}

# ----- K8s leaders -----

resource "proxmox_haresource" "k8s_leader" {
  count = var.ha_enabled ? var.leader_count : 0

  resource_id = "vm:${proxmox_virtual_environment_vm.k8s_leader[count.index].vm_id}"
  state       = "started"
  comment     = "K8s leader ${proxmox_virtual_environment_vm.k8s_leader[count.index].name}"
  failback    = var.ha_failback

  depends_on = [proxmox_virtual_environment_vm.k8s_leader]
}

resource "proxmox_harule" "k8s_leader" {
  count = var.ha_enabled ? var.leader_count : 0

  rule      = "${var.env_id}-leader-${format("%02d", count.index + 1)}"
  type      = "node-affinity"
  comment   = "K8s leader - preferred node ${local.leader_node_names[count.index]}"
  resources = [proxmox_haresource.k8s_leader[count.index].resource_id]
  strict    = var.ha_strict
  nodes     = local.ha_nodes_for_preferred[local.leader_node_names[count.index]]

  depends_on = [proxmox_haresource.k8s_leader]
}

# ----- K8s workers -----

resource "proxmox_haresource" "k8s_worker" {
  count = var.ha_enabled ? var.worker_count : 0

  resource_id = "vm:${proxmox_virtual_environment_vm.k8s_worker[count.index].vm_id}"
  state       = "started"
  comment     = "K8s worker ${proxmox_virtual_environment_vm.k8s_worker[count.index].name}"
  failback    = var.ha_failback

  depends_on = [proxmox_virtual_environment_vm.k8s_worker]
}

resource "proxmox_harule" "k8s_worker" {
  count = var.ha_enabled ? var.worker_count : 0

  rule      = "${var.env_id}-worker-${format("%02d", count.index + 1)}"
  type      = "node-affinity"
  comment   = "K8s worker - preferred node ${local.worker_node_names[count.index]}"
  resources = [proxmox_haresource.k8s_worker[count.index].resource_id]
  strict    = var.ha_strict
  nodes     = local.ha_nodes_for_preferred[local.worker_node_names[count.index]]

  depends_on = [proxmox_haresource.k8s_worker]
}
