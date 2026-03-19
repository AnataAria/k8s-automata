[bastion]

[load_balancers]
%{ for lb in loadbalancers ~}
${lb.tags.Name} ansible_host=${lb.public_ip} ip=${lb.private_ip} ansible_user=ubuntu private_ip=${lb.private_ip}
%{ endfor ~}

[etcd]
%{ for etcd in etcds ~}
${etcd.tags.Name} ansible_host=${etcd.public_ip} ip=${etcd.private_ip} ansible_user=ubuntu private_ip=${etcd.private_ip}
%{ endfor ~}

[control_plane]
%{ for master in masters ~}
${master.tags.Name} ansible_host=${master.public_ip} ip=${master.private_ip} ansible_user=ubuntu private_ip=${master.private_ip}
%{ endfor ~}

[workers]
%{ for worker in workers ~}
${worker.tags.Name} ansible_host=${worker.public_ip} ip=${worker.private_ip} ansible_user=ubuntu private_ip=${worker.private_ip}
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
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/id_rsa
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
k8s_version=1.31
cluster_name=${cluster_name}
service_cidr=10.96.0.0/12
pod_network_cidr=10.244.0.0/16
external_etcd_enabled=true
loadbalancer_enabled=true
