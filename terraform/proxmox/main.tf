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
  automatic_reboot = true
  balloon = 0
  bios = "seabios"
  os_type = var.vm_os_type
  qemu_os = var.qemu_os
  target_node = var.proxmox_node
  clone       = var.template_name
  agent    = 1
  cpu {
    cores = var.master_cores
    sockets = var.master_socket
    type = var.master_cpu_type
  }
  memory   = var.master_memory
  scsihw   = "virtio-scsi-pci"

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
          size               = "${var.disk_size}G"
          storage            = var.storage_pool
        }
      }
    }
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
    type = var.worker_cpu_type
  }
  memory   = var.worker_memory
  scsihw   = "virtio-scsi-pci"

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
          size               = "${var.disk_size}G"
          storage            = var.storage_pool
        }
      }
    }
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

resource "proxmox_lxc" "k8s_loadbalancer" {
  features {
    nesting = true
  }
  hostname = var.lxc_os_hostname
  network {
    name = "eth0"
    bridge = "vmbro"
    ip = "dhcp"
    ip6 = "dhcp"
  }
  ostemplate = var.lxc_os_template
  target_node = var.proxmox_node
  unprivileged = true
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