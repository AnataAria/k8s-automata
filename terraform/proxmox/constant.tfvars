proxmox_config = {
  url            = "https://your-proxmox-server:8006/api2/json"
  tls            = true
  node_name      = "your-proxmox-node-name"
  storage_pool   = "local-lvm"
  network_bridge = "vmbr0"
  gateway        = "192.168.1.1"
}

proxmox_credential = {
  api_token_id     = "terraform@pve!terraform"
  api_token_secret = "your-api-token-secret"
}

cluster_name = "my-k8s-cluster"

master_vm_config = {
  template_name = "ubuntu-22.04-template"
  ip_base       = "192.168.1"
  vm_count      = 1
  cpu_core      = 2
  cpu_socket    = 1
  cpu_type      = "host"
  memory        = 4096
  os_type       = "cloud-init"
  qemu_os       = "l26"
  bios          = "seabios"
}

worker_vm_config = {
  template_name = "ubuntu-22.04-template"
  ip_base       = "192.168.1"
  vm_count      = 2
  cpu_core      = 2
  cpu_socket    = 1
  cpu_type      = "host"
  memory        = 4096
  os_type       = "cloud-init"
  qemu_os       = "l26"
  bios          = "seabios"
}

lxc_gateways = {
  template = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
  hostname = "k8s-lb"
}

vm_credential = {
  username = "ubuntu"
  password = "your-password"
  ssh_keys = "ssh-rsa YOUR_SSH_PUBLIC_KEY"
}
