locals {
  vault_policy_name = "k8s-automata-ansible"
  vault_kv_mount    = "k8s-automata"
  create_kv_mount     = false
}

resource "vault_mount" "k8s-automata" {
  path = local.vault_kv_mount
  type = "kv"
  options     = { version = "2" }
  description = "KV v2 mount for CA certificates"
  count = local.create_kv_mount ? 1 : 0
}

resource "vault_policy" "ansible" {
  name = var.hashicorp_vault_config.policy_name

  policy = <<-EOT
    path "${var.hashicorp_vault_config.kv_mount}/data/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    path "${var.hashicorp_vault_config.kv_mount}/metadata/*" {
      capabilities = ["read", "list", "delete"]
    }
  EOT
}

resource "vault_approle_auth_backend_role" "ansible" {
  backend                 = "approle"
  role_name               = var.hashicorp_vault_config.policy_name
  token_ttl               = 1800
  token_max_ttl           = 3600
  token_no_default_policy = true
  token_policies          = [vault_policy.ansible.name]
}

resource "vault_approle_auth_backend_role_secret_id" "ansible" {
  backend   = vault_approle_auth_backend_role.ansible.backend
  role_name = vault_approle_auth_backend_role.ansible.role_name
}

locals {
  vault_addr      = var.hashicorp_vault_config.addr
  vault_role_id   = vault_approle_auth_backend_role.ansible.role_id
  vault_secret_id = vault_approle_auth_backend_role_secret_id.ansible.secret_id
}

resource "local_file" "ansible_vault" {
  depends_on = [proxmox_vm_qemu.k8s_masters, proxmox_vm_qemu.k8s_workers, proxmox_lxc.k8s_loadbalancer, proxmox_vm_qemu.k8s_etcds]
  content = templatefile("${path.module}/cert.tpl", {
    vault_addr      = local.vault_addr
    vault_role_id   = local.vault_role_id
    vault_secret_id = local.vault_secret_id
  })
  filename = "${path.root}/../../ansible/inventories/proxmox/group_vars/all/cert.yml"
}
