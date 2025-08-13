resource "proxmox_vm_qemu" "k8s-master" {
  count       = var.master_count
  name        = var.master_name
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

  ipconfig0 = "ip=${var.ip_base}.${var.master_ip_host}/${var.network_cidr},gw=${var.gateway}"
  os_type   = var.os_type
  vmid      = var.master_vmid

  ciuser     = var.ssh_user
  cipassword = var.ssh_password
  sshkeys    = var.ssh_public_key

  serial {
    id   = var.serial_id
    type = var.serial_type
  }

  provisioner "remote-exec" {
    inline = ["echo ${var.ssh_password} | sudo -S -k hostnamectl set-hostname ${var.master_hostname}"]

    connection {
      host        = self.ssh_host
      type        = "ssh"
      user        = var.ssh_user
      password    = var.ssh_password
      private_key = file(var.private_key_path)
    }
  }
}

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

# Configure master node with Ansible
resource "null_resource" "configure_master" {
  depends_on = [proxmox_vm_qemu.k8s-master]

  provisioner "local-exec" {
    command     = <<EOT
      ssh-keygen -f ~/.ssh/known_hosts -R ${var.ip_base}.${var.master_ip_host} || true

      while ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i ${var.private_key_path} ${var.ssh_user}@${var.ip_base}.${var.master_ip_host} 'exit'; do
        echo "Waiting for SSH to be available on master node..."
        sleep 10
      done

      ansible-playbook -u ${var.ssh_user} --private-key ${var.private_key_path} \
        -i '${var.ip_base}.${var.master_ip_host},' \
        ../ansible/install-master.yml \
        --ssh-extra-args='-o StrictHostKeyChecking=no'
    EOT
    working_dir = path.module
  }

  triggers = {
    master_ip = "${var.ip_base}.${var.master_ip_host}"
    timestamp = timestamp()
  }
}

# Configure worker nodes with Ansible
resource "null_resource" "configure_workers" {
  depends_on = [null_resource.configure_master, proxmox_vm_qemu.k8s-node]
  count      = var.nodes_count

  provisioner "local-exec" {
    command     = <<EOT
      ssh-keygen -f ~/.ssh/known_hosts -R ${var.ip_base}.${count.index + var.node_ip_start} || true

      while ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i ${var.private_key_path} ${var.ssh_user}@${var.ip_base}.${count.index + var.node_ip_start} 'exit'; do
        echo "Waiting for SSH to be available on worker node ${count.index + 1}..."
        sleep 10
      done

      ansible-playbook -u ${var.ssh_user} --private-key ${var.private_key_path} \
        -i '${var.ip_base}.${count.index + var.node_ip_start},' \
        ../ansible/install-workers.yml \
        --ssh-extra-args='-o StrictHostKeyChecking=no' \
        --extra-vars "master_private_ip=${var.ip_base}.${var.master_ip_host} master_public_ip=${var.ip_base}.${var.master_ip_host}"
    EOT
    working_dir = path.module
  }

  triggers = {
    worker_ip = "${var.ip_base}.${count.index + var.node_ip_start}"
    master_ip = "${var.ip_base}.${var.master_ip_host}"
    timestamp = timestamp()
  }
}
