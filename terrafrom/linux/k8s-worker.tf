resource "proxmox_virtual_environment_vm" "k8s_worker" {
  count = var.worker_count

  name      = format("${var.env_id}-worker-%02d", count.index + 1)
  node_name = local.worker_node_names[count.index]
  vm_id     = var.worker_vmid_start + count.index
  tags      = concat(var.vm_tags, ["worker"])
  pool_id   = var.env_id

  depends_on = [
    proxmox_virtual_environment_pool.homelab,
    proxmox_virtual_environment_vm.k8s_leader,
    proxmox_virtual_environment_vm.k8s_lb,
  ]

  stop_on_destroy = true

  clone {
    vm_id        = var.template_vm_id
    node_name    = var.template_node
    full         = true
    datastore_id = var.ceph ? var.ceph_datastore_id : var.local_datastore_id
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
    datastore_id = var.ceph ? var.ceph_datastore_id : var.local_datastore_id
    interface    = "scsi0"
    size         = var.vm_disk_gb
    discard      = "on"
    iothread     = true
  }

  dynamic "disk" {
    for_each = var.worker_data_disk_enabled ? [1] : []
    content {
      datastore_id = var.ceph ? var.ceph_datastore_id : var.local_datastore_id
      interface    = "scsi1"
      size         = var.worker_data_disk_gb
      discard      = "on"
      iothread     = true
    }
  }

  network_device {
    bridge  = var.network_bridge
    model   = "virtio"
    vlan_id = var.vlan_tag > 0 ? var.vlan_tag : null
  }

  initialization {
    datastore_id = var.ceph ? var.ceph_datastore_id : var.local_datastore_id
    upgrade      = var.cloud_init_upgrade

    dns {
      domain  = var.dns_domain
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${var.ip_base}.${var.worker_ip_start + count.index}/${var.network_cidr}"
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
