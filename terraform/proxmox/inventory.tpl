[masters]
%{ for i, master in masters ~}
${master.name} ansible_host=${master_ip_base}.${i + master_ip_offset} ansible_user=ubuntu
%{ endfor ~}

[workers]
%{ for i, worker in workers ~}
${worker.name} ansible_host=${worker_ip_base}.${i + worker_ip_offset} ansible_user=ubuntu
%{ endfor ~}

[k8s_cluster:children]
masters
workers

[k8s_cluster:vars]
ansible_ssh_private_key_file=~/.ssh/root
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
