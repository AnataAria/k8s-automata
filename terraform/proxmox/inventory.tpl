[bastion]

[load_balancers]
${loadbalancer.hostname} ansible_host=${loadbalancer_ip} ip=${loadbalancer_ip} ansible_user=root

[etcd]
%{ for i, etcd in etcds ~}
${etcd.name} ansible_host=${etcd_ip_base}.${i + etcd_ip_offset} ip=${etcd_ip_base}.${i + etcd_ip_offset} ansible_user=${vm_username}
%{ endfor ~}

[control_plane]
%{ for i, master in masters ~}
${master.name} ansible_host=${master_ip_base}.${i + master_ip_offset} ip=${master_ip_base}.${i + master_ip_offset} ansible_user=${vm_username}
%{ endfor ~}

[workers]
%{ for i, worker in workers ~}
${worker.name} ansible_host=${worker_ip_base}.${i + worker_ip_offset} ip=${worker_ip_base}.${i + worker_ip_offset} ansible_user=${vm_username}
%{ endfor ~}

[k8s_cluster:children]
control_plane
workers

[cluster_nodes:children]
etcd
k8s_cluster

[services:children]
load_balancers
bastion

[all:vars]
ansible_user=${vm_username}
ansible_ssh_private_key_file=${ssh_private_key_path}
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
k8s_version=${k8s_config.k8s_version}
cluster_name=${cluster_name}
service_cidr=10.96.0.0/12
pod_network_cidr=10.244.0.0/16
external_etcd_enabled=true
loadbalancer_enabled=true
