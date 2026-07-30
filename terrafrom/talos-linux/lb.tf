resource "proxmox_virtual_environment_vm" "talos_lb" {
  count = var.lb_enabled ? 1 : 0

  name      = local.lb_vm_name
  node_name = local.lb_node_name
  vm_id     = var.lb_vmid
  tags      = concat(var.vm_tags, ["lb", "haproxy"])
  pool_id   = var.env_id

  depends_on = [proxmox_virtual_environment_pool.talos]

  stop_on_destroy                      = true
  purge_on_destroy                     = true
  delete_unreferenced_disks_on_destroy = true

  clone {
    vm_id        = var.lb_template_vm_id
    node_name    = var.lb_template_node
    full         = true
    # Template Debian13-cloud (LB HAProxy) lives on node1; Talos image is separate (template_node).
    # Without target datastore, cross-node full clone keeps NFStorage and disk resize fails.
    datastore_id = var.ceph ? var.ceph_datastore_id : var.local_datastore_id
  }

  timeout_clone  = 1800
  timeout_create = 1800

  cpu {
    cores = var.lb_cores
    numa  = var.vm_numa
    type  = var.vm_cpu_type
  }

  hotplug = var.vm_hotplug

  memory {
    dedicated = var.lb_memory_mb
  }

  scsi_hardware = "virtio-scsi-single"

  agent {
    enabled = var.vm_wait_for_agent && var.vm_agent_enabled
    timeout = "15m"
  }

  disk {
    datastore_id = var.ceph ? var.ceph_datastore_id : var.local_datastore_id
    interface    = "scsi0"
    size         = var.lb_disk_gb
    discard      = "on"
    iothread     = true
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
        address = "${var.ip_base}.${var.lb_ip_host}/${var.network_cidr}"
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
