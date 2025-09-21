output "proxmox_master_default_ip_addresses" {
  description = "Default IP addresses of all master VMs"
  value       = proxmox_vm_qemu.k8s-master[*].default_ipv4_address
}

output "proxmox_master_static_ip_addresses" {
  description = "Static IP addresses of all master VMs"
  value       = [for i in range(var.master_count) : "${var.ip_base}.${var.master_ip_host + i}"]
}

output "proxmox_nodes_default_ip_addresses" {
  description = "Default IP addresses of the worker node VMs"
  value       = proxmox_vm_qemu.k8s-node[*].default_ipv4_address
}

output "master_ssh_connections" {
  description = "SSH connection commands for all masters"
  value = [
    for i in range(var.master_count) :
    "ssh -i ${var.private_key_path} ${var.ssh_user}@${var.ip_base}.${var.master_ip_host + i}"
  ]
}

output "worker_ssh_connections" {
  description = "SSH connection commands for workers"
  value = [
    for i in range(var.nodes_count) :
    "ssh -i ${var.private_key_path} ${var.ssh_user}@${var.ip_base}.${var.node_ip_start + i}"
  ]
}

output "nginx_lb_ssh_connection" {
  description = "SSH connection command for Nginx load balancer"
  value       = "ssh -i ${var.private_key_path} ${var.ssh_user}@${var.ip_base}.${var.nginx_lb_ip_host}"
}

output "kubeconfig_command" {
  description = "Command to copy kubeconfig from first master"
  value       = "scp -i ${var.private_key_path} ${var.ssh_user}@${var.ip_base}.${var.master_ip_host}:~/.kube/config ./kubeconfig"
}

output "cluster_info" {
  description = "K3s HA cluster information"
  value = {
    masters = {
      count = var.master_count
      ips   = [for i in range(var.master_count) : "${var.ip_base}.${var.master_ip_host + i}"]
    }
    workers = {
      count = var.nodes_count
      ips   = [for i in range(var.nodes_count) : "${var.ip_base}.${var.node_ip_start + i}"]
    }
    loadbalancer = {
      ip = "${var.ip_base}.${var.nginx_lb_ip_host}"
    }
    api_endpoint = "https://${var.ip_base}.${var.nginx_lb_ip_host}:6443"
  }
}
