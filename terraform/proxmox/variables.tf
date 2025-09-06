variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token Secret"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Allow insecure TLS connections"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "k8s-cluster"
}

variable "template_name" {
  description = "Name of the VM template to clone"
  type        = string
  default     = "ubuntu-22.04-template"
}

variable "network_bridge" {
  description = "Network bridge to use"
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "Network gateway"
  type        = string
  default     = "192.168.1.1"
}

variable "master_ip_base" {
  description = "Base IP for master nodes (e.g., 192.168.1)"
  type        = string
  default     = "192.168.1"
}

variable "worker_ip_base" {
  description = "Base IP for worker nodes (e.g., 192.168.1)"
  type        = string
  default     = "192.168.1"
}

variable "storage_pool" {
  description = "Proxmox storage pool"
  type        = string
  default     = "local-lvm"
}

variable "disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 20
}

variable "master_count" {
  description = "Number of master nodes"
  type        = number
  default     = 1
}

variable "master_cores" {
  description = "Number of CPU cores for master nodes"
  type        = number
  default     = 2
}

variable "master_memory" {
  description = "Memory in MB for master nodes"
  type        = number
  default     = 4096
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "worker_cores" {
  description = "Number of CPU cores for worker nodes"
  type        = number
  default     = 2
}

variable "worker_memory" {
  description = "Memory in MB for worker nodes"
  type        = number
  default     = 4096
}

variable "vm_user" {
  description = "VM user for cloud-init"
  type        = string
  default     = "ubuntu"
}

variable "vm_password" {
  description = "VM password for cloud-init"
  type        = string
  sensitive   = true
}

variable "ssh_keys" {
  description = "SSH public keys for cloud-init"
  type        = string
}
