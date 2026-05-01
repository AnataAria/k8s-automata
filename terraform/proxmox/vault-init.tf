resource "vault_approle_auth_backend_role" "ansible" {
    role_name = "k8s-automata-ansible"
    token_ttl = "30m"
    token_max_ttl = "60m"
}

resource "vault_approle_auth_backend_role_secret_id" "ansible" {
    role_name = vault_approle_auth_backend_role.ansible.role_name
}

locals {
  vault_role_id = vault_approle_auth_backend_role.ansible.role_id
  vault_secret_id = vault_approle_auth_backend_role_secret_id.ansible.secret_id
}

resource "local_file" "ansible_vault" {
  depends_on = [proxmox_vm_qemu.k8s_masters, proxmox_vm_qemu.k8s_workers, proxmox_lxc.k8s_loadbalancer, proxmox_vm_qemu.k8s_etcds]
  content = templatefile("${path.module}/cert.tpl", {
    vault_role_id = local.vault_role_id
    vault_secret_id = local.vault_secret_id
  })
  filename = "${path.root}/../../ansible/inventories/proxmox/group_vars/cert.yml"
}