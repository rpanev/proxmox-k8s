resource "proxmox_vm_qemu" "k8s-master" {
  count       = var.master_count
  name        = "${var.master_name}-${count.index + 1}"
  target_node = var.target_node
  clone       = var.template_name
  cpu {
    cores   = var.master_cores
    sockets = var.master_sockets
  }
  memory = var.master_memory
  agent  = var.enable_agent ? 1 : 0
  tags   = var.master_tags
  pool   = proxmox_pool.k8s.poolid

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

  ipconfig0 = "ip=${var.ip_base}.${var.master_ip_host + count.index}/${var.network_cidr},gw=${var.gateway}"
  os_type   = var.os_type
  vmid      = var.master_vmid + count.index

  ciuser     = var.ssh_user
  cipassword = var.ssh_password
  sshkeys    = var.ssh_public_key

  serial {
    id   = var.serial_id
    type = var.serial_type
  }

  provisioner "remote-exec" {
    inline = ["echo ${var.ssh_password} | sudo -S -k hostnamectl set-hostname ${var.master_name}-${count.index + 1}"]

    connection {
      host        = self.ssh_host
      type        = "ssh"
      user        = var.ssh_user
      password    = var.ssh_password
      private_key = file(var.private_key_path)
    }
  }
}