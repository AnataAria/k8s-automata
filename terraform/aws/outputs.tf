output "master_public_ips" {
  description = "Public IP addresses of master nodes"
  value       = aws_instance.k8s_masters[*].public_ip
}

output "master_private_ips" {
  description = "Private IP addresses of master nodes"
  value       = aws_instance.k8s_masters[*].private_ip
}

output "worker_public_ips" {
  description = "Public IP addresses of worker nodes"
  value       = aws_instance.k8s_workers[*].public_ip
}

output "worker_private_ips" {
  description = "Private IP addresses of worker nodes"
  value       = aws_instance.k8s_workers[*].private_ip
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.k8s_vpc.id
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.k8s_sg.id
}