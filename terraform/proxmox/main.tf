terraform {
  required_version = ">= 1.0"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc04"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure     = var.proxmox_tls_insecure
}

resource "proxmox_vm_qemu" "k8s_masters" {
  count       = var.master_count
  name        = "${var.cluster_name}-master-${count.index + 1}"
  target_node = var.proxmox_node
  clone       = var.template_name
  
  agent    = 1
  os_type  = "cloud-init"
  cpu {
    cores = var.master_cores
    sockets = var.master_socket
    type = "host"
  }
  memory   = var.master_memory
  scsihw   = "virtio-scsi-pci"
  bootdisk = "scsi0"

  disk {
    slot     = 0
    size     = "${var.disk_size}G"
    type     = "scsi"
    storage  = var.storage_pool
    iothread = 1
  }

  network {
    id = 0
    model  = "virtio"
    bridge = var.network_bridge
  }

  lifecycle {
    ignore_changes = [
      network,
    ]
  }

  ipconfig0 = "ip=${var.master_ip_base}.${count.index + 10}/24,gw=${var.gateway}"
  
  ciuser     = var.vm_user
  cipassword = var.vm_password
  sshkeys    = var.ssh_keys

  tags = "k8s,master"
  automatic_reboot = true
  balloon = 0
}

resource "proxmox_vm_qemu" "k8s_workers" {
  count       = var.worker_count
  name        = "${var.cluster_name}-worker-${count.index + 1}"
  target_node = var.proxmox_node
  clone       = var.template_name
  
  agent    = 1
  os_type  = "cloud-init"
  cpu {
    cores = var.worker_cores
    sockets = var.worker_socket
    type = "host"
  }
  memory   = var.worker_memory
  scsihw   = "virtio-scsi-pci"
  bootdisk = "scsi0"

  disk {
    slot     = 0
    size     = "${var.disk_size}G"
    type     = "scsi"
    storage  = var.storage_pool
    iothread = 1
  }

  network {
    id = 0
    model  = "virtio"
    bridge = var.network_bridge
  }

  lifecycle {
    ignore_changes = [
      network,
    ]
  }

  ipconfig0 = "ip=${var.worker_ip_base}.${count.index + 10}/24,gw=${var.gateway}"
  
  ciuser     = var.vm_user
  cipassword = var.vm_password
  sshkeys    = var.ssh_keys

  tags = "k8s,worker"
}

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    masters = proxmox_vm_qemu.k8s_masters
    workers = proxmox_vm_qemu.k8s_workers
    master_ip_base = var.master_ip_base
    worker_ip_base = var.worker_ip_base
  })
  filename = "${path.root}/../ansible/inventories/proxmox/hosts.ini"
}