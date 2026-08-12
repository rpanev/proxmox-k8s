# Network is provided by existing Proxmox bridges (vmbr0, etc.).
# Extend here with SDN zones or linux bridges when needed.

# resource "proxmox_virtual_environment_network_linux_bridge" "homelab" {
#   count     = var.create_network_bridge ? 1 : 0
#   node_name = var.target_node
#   name      = "vmbr0"
#   address   = "${var.ip_base}.1/${var.network_cidr}"
#   gateway   = var.network_gateway
#   bridge_ports = "none"
#   comment   = "${var.environment} isolated bridge"
# }
