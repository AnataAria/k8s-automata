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

variable "proxmox_credential" {
  type = object({
    api_token_id     = string
    api_token_secret = string
  })
  description = "Proxmox VE API authentication credentials for secure access"
  default = {
    api_token_id     = "value"
    api_token_secret = "value"
  }
}

variable "master_vm_config" {
  type = object({
    template_name = string
    ip_base       = string
    vm_count      = number
    cpu_core      = number
    cpu_socket    = number
    cpu_type      = number
    memory        = number
    os_type       = string
    qemu_os       = string
    bios          = string
    ip_offset     = number
    disk_size     = number
  })
  description = "Configuration for Kubernetes master node VMs including hardware specs and network settings"
  default = {
    template_name = "ubuntu-22.04-template"
    ip_base       = "192.168.1.10"
    vm_count      = 3
    cpu_core      = 2
    cpu_socket    = 1
    cpu_type      = 0
    memory        = 4096
    os_type       = "cloud-init"
    qemu_os       = "l26"
    bios          = "ovmf"
    ip_offset     = 0
    disk_size     = 32
  }
}

variable "worker_vm_config" {
  type = object({
    template_name = string
    ip_base       = string
    vm_count      = number
    cpu_core      = number
    cpu_socket    = number
    cpu_type      = number
    memory        = number
    os_type       = string
    qemu_os       = string
    bios          = string
    ip_offset     = number
    disk_size     = number
  })
  description = "Configuration for Kubernetes worker node VMs including hardware specs and network settings"
  default = {
    template_name = "ubuntu-22.04-template"
    ip_base       = "192.168.1.20"
    vm_count      = 3
    cpu_core      = 4
    cpu_socket    = 1
    cpu_type      = 0
    memory        = 8192
    os_type       = "cloud-init"
    qemu_os       = "l26"
    bios          = "ovmf"
    ip_offset     = 0
    disk_size     = 64
  }
}

variable "lxc_gateways" {
  type = object({
    template = string
    hostname = string
  })
  description = "LXC container configuration for gateway services"
  default = {
    template = "ubuntu-22.04-standard"
    hostname = "k8s-gateway"
  }
}

variable "cluster_name" {
  type        = string
  description = "Name of the Kubernetes cluster to be created"
  default     = "k8s-cluster"
}

variable "vm_credential" {
  type = object({
    username = string
    password = string
    ssh_keys = string
  })
  description = "Authentication credentials for VM access including SSH configuration"
  default = {
    username = "ubuntu"
    password = "ubuntu"
    ssh_keys = ""
  }
}
