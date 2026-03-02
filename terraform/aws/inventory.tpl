[masters]
%{ for master in masters ~}
${master.tags.Name} ansible_host=${master.public_ip} ansible_user=ubuntu private_ip=${master.private_ip}
%{ endfor ~}

[workers]
%{ for worker in workers ~}
${worker.tags.Name} ansible_host=${worker.public_ip} ansible_user=ubuntu private_ip=${worker.private_ip}
%{ endfor ~}

[loadbalancers]
%{ for lb in loadbalancers ~}
${lb.tags.Name} ansible_host=${lb.public_ip} ansible_user=ubuntu private_ip=${lb.private_ip}
%{ endfor ~}

[etcds]
%{ for etcd in etcds ~}
${etcd.tags.Name} ansible_host=${etcd.public_ip} ansible_user=ubuntu private_ip=${etcd.private_ip}
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
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/id_rsa
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
k8s_version=1.31
cluster_name=${cluster_name}
service_subnet=10.96.0.0/12
pod_subnet=10.244.0.0/16
k8s_ssl_enabled=true
