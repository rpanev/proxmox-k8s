resource "proxmox_virtual_environment_pool" "talos" {
  count = var.create_pool ? 1 : 0

  pool_id = var.env_id
  comment = "Talos Linux test cluster (${var.env_id})"
}
