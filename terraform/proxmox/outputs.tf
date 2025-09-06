output "master_ips" {
  description = "IP addresses of master nodes"
  value = [
    for i in range(var.master_count) : "${var.master_ip_base}.${i + 10}"
  ]
}

output "worker_ips" {
  description = "IP addresses of worker nodes"
  value = [
    for i in range(var.worker_count) : "${var.worker_ip_base}.${i + 10}"
  ]
}

output "master_names" {
  description = "Names of master VMs"
  value       = proxmox_vm_qemu.k8s_masters[*].name
}

output "worker_names" {
  description = "Names of worker VMs"
  value       = proxmox_vm_qemu.k8s_workers[*].name
}