locals {
  etcd_ips = [
    for i in range(var.etcd_vm_config.vm_count) :
    "${var.etcd_vm_config.ip_base}.${var.etcd_vm_config.ip_offset + i}"
  ]

  etcd_ids = [
    for i in range(var.etcd_vm_config.vm_count) :
    "${var.etcd_vm_config.id_offset + i}"
  ]

  master_ips = [
    for i in range(var.master_vm_config.vm_count) :
    "${var.master_vm_config.ip_base}.${var.master_vm_config.ip_offset + i}"
  ]

  master_ids = [
    for i in range(var.master_vm_config.vm_count) :
    "${var.master_vm_config.id_offset + i}"
  ]

  worker_ips = [
    for i in range(var.worker_vm_config.vm_count) :
    "${var.worker_vm_config.ip_base}.${var.worker_vm_config.ip_offset + i}"
  ]

  worker_ids = [
    for i in range(var.worker_vm_config.vm_count) :
    "${var.worker_vm_config.id_offset + i}"
  ]

  gateway_ip = var.lxc_gateways.ipv4
  gateway_id = var.lxc_gateways.id

  all_ips = concat(local.etcd_ips, local.master_ips, local.worker_ips, [local.gateway_ip])
  all_ids = concat(local.etcd_ids, local.master_ids, local.worker_ids, [local.gateway_id])
}

check "unique_ips_across_cluster" {
  assert {
    condition     = length(local.all_ips) == length(distinct(local.all_ips))
    error_message = "Duplicate IPs found across etcd, master, worker, or gateway."
  }
}

check "unique_ids_across_cluster" {
  assert {
    condition     = length(local.all_ids) == length(distinct(local.all_ids))
    error_message = "Duplicate IDs found across etcd, master, worker, or gateway."
  }
}


variable "proxmox_config" {
  type = object({
    url            = string
    tls            = bool
    node_name      = string
    storage_pool   = string
    network_bridge = string
    gateway        = string
  })
  description = "Proxmox VE server configuration including connection details and resource settings"
  default = {
    url            = "value"
    tls            = true
    node_name      = "value"
    storage_pool   = "local-lvm"
    network_bridge = "vmbr0"
    gateway        = "192.168.1.1"
  }
}



variable "master_vm_config" {
  type = object({
    template_name = string
    ip_base       = string
    vm_count      = number
    cpu_core      = number
    cpu_socket    = number
    cpu_type      = string
    memory        = number
    os_type       = string
    qemu_os       = string
    bios          = string
    ip_offset     = number
    id_offset     = number
    disk_size     = number
  })
  description = "Configuration for Kubernetes master node VMs including hardware specs and network settings"
  default = {
    template_name = "ubuntu-22.04-template"
    ip_base       = "192.168.1"
    vm_count      = 3
    cpu_core      = 2
    cpu_socket    = 1
    cpu_type      = "x86-64-v2-AES"
    memory        = 4096
    os_type       = "cloud-init"
    qemu_os       = "l26"
    bios          = "seabios"
    ip_offset     = 0
    disk_size     = 32
    id_offset     = 200
  }
  validation {
    condition     = var.master_vm_config.vm_count > 0
    error_message = "master_vm_config.vm_count must be greater than 0"
  }
}

variable "worker_vm_config" {
  type = object({
    template_name = string
    ip_base       = string
    vm_count      = number
    cpu_core      = number
    cpu_socket    = number
    cpu_type      = string
    memory        = number
    os_type       = string
    qemu_os       = string
    bios          = string
    ip_offset     = number
    id_offset     = number
    disk_size     = number
  })
  description = "Configuration for Kubernetes worker node VMs including hardware specs and network settings"
  default = {
    template_name = "ubuntu-22.04-template"
    ip_base       = "192.168.1"
    vm_count      = 3
    cpu_core      = 4
    cpu_socket    = 1
    cpu_type      = "x86-64-v2-AES"
    memory        = 8192
    os_type       = "cloud-init"
    qemu_os       = "l26"
    bios          = "ovmf"
    ip_offset     = 0
    disk_size     = 64
    id_offset     = 300
  }

  validation {
    condition     = var.worker_vm_config.vm_count > 0
    error_message = "worker_vm_config.vm_count must be greater than 0"
  }
}

variable "etcd_vm_config" {
  type = object({
    template_name = string
    ip_base       = string
    vm_count      = number
    cpu_core      = number
    cpu_socket    = number
    cpu_type      = string
    memory        = number
    os_type       = string
    qemu_os       = string
    bios          = string
    ip_offset     = number
    id_offset     = number
    disk_size     = number
  })
  description = "Configuration for Kubernetes etcd node VMs including hardware specs and network settings"
  default = {
    template_name = "ubuntu-22.04-template"
    ip_base       = "192.168.1"
    vm_count      = 3
    cpu_core      = 2
    cpu_socket    = 1
    cpu_type      = "x86-64-v2-AES"
    memory        = 4096
    os_type       = "cloud-init"
    qemu_os       = "l26"
    bios          = "seabios"
    ip_offset     = 0
    disk_size     = 32
    id_offset     = 200
  }
  validation {
    condition     = var.etcd_vm_config.vm_count > 0
    error_message = "etcd_vm_config.vm_count must be greater than 0"
  }
}

variable "lxc_gateways" {
  type = object({
    id       = number
    template = string
    hostname = string
    memory   = number
    swap     = number
    cpu      = number
    ipv4     = string
    subnet   = number
  })
  description = "LXC container configuration for gateway services"
  default = {
    id       = 700
    template = "ubuntu-22.04-standard"
    hostname = "k8s-gateway"
    memory   = 4096
    swap     = 0
    cpu      = 2
    ipv4     = "192.168.1.10"
    subnet   = 24
  }
}

variable "cluster_name" {
  type        = string
  description = "Name of the Kubernetes cluster to be created"
  default     = "k8s-cluster"
}

variable "k8s_config" {
  type = object({
    k8s_version  = string
    etcd_version = string
    etcd_ha      = bool
  })
  description = "K8s configuration for using with ansible"
  default = {
    k8s_version  = "1.34.2"
    etcd_version = "3.6.0"
    etcd_ha      = true
  }
}

variable "hashicorp_vault_config" {
  type = object({
    addr = string
  })
  description = "Hashicorp vault config"
  default = {
    addr = "https://localhost:8200"
  }
}
