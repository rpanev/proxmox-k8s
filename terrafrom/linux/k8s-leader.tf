resource "proxmox_virtual_environment_vm" "k8s_leader" {
  count = var.leader_count

  name      = var.leader_count == 1 ? "${var.env_id}-leader" : format("${var.env_id}-leader-%02d", count.index + 1)
  node_name = local.leader_node_names[count.index]
  vm_id     = var.leader_vmid_start + count.index
  tags      = concat(var.vm_tags, ["leader"])
  pool_id   = var.env_id

  depends_on = [
    proxmox_virtual_environment_pool.homelab,
    proxmox_virtual_environment_vm.k8s_lb,
  ]

  stop_on_destroy = true

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

  agent {
    enabled = var.vm_wait_for_agent && var.vm_agent_enabled
    timeout = "15m"

    dynamic "wait_for_ip" {
      for_each = var.vm_wait_for_agent ? [1] : []
      content {
        ipv4 = true
      }
    }
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

  initialization {
    datastore_id = local.datastore_id
    upgrade      = var.cloud_init_upgrade

    dns {
      domain  = var.dns_domain
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${var.ip_base}.${var.leader_ip_start + count.index}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }

    user_account {
      username = var.ssh_user
      password = var.ssh_password
      keys     = [var.ssh_public_key]
    }
  }
}
