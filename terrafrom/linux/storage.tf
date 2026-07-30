resource "proxmox_virtual_environment_pool" "homelab" {
  count = var.create_pool ? 1 : 0

  pool_id = var.env_id
  comment = "K8s cluster pool for ${var.env_id}"
}
