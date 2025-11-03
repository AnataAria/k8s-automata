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
    ip_base       = "192.168.1.10"
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
    ip_base       = "192.168.1.20"
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
}

variable "lxc_gateways" {
  type = object({
    template = string
    hostname = string
    memory   = number
    swap     = number
    cpu      = number
    ipv4     = string
  })
  description = "LXC container configuration for gateway services"
  default = {
    template = "ubuntu-22.04-standard"
    hostname = "k8s-gateway"
    memory   = 4096
    swap     = 0
    cpu      = 2
    ipv4     = "192.168.1.10/24"
  }
}

variable "cluster_name" {
  type        = string
  description = "Name of the Kubernetes cluster to be created"
  default     = "k8s-cluster"
}
