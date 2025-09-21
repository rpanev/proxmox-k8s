resource "proxmox_vm_qemu" "k8s-node" {
  count = var.nodes_count # number of VMs to create
  name  = "${var.node_name_prefix}${count.index + 1}"

  target_node = var.target_node

  ### Clone VM operation
  clone = var.template_name
  # note that cores, sockets and memory settings are not copied from the source VM template
  cpu {
    cores   = var.node_cores
    sockets = var.node_sockets
  }
  memory = var.node_memory
  tags   = var.node_tags
  pool   = proxmox_pool.k8s.poolid

  # Activate QEMU agent for this VM
  agent = var.enable_agent ? 1 : 0

  scsihw   = var.scsihw
  bootdisk = var.bootdisk

  disks {
    ide {
      ide2 {
        cloudinit {
          storage = var.cloudinit_storage
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size      = var.disk0_size_gb
          cache     = var.disk0_cache
          storage   = var.disk0_storage
          replicate = var.disk0_replicate
        }
      }
    }
  }

  network {
    id     = 0
    model  = var.net_model
    bridge = var.net_bridge
  }

  boot = var.boot_order

  ipconfig0 = "ip=${var.ip_base}.${count.index + var.node_ip_start}/${var.network_cidr},gw=${var.gateway}"
  os_type   = var.os_type
  vmid      = count.index + var.node_vmid_start

  ciuser     = var.ssh_user
  cipassword = var.ssh_password
  sshkeys    = var.ssh_public_key

  serial {
    id   = var.serial_id
    type = var.serial_type
  }

  provisioner "remote-exec" {
    inline = ["echo ${var.ssh_password} | sudo -S -k hostnamectl set-hostname ${self.name}"]

    connection {
      host        = self.ssh_host
      type        = "ssh"
      user        = var.ssh_user
      password    = var.ssh_password
      private_key = file(var.private_key_path)
    }
  }

}