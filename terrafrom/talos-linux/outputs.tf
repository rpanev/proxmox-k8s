output "proxmox_version" {
  value = data.proxmox_version.cluster.version
}

output "env_id" {
  value = var.env_id
}

output "ceph_mode" {
  value = var.ceph
}

output "talos_lb" {
  description = "HAProxy VM — Kubernetes API endpoint for talosctl/kubeconfig"
  value = var.lb_enabled ? {
    name     = local.lb_vm_name
    node     = local.lb_node_name
    ip       = "${var.ip_base}.${var.lb_ip_host}"
    api_port = var.k3s_api_port
    api_url  = "https://${var.ip_base}.${var.lb_ip_host}:${var.k3s_api_port}"
    vm_id    = var.lb_vmid
  } : null
}

output "talos_controlplane_nodes" {
  description = "Talos control plane VMs"
  value = [
    for i in range(var.controlplane_count) : {
      name  = var.controlplane_count == 1 ? "${var.env_id}-leader" : format("${var.env_id}-leader-%02d", i + 1)
      node  = local.controlplane_node_names[i]
      ip    = "${var.ip_base}.${var.controlplane_ip_start + i}"
      vm_id = var.controlplane_vmid_start + i
    }
  ]
}

output "talos_worker_nodes" {
  description = "Talos worker VMs"
  value = [
    for i in range(var.worker_count) : {
      name  = format("${var.env_id}-worker-%02d", i + 1)
      node  = local.worker_node_names[i]
      ip    = "${var.ip_base}.${var.worker_ip_start + i}"
      vm_id = var.worker_vmid_start + i
    }
  ]
}

output "pool_members" {
  value = concat(
    var.lb_enabled ? [var.lb_vmid] : [],
    [for i in range(var.controlplane_count) : var.controlplane_vmid_start + i],
    [for i in range(var.worker_count) : var.worker_vmid_start + i],
  )
}

output "cluster_info" {
  value = {
    env_id        = var.env_id
    talos_template = "${var.template_name} (VMID ${var.template_vm_id} @ ${var.template_node})"
    lb_template   = "${var.lb_template_name} (VMID ${var.lb_template_vm_id} @ ${var.lb_template_node})"
    api_endpoint  = var.lb_enabled ? "https://${var.ip_base}.${var.lb_ip_host}:${var.k3s_api_port}" : null
    controlplanes = {
      count = var.controlplane_count
      ips   = [for i in range(var.controlplane_count) : "${var.ip_base}.${var.controlplane_ip_start + i}"]
    }
    workers = {
      count = var.worker_count
      ips   = [for i in range(var.worker_count) : "${var.ip_base}.${var.worker_ip_start + i}"]
    }
  }
}

output "backup_job" {
  description = "Proxmox PBS backup job for VMs in the homelab pool"
  value = var.backup_enabled ? {
    id       = coalesce(var.backup_job_id, local.backup_job_id)
    schedule = var.backup_schedule
    storage  = var.backup_storage
    pool     = var.env_id
    mode     = var.backup_mode
  } : null
}

output "ha_rules" {
  description = "Proxmox HA node-affinity rules (one per VM)"
  value = {
    lb = var.lb_enabled && var.ha_enabled ? local.ha_lb_rule_id : null
    leaders = var.ha_enabled ? [
      for i in range(var.controlplane_count) : "${var.env_id}-leader-${format("%02d", i + 1)}"
    ] : []
    workers = var.ha_enabled ? [
      for i in range(var.worker_count) : "${var.env_id}-worker-${format("%02d", i + 1)}"
    ] : []
  }
}

output "tailscale" {
  description = "Tailscale operator / subnet router settings derived from env_id and network"
  value = {
    env_id               = var.env_id
    proxy_tag            = "tag:${var.env_id}"
    homelab_network_cidr = local.network_cidr
    connector_name       = "connector-${var.env_id}"
    connector_hostname   = "subnet-router-${var.env_id}"
  }
}
