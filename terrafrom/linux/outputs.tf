output "proxmox_version" {
  description = "Proxmox VE cluster version"
  value       = data.proxmox_version.cluster.version
}

output "proxmox_nodes" {
  description = "Available Proxmox nodes"
  value       = data.proxmox_virtual_environment_nodes.cluster.names
}

output "ceph_mode" {
  description = "Whether Ceph storage and multi-node placement is enabled"
  value       = var.ceph
}

output "env_id" {
  description = "Environment ID (Proxmox pool, VM names, hostnames)"
  value       = var.env_id
}

output "pool_members" {
  description = "VMIDs assigned to the environment pool"
  value = concat(
    var.lb_enabled ? [var.lb_vmid] : [],
    [for i in range(var.leader_count) : var.leader_vmid_start + i],
    [for i in range(var.worker_count) : var.worker_vmid_start + i],
  )
}

output "k8s_leader_nodes" {
  description = "Leader VM name, Proxmox node, IP and VMID"
  value = [
    for i in range(var.leader_count) : {
      name  = var.leader_count == 1 ? "${var.env_id}-leader" : format("${var.env_id}-leader-%02d", i + 1)
      node  = local.leader_node_names[i]
      ip    = "${var.ip_base}.${var.leader_ip_start + i}"
      vm_id = var.leader_vmid_start + i
    }
  ]
}

output "k8s_worker_nodes" {
  description = "Worker VM name, Proxmox node, IP and VMID"
  value = [
    for i in range(var.worker_count) : {
      name  = format("${var.env_id}-worker-%02d", i + 1)
      node  = local.worker_node_names[i]
      ip    = "${var.ip_base}.${var.worker_ip_start + i}"
      vm_id = var.worker_vmid_start + i
    }
  ]
}

output "leader_ssh_commands" {
  description = "SSH commands for leader nodes"
  value = [
    for i in range(var.leader_count) :
    "ssh ${var.ssh_user}@${var.ip_base}.${var.leader_ip_start + i}"
  ]
}

output "worker_ssh_commands" {
  description = "SSH commands for worker nodes"
  value = [
    for i in range(var.worker_count) :
    "ssh ${var.ssh_user}@${var.ip_base}.${var.worker_ip_start + i}"
  ]
}

output "cluster_info" {
  description = "K8s cluster summary"
  value = {
    env_id  = var.env_id
    platform = "k3s"
    leaders = {
      count = var.leader_count
      ips   = [for i in range(var.leader_count) : "${var.ip_base}.${var.leader_ip_start + i}"]
    }
    workers = {
      count = var.worker_count
      ips   = [for i in range(var.worker_count) : "${var.ip_base}.${var.worker_ip_start + i}"]
    }
    storage = local.datastore_id
  }
}

output "backup_job" {
  description = "Homelab K8s backup job configuration"
  value = var.backup_enabled ? {
    id       = coalesce(var.backup_job_id, local.backup_job_id)
    schedule = var.backup_schedule
    storage  = var.backup_storage
    pool     = var.env_id
    mode     = var.backup_mode
  } : null
}

output "k8s_lb" {
  description = "HAProxy load balancer for K3s API (cluster registration endpoint)"
  value = var.lb_enabled ? {
    name        = local.lb_vm_name
    ip          = "${var.ip_base}.${var.lb_ip_host}"
    vm_id       = var.lb_vmid
    node        = local.lb_node_name
    api_url     = "https://${var.ip_base}.${var.lb_ip_host}:${var.k3s_api_port}"
    api_port    = var.k3s_api_port
    join_hint   = "K3s agents should use https://${var.ip_base}.${var.lb_ip_host}:${var.k3s_api_port}"
  } : null
}

output "k3s_join_command" {
  description = "Example K3s agent join command (token from Ansible secrets)"
  value       = var.lb_enabled ? "curl -sfL https://get.k3s.io | K3S_URL=https://${var.ip_base}.${var.lb_ip_host}:${var.k3s_api_port} K3S_TOKEN=<token> sh -" : null
}

output "ha_rules" {
  description = "Proxmox HA node-affinity rules (one per VM)"
  value = {
    lb = var.lb_enabled && var.ha_enabled ? local.ha_lb_rule_id : null
    leaders = var.ha_enabled ? [
      for i in range(var.leader_count) : "${var.env_id}-leader-${format("%02d", i + 1)}"
    ] : []
    workers = var.ha_enabled ? [
      for i in range(var.worker_count) : "${var.env_id}-worker-${format("%02d", i + 1)}"
    ] : []
  }
}

output "k8s_vm_placement" {
  description = "Configured Proxmox node per K8s VM (from terraform.tfvars or auto-spread)"
  value = merge(
    var.lb_enabled ? { (local.lb_vm_name) = local.lb_node_name } : {},
    {
      for i in range(var.leader_count) :
      (var.leader_count == 1 ? "${var.env_id}-leader" : format("${var.env_id}-leader-%02d", i + 1)) => local.leader_node_names[i]
    },
    {
      for i in range(var.worker_count) :
      format("${var.env_id}-worker-%02d", i + 1) => local.worker_node_names[i]
    },
  )
}

output "homelab_network_cidr" {
  description = "Homelab LAN CIDR advertised by Tailscale subnet router"
  value       = local.homelab_network_cidr
}

output "tailscale_proxy_tag" {
  description = "Tailscale ACL tag for K8s proxies and subnet router (tag:<env_id>)"
  value       = local.tailscale_proxy_tag
}

output "tailscale" {
  description = "Tailscale operator / subnet router settings derived from env_id and network"
  value = {
    env_id               = var.env_id
    proxy_tag            = local.tailscale_proxy_tag
    homelab_network_cidr = local.homelab_network_cidr
    connector_name       = "connector-${var.env_id}"
    connector_hostname   = "subnet-router-${var.env_id}"
  }
}
