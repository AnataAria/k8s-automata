terraform {
  required_version = ">= 1.0"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc05"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.proxmox_config.url
  pm_api_token_id     = var.proxmox_credential.api_token_id
  pm_api_token_secret = var.proxmox_credential.api_token_secret
  pm_tls_insecure     = var.proxmox_config.tls
}
