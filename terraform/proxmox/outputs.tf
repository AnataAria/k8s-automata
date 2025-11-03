output "master_ips" {
  description = "IP addresses of master nodes"
  value = [
    for i in range(var.master_vm_config.vm_count) : "${var.master_vm_config.ip_base}.${i + var.master_vm_config.ip_offset}"
  ]
}

output "worker_ips" {
  description = "IP addresses of worker nodes"
  value = [
    for i in range(var.worker_vm_config.vm_count) : "${var.worker_vm_config.ip_base}.${i + var.worker_vm_config.ip_offset}"
  ]
}

output "loadbalancer_ip" {
  description = "IP address of the load balancer"
  value       = var.lxc_gateways.ipv4
}

output "master_names" {
  description = "Names of master VMs"
  value       = proxmox_vm_qemu.k8s_masters[*].name
}

output "worker_names" {
  description = "Names of worker VMs"
  value       = proxmox_vm_qemu.k8s_workers[*].name
}

output "loadbalancer_name" {
  description = "Name of the load balancer container"
  value       = proxmox_lxc.k8s_loadbalancer.hostname
}

output "cluster_summary" {
  description = "Complete cluster information"
  value = {
    cluster_name    = var.cluster_name
    master_count    = var.master_vm_config.vm_count
    worker_count    = var.worker_vm_config.vm_count
    master_ips      = [for i in range(var.master_vm_config.vm_count) : "${var.master_vm_config.ip_base}.${i + var.master_vm_config.ip_offset}"]
    worker_ips      = [for i in range(var.worker_vm_config.vm_count) : "${var.worker_vm_config.ip_base}.${i + var.worker_vm_config.ip_offset}"]
    loadbalancer_ip = var.lxc_gateways.ipv4
  }
}
