resource "proxmox_virtual_environment_vm" "talos_controlplane" {
  count = var.controlplane_count

  name      = var.controlplane_count == 1 ? "${var.env_id}-leader" : format("${var.env_id}-leader-%02d", count.index + 1)
  node_name = local.spread_nodes ? local.controlplane_node_names[count.index] : var.target_node
  vm_id     = var.controlplane_vmid_start + count.index
  tags      = concat(var.vm_tags, ["leader", "controlplane"])
  pool_id   = var.env_id

  depends_on = [
    proxmox_virtual_environment_pool.talos,
    proxmox_virtual_environment_vm.talos_lb,
  ]

  stop_on_destroy         = true
  purge_on_destroy        = true
  delete_unreferenced_disks_on_destroy = true

  clone {
    vm_id        = var.template_vm_id
    node_name    = var.template_node
    full         = true
    datastore_id = local.datastore_id
  }

  timeout_clone  = 1800
  timeout_create = 1800

  cpu {
    cores = var.vm_cores
    numa  = var.vm_numa
    type  = var.vm_cpu_type
  }

  hotplug = var.vm_hotplug

  memory {
    dedicated = var.vm_memory_mb
  }

  scsi_hardware = "virtio-scsi-single"

  # Talos image includes qemu-guest-agent; Proxmox must expose the virtio channel
  # or boot hangs waiting for ext-qemu-guest-agent (etcd/bootstrap never ready).
  agent {
    enabled = true
  }

  disk {
    datastore_id = local.datastore_id
    interface    = "scsi0"
    size         = var.vm_disk_gb
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge  = var.network_bridge
    model   = "virtio"
    vlan_id = var.vlan_tag > 0 ? var.vlan_tag : null
  }

  # Static IP via Proxmox cloud-init (Talos reads nocloud metadata).
  # Machine config / cluster bootstrap comes later (talosctl).
  initialization {
    datastore_id = local.datastore_id
    upgrade      = var.cloud_init_upgrade

    dns {
      domain  = var.dns_domain
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${var.ip_base}.${var.controlplane_ip_start + count.index}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }
  }
}
