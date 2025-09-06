[masters]
%{ for master in masters ~}
${master.tags.Name} ansible_host=${master.public_ip} ansible_user=ubuntu private_ip=${master.private_ip}
%{ endfor ~}

[workers]
%{ for worker in workers ~}
${worker.tags.Name} ansible_host=${worker.public_ip} ansible_user=ubuntu private_ip=${worker.private_ip}
%{ endfor ~}

[k8s_cluster:children]
masters
workers

[k8s_cluster:vars]
ansible_ssh_private_key_file=~/.ssh/id_rsa
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
