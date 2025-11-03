resource "proxmox_vm_qemu" "k8s_masters" {
  depends_on       = [proxmox_lxc.k8s_loadbalancer]
  count            = var.master_vm_config.vm_count
  vmid             = var.master_vm_config.id_offset + count.index
  name             = "${var.cluster_name}-master-${count.index + 1}"
  automatic_reboot = true
  balloon          = 0
  bios             = var.master_vm_config.bios
  os_type          = var.master_vm_config.cpu_type
  qemu_os          = var.master_vm_config.qemu_os
  target_node      = var.proxmox_config.node_name
  clone            = var.master_vm_config.template_name
  agent            = 1
  vm_state         = "running"
  onboot           = true
  additional_wait  = 30
  cpu {
    cores   = var.master_vm_config.cpu_core
    sockets = var.master_vm_config.cpu_socket
    type    = var.master_vm_config.cpu_type
  }
  serial {
    id = 0
  }
  memory = var.master_vm_config.memory
  scsihw = "virtio-scsi-pci"

  disks {
    scsi {
      scsi0 {
        disk {
          backup             = true
          cache              = "none"
          discard            = true
          emulatessd         = true
          iothread           = true
          mbps_r_burst       = 0.0
          mbps_r_concurrent  = 0.0
          mbps_wr_burst      = 0.0
          mbps_wr_concurrent = 0.0
          replicate          = true
          size               = "${var.master_vm_config.disk_size}G"
          storage            = var.proxmox_config.storage_pool
        }
      }
    }
    ide {
      ide1 {
        cloudinit {
          storage = var.proxmox_config.storage_pool
        }
      }
    }
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = var.proxmox_config.network_bridge
  }

  lifecycle {
    ignore_changes = [
      network,
    ]
  }

  ipconfig0 = "ip=${var.master_vm_config.ip_base}.${count.index + 10}/24,gw=${var.proxmox_config.gateway}"

  ciuser     = var.vm_credential.username
  cipassword = var.vm_credential.password
  sshkeys    = var.vm_credential.ssh_keys

  tags = "k8s,master"

  provisioner "local-exec" {
    command = "echo 'Master ${count.index + 1} created, waiting 10 seconds before next...'; sleep 10"
  }
}

resource "proxmox_vm_qemu" "k8s_workers" {
  depends_on       = [proxmox_vm_qemu.k8s_masters]
  count            = var.worker_vm_config.vm_count
  vmid             = var.worker_vm_config.id_offset + count.index
  name             = "${var.cluster_name}-worker-${count.index + 1}"
  automatic_reboot = true
  balloon          = 0
  bios             = var.worker_vm_config.bios
  os_type          = var.worker_vm_config.os_type
  qemu_os          = var.worker_vm_config.qemu_os
  target_node      = var.proxmox_config.node_name
  clone            = var.worker_vm_config.template_name
  vm_state         = "running"
  onboot           = true
  additional_wait  = 30

  agent = 1
  cpu {
    cores   = var.worker_vm_config.cpu_core
    sockets = var.worker_vm_config.cpu_socket
    type    = var.worker_vm_config.cpu_type
  }

  serial {
    id = 0
  }
  memory = var.worker_vm_config.memory
  scsihw = "virtio-scsi-pci"

  disks {
    scsi {
      scsi0 {
        disk {
          backup             = true
          cache              = "none"
          discard            = true
          emulatessd         = true
          iothread           = true
          mbps_r_burst       = 0.0
          mbps_r_concurrent  = 0.0
          mbps_wr_burst      = 0.0
          mbps_wr_concurrent = 0.0
          replicate          = true
          size               = "${var.worker_vm_config.disk_size}G"
          storage            = var.proxmox_config.storage_pool
        }
      }
    }
    ide {
      ide1 {
        cloudinit {
          storage = var.proxmox_config.storage_pool
        }
      }
    }
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = var.proxmox_config.network_bridge
  }

  lifecycle {
    ignore_changes = [
      network,
    ]
  }

  ipconfig0 = "ip=${var.worker_vm_config.ip_base}.${count.index + var.worker_vm_config.ip_offset}/24,gw=${var.proxmox_config.gateway}"

  ciuser     = var.vm_credential.username
  cipassword = var.vm_credential.password
  sshkeys    = var.vm_credential.ssh_keys

  tags = "k8s,worker"

  provisioner "local-exec" {
    command = "echo 'Worker ${count.index + 1} created, waiting 5 seconds before next...'; sleep 5"
  }
}

resource "proxmox_lxc" "k8s_loadbalancer" {
  features {
    nesting = true
  }
  hostname = var.lxc_gateways.hostname
  start    = true
  onboot   = true
  memory   = var.lxc_gateways.memory
  cores    = 2
  swap     = var.lxc_gateways.swap
  network {
    name     = "eth0"
    bridge   = var.proxmox_config.network_bridge
    ip       = var.lxc_gateways.ipv4
    ip6      = "auto"
    firewall = true
  }
  ssh_public_keys = var.vm_credential.ssh_keys
  ostemplate      = var.lxc_gateways.template
  target_node     = var.proxmox_config.node_name
  unprivileged    = true

  rootfs {
    storage = "local-zfs"
    size    = "8G"
  }

  provisioner "local-exec" {
    command = "echo 'Load Balancer created, waiting 20 seconds before creating masters...'; sleep 20"
  }
}

resource "local_file" "ansible_inventory" {
  depends_on = [proxmox_vm_qemu.k8s_masters, proxmox_vm_qemu.k8s_workers]
  content = templatefile("${path.module}/inventory.tpl", {
    masters              = proxmox_vm_qemu.k8s_masters
    workers              = proxmox_vm_qemu.k8s_workers
    master_ip_base       = var.master_vm_config.ip_base
    worker_ip_base       = var.worker_vm_config.ip_base
    master_ip_offset     = var.master_vm_config.ip_offset
    worker_ip_offset     = var.worker_vm_config.ip_offset
    ssh_private_key_path = var.vm_credential.ssh_private_key_path
  })
  filename = "${path.root}/../../ansible/inventories/proxmox/hosts.ini"
}
