output "proxmox_master_default_ip_addresses" {
  description = "Default IP address of the master VM"
  value       = proxmox_vm_qemu.k8s-master[*].default_ipv4_address
}

output "proxmox_nodes_default_ip_addresses" {
  description = "Default IP addresses of the worker node VMs"
  value       = proxmox_vm_qemu.k8s-node[*].default_ipv4_address
}

output "master_ssh_connection" {
  description = "SSH connection command for master"
  value       = "ssh -i ${var.private_key_path} ${var.ssh_user}@${var.ip_base}.${var.master_ip_host}"
}

output "worker_ssh_connections" {
  description = "SSH connection commands for workers"
  value = [
    for i in range(var.nodes_count) :
    "ssh -i ${var.private_key_path} ${var.ssh_user}@${var.ip_base}.${var.node_ip_start + i}"
  ]
}

output "kubeconfig_command" {
  description = "Command to copy kubeconfig from master"
  value       = "scp -i ${var.private_key_path} ${var.ssh_user}@${var.ip_base}.${var.master_ip_host}:~/.kube/config ./kubeconfig"
}
