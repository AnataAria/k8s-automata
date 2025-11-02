variable "proxmox_credential" {
  type = object({
    api_token_id     = string
    api_token_secret = string
  })
  description = "Proxmox VE API authentication credentials for secure access"
  sensitive   = true
}

variable "vm_credential" {
  type = object({
    username = string
    password = string
    ssh_keys = string
  })
  description = "Authentication credentials for VM access including SSH configuration"
  sensitive   = true
}
