resource "proxmox_backup_job" "homelab_k8s" {
  count = var.backup_enabled ? 1 : 0

  id       = coalesce(var.backup_job_id, local.backup_job_id)
  schedule = var.backup_schedule
  storage  = var.backup_storage
  mode     = var.backup_mode
  enabled  = true

  pool           = var.env_id
  notes_template = var.backup_notes_template != "" ? var.backup_notes_template : local.backup_notes_template
  compress       = var.backup_compress

  prune_backups = length(var.backup_prune_backups) > 0 ? var.backup_prune_backups : null

  depends_on = [
    proxmox_virtual_environment_pool.homelab,
    proxmox_virtual_environment_vm.k8s_lb,
    proxmox_virtual_environment_vm.k8s_leader,
    proxmox_virtual_environment_vm.k8s_worker,
  ]
}
