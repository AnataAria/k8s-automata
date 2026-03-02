[masters]
%{ for i, master in masters ~}
${master.name} ansible_host=${master_ip_base}.${i + master_ip_offset} ansible_user=${vm_username}
%{ endfor ~}

[workers]
%{ for i, worker in workers ~}
${worker.name} ansible_host=${worker_ip_base}.${i + worker_ip_offset} ansible_user=${vm_username}
%{ endfor ~}

[loadbalancers]
${loadbalancer.hostname} ansible_host=${loadbalancer_ip} ansible_user=root

[etcds]
%{ for i, etcd in etcds ~}
${etcd.name} ansible_host=${etcd_ip_base}.${i + etcd_ip_offset} ansible_user=${vm_username}
%{ endfor ~}

[k8s_cluster:children]
masters
workers
etcds
loadbalancers

[cluster:children]
masters
workers
etcds
loadbalancers

[all:vars]
ansible_user=${vm_username}
ansible_ssh_private_key_file=${ssh_private_key_path}
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
k8s_version=${k8s_config.k8s_version}
cluster_name=${cluster_name}
service_subnet=10.96.0.0/12
pod_subnet=10.244.0.0/16
k8s_ssl_enabled=true
