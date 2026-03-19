# Inventory and Topology Contract

This document describes the current contract between Terraform-generated inventory and the Ansible implementation.

## Canonical Inventory Groups

The current canonical groups are defined in [`script/modules/ansible.sh`](../script/modules/ansible.sh) and enforced in [`ansible/site.yml`](../ansible/site.yml):

- `bastion`
- `load_balancers`
- `etcd`
- `control_plane`
- `workers`
- `k8s_cluster`
- `cluster_nodes`
- `services`

These names are the Ansible contract. Documentation and manually maintained inventories should use them exactly.

Do not use legacy group names such as `masters`. Terraform implementation internals may still refer to `masters` variables when rendering inventory, but the rendered inventory consumed by Ansible must use `control_plane`.

## Group Meaning

### `bastion`

Reserved for bastion or jump hosts. The current sample inventories and templates define the group, even when it is empty.

### `load_balancers`

Hosts that expose the kube-apiserver endpoint through HAProxy.

Used by:

- [`ansible/site.yml`](../ansible/site.yml) during the load-balancer play
- HAProxy-specific Make targets in [`Makefile`](../Makefile)
- topology assertions when HA control plane and load balancing are enabled

### `etcd`

Dedicated external etcd hosts.

Used by:

- [`ansible/roles/cert/tasks/main.yml`](../ansible/roles/cert/tasks/main.yml) for certificate generation and distribution
- [`ansible/roles/etcd/`](../ansible/roles/etcd/) for installation and verification
- backup and health workflows in [`script/workflows/maintenance.sh`](../script/workflows/maintenance.sh)

### `control_plane`

Kubernetes control-plane nodes.

Used by:

- kubeadm bootstrap and join logic in [`ansible/roles/control_plane/tasks/main.yml`](../ansible/roles/control_plane/tasks/main.yml)
- post-deployment verification in [`ansible/site.yml`](../ansible/site.yml)
- health and backup workflows that target `control_plane[0]`

### `workers`

Kubernetes worker nodes.

Used by:

- worker join logic in [`ansible/roles/worker/`](../ansible/roles/worker/)
- node-count verification in [`ansible/site.yml`](../ansible/site.yml)

### `k8s_cluster`

A child group containing:

- `control_plane`
- `workers`

### `cluster_nodes`

A child group containing:

- `etcd`
- `k8s_cluster`

This is the baseline-preparation target for the `common`, `containerd`, and `k8s` roles in [`ansible/site.yml`](../ansible/site.yml).

### `services`

A child group containing:

- `load_balancers`
- `bastion`

## Required Topology Rules

The current implementation asserts these rules in [`ansible/site.yml`](../ansible/site.yml):

- `control_plane` must have at least one host
- `workers` must have at least one host
- `control_plane_endpoint` must be defined and non-empty
- if `external_etcd_enabled=true`, then `etcd` must contain exactly three hosts
- if more than one control-plane host exists and `loadbalancer_enabled=true`, then `load_balancers` must contain at least one host

In addition, [`script/modules/ansible.sh`](../script/modules/ansible.sh) warns when canonical groups are missing from the inventory file.

## Required Host and Global Variables

The inventory templates and sample inventory show the variables that the current roles depend on.

### Common host variables

At minimum, hosts are expected to expose values that support these patterns:

- `ansible_host`: SSH target address
- `ansible_user`: SSH username
- `ip`: service or node IP used by cluster-facing templates and endpoint assembly

Some platforms also expose:

- `private_ip`: especially in AWS-generated inventory
- `access_ip`: accepted as a fallback by some templates and commands

Several roles and verification steps compute addresses in the following order:

1. `ip`
2. `access_ip`
3. `ansible_host`

If `ip` is omitted, ensure the chosen fallback is valid for etcd peer traffic, kubeadm advertise addresses, and control-plane-to-etcd communication.

### Common global variables in `[all:vars]`

The current examples and templates provide values such as:

- `cluster_name`
- `k8s_version`
- `service_cidr`
- `pod_network_cidr`
- `external_etcd_enabled`
- `loadbalancer_enabled`
- `ansible_ssh_private_key_file`
- `ansible_ssh_common_args`

The Proxmox example inventory is supplemented by [`ansible/inventories/proxmox/group_vars/all.yml`](../ansible/inventories/proxmox/group_vars/all.yml), which currently defines additional required behavior such as:

- `control_plane_endpoint`
- `container_runtime`
- `containerd_socket`
- `kubeadm_artifact_dir`
- `local_artifact_dir`
- `cni_plugin`
- token TTL values

## Terraform Inventory Generation

Terraform is expected to write `ansible/inventories/<platform>/hosts.ini`.

### AWS template behavior

[`terraform/aws/inventory.tpl`](../terraform/aws/inventory.tpl) currently:

- renders the canonical inventory groups
- places public addresses in `ansible_host`
- places private service addresses in `ip` and `private_ip`
- sets `ansible_user=ubuntu`
- hardcodes `ansible_ssh_private_key_file=~/.ssh/id_rsa`
- sets `external_etcd_enabled=true` and `loadbalancer_enabled=true`

### Proxmox template behavior

[`terraform/proxmox/inventory.tpl`](../terraform/proxmox/inventory.tpl) currently:

- renders the canonical inventory groups
- places rendered VM addresses directly in `ansible_host` and `ip`
- sets `ansible_user` from the Terraform VM credential configuration
- renders an absolute SSH private key path
- sets `external_etcd_enabled=true` and `loadbalancer_enabled=true`

## Example Inventory Shape

[`ansible/inventories/proxmox/hosts.example.ini`](../ansible/inventories/proxmox/hosts.example.ini) is the best current example of the expected inventory layout.

Key features of the example:

- empty `bastion` group is still present
- a dedicated `load_balancers` host is defined
- exactly three dedicated `etcd` hosts are defined
- three `control_plane` hosts are shown
- worker nodes are defined separately from the control plane
- `k8s_cluster`, `cluster_nodes`, and `services` are declared as child groups

## Topology Implications for Operators

Operators should treat the inventory as the contract that drives the whole Ansible execution plan.

Changing group membership changes behavior directly:

- adding or removing `load_balancers` changes HAProxy targets and Make target scope
- changing `control_plane` ordering changes which host becomes `control_plane[0]`
- altering `etcd` membership changes certificate generation, etcd cluster formation, health checks, and backup targets
- removing `workers` causes the default topology assertions to fail

## Manual Inventory Guidance

When building inventory manually instead of using Terraform:

1. keep the canonical group names exactly as documented here
2. preserve the child group relationships
3. provide a valid `control_plane_endpoint`
4. ensure `ip` values are routable between cluster components
5. ensure the etcd topology is three dedicated nodes when external etcd is enabled
6. avoid reintroducing legacy names like `masters`

## Known Current Caveats

There are a few repository realities operators should be aware of:

- AWS and Proxmox templates are aligned on group names but not fully aligned on SSH key defaults
- the sample Proxmox inventory and its group vars are the clearest source of current Ansible expectations
- the wrappers assume generated inventory exists before Ansible execution
- some Terraform example comments are older than the actual wrapper behavior, so operators should prefer documented wrapper entrypoints over comment text inside examples