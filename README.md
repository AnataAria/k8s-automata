# K8s Automata

K8s Automata is an infrastructure and cluster automation repository for provisioning Kubernetes environments with Terraform and configuring them with Ansible. The repository currently targets two infrastructure providers:

- AWS, using Terraform under `terraform/aws/`
- Proxmox, using Terraform under `terraform/proxmox/`

The Ansible implementation in `ansible/` is built around a kubeadm-based highly available control plane with:

- canonical inventory groups shared across platforms
- optional HAProxy-based API load balancers
- dedicated external etcd nodes
- containerd as the container runtime
- role-oriented playbook execution through `ansible/site.yml`

This README reflects the current repository state and current operator entrypoints. It does not describe legacy playbooks, legacy inventory group names, or Docker-based runtime assumptions.

## Repository Scope

Infrastructure provisioning and cluster configuration are intentionally split:

- Terraform provisions platform-specific compute and networking and renders platform inventories through [`terraform/aws/inventory.tpl`](terraform/aws/inventory.tpl) and [`terraform/proxmox/inventory.tpl`](terraform/proxmox/inventory.tpl).
- Ansible validates the generated topology and configures the Kubernetes cluster through [`ansible/site.yml`](ansible/site.yml).
- Shell wrappers under [`script/`](script/) and convenience targets in [`Makefile`](Makefile) provide the supported operator workflows.

## Current Architecture Summary

The current Ansible execution flow in [`ansible/site.yml`](ansible/site.yml) is:

1. Validate inventory structure and topology requirements.
2. Prepare all cluster nodes with baseline OS, kernel, containerd, and Kubernetes packages.
3. Configure API load balancers on `load_balancers` when enabled.
4. Stage PKI material for external etcd and control-plane integration.
5. Deploy the external etcd cluster on dedicated `etcd` hosts.
6. Bootstrap the first control-plane node.
7. Join remaining control-plane nodes.
8. Join worker nodes.
9. Install the selected CNI from the bootstrap control-plane node.
10. Verify cluster health and external etcd reachability.

For design details and component boundaries, see [`docs/architecture.md`](docs/architecture.md). For the inventory contract, see [`docs/inventory-topology.md`](docs/inventory-topology.md).

## Supported Topology Model

The repository is currently aligned to the following logical node classes:

- `bastion`
- `load_balancers`
- `etcd`
- `control_plane`
- `workers`
- `k8s_cluster`
- `cluster_nodes`
- `services`

The canonical groups are enforced both by Ansible inventory validation in [`script/modules/ansible.sh`](script/modules/ansible.sh) and by preflight assertions in [`ansible/site.yml`](ansible/site.yml).

Important current constraints:

- `control_plane` must contain at least one host.
- `workers` must contain at least one host.
- when `external_etcd_enabled=true`, the current implementation requires exactly three dedicated `etcd` hosts
- when more than one control-plane node is present and `loadbalancer_enabled=true`, at least one `load_balancers` host is required
- the primary playbook entrypoint is [`ansible/site.yml`](ansible/site.yml); there is no current `site.yaml` playbook in this repository

A working example inventory is provided in [`ansible/inventories/proxmox/hosts.example.ini`](ansible/inventories/proxmox/hosts.example.ini).

## Prerequisites

Operators should have the following tools available on the machine running the automation:

- Terraform
- Ansible and `ansible-playbook`
- SSH access to all provisioned hosts
- access credentials for the selected Terraform platform

Additional runtime assumptions reflected in the current codebase:

- target hosts are configured for containerd, not Docker
- kubeadm is the cluster bootstrap mechanism
- external etcd is the modeled HA datastore path
- Linux hosts must permit the baseline OS preparation in the `common`, `containerd`, and `k8s` roles

## Operator Entrypoints

There are three practical operator entrypoints in the repository:

### 1. Preferred workflow wrapper

[`script/main.sh`](script/main.sh) is the main maintained shell entrypoint.

Examples:

```bash
./script/main.sh proxmox plan
./script/main.sh proxmox apply --auto-approve
./script/main.sh aws ansible --playbook site.yml
./script/main.sh both health --verbose
```

Supported high-level actions include infrastructure lifecycle, Ansible-only execution, health checks, backups, updates, log collection, and troubleshooting. See [`script/main.sh`](script/main.sh) for the full CLI surface.

### 2. Make targets

[`Makefile`](Makefile) wraps [`script/main.sh`](script/main.sh) for common workflows.

Examples:

```bash
make proxmox-plan
make proxmox-apply
make aws-ansible ANSIBLE_PLAYBOOK=site.yml
make both-health
make lb-deploy-proxmox
```

The Make targets also provide targeted HAProxy operations against the `load_balancers` group.

### 3. Legacy compatibility wrapper

[`setup-k8s.sh`](setup-k8s.sh) is still present, but it exposes a smaller interface than [`script/main.sh`](script/main.sh). It should be treated as a compatibility wrapper rather than the primary operator interface.

Examples:

```bash
./setup-k8s.sh proxmox plan
./setup-k8s.sh aws apply
./setup-k8s.sh both ansible
```

## Typical Workflows

### Provision and configure a platform

1. Create the required Terraform variable files for the target platform.
2. Run a plan.
3. Apply infrastructure.
4. Allow the wrapper to use the Terraform-rendered inventory and execute [`ansible/site.yml`](ansible/site.yml).

Example with the maintained wrapper:

```bash
./script/main.sh proxmox plan
./script/main.sh proxmox apply --auto-approve
```

### Re-run Ansible against existing infrastructure

If infrastructure already exists and inventory is current:

```bash
./script/main.sh proxmox ansible --playbook site.yml
./script/main.sh aws ansible --playbook site.yml
```

### Validate connectivity and health

```bash
./script/main.sh proxmox ping
./script/main.sh proxmox health --verbose
./script/main.sh both health
```

### Run only load balancer configuration

```bash
make lb-deploy-proxmox
make lb-health-proxmox
```

These targets limit execution to the canonical `load_balancers` inventory group.

## Terraform Configuration Locations

Current platform configuration files in the repository are:

### AWS

- template/example variables: [`terraform/aws/terraform.tfvars.example`](terraform/aws/terraform.tfvars.example)
- inventory template: [`terraform/aws/inventory.tpl`](terraform/aws/inventory.tpl)

Current Make helper behavior copies the AWS example to `terraform/aws/configs.auto.tfvars`, while the legacy wrapper expects `*.auto.tfvars` files to exist in the platform directory.

### Proxmox

- non-secret example variables: [`terraform/proxmox/configs.auto.tfvars.example`](terraform/proxmox/configs.auto.tfvars.example)
- secret example variables: [`terraform/proxmox/secrets.auto.tfvars.example`](terraform/proxmox/secrets.auto.tfvars.example)
- inventory template: [`terraform/proxmox/inventory.tpl`](terraform/proxmox/inventory.tpl)

The Proxmox examples model dedicated VM groups for control plane, workers, and external etcd, plus an LXC or VM-style gateway/load-balancer node depending on the Terraform implementation.

## Inventory Generation Behavior

Terraform is expected to render `ansible/inventories/<platform>/hosts.ini` using the platform inventory templates.

Current inventory behavior to be aware of:

- both templates emit the canonical inventory groups expected by Ansible
- both templates define `external_etcd_enabled=true` and `loadbalancer_enabled=true` in `[all:vars]`
- the host variable `ip` is treated as the internal service address used by several roles and verifications
- AWS inventory entries include both `ansible_host` and `private_ip`
- Proxmox inventory entries use the rendered IP addresses directly as `ansible_host` and `ip`

Inventory details and the contract between Terraform and Ansible are documented in [`docs/inventory-topology.md`](docs/inventory-topology.md).

## Ansible Role Layout

The current role set under [`ansible/roles/`](ansible/roles/) is:

- `common` for baseline host preparation
- `containerd` for container runtime installation and configuration
- `k8s` for Kubernetes package installation and host-level prerequisites
- `loadbalancer` for HAProxy API endpoint routing
- `cert` for external-etcd and control-plane certificate staging
- `etcd` for dedicated external etcd deployment and verification
- `control_plane` for kubeadm init and control-plane joins
- `worker` for kubeadm worker joins
- `cni` for cluster network installation

The cluster no longer assumes a Docker runtime role. The current runtime path is containerd.

## Certificate Workflow

The external-etcd certificate workflow is implemented by [`ansible/roles/cert/tasks/main.yml`](ansible/roles/cert/tasks/main.yml).

At a high level:

- an etcd host is chosen as the certificate generation delegate
- kubeadm generates the shared etcd CA on that host
- kubeadm generates the `apiserver-etcd-client` certificate on that same host
- CA material is fetched back to local Ansible artifacts
- each etcd node renders a kubeadm certificate config and generates its own server, peer, and healthcheck client certificates
- the control-plane nodes receive the external etcd CA certificate plus the `apiserver-etcd-client` certificate and key

This is documented in detail in [`docs/certificate-workflow.md`](docs/certificate-workflow.md).

## Operational Caveats

Before running the automation, account for the following repository-specific caveats:

- The current Ansible topology assumes dedicated external etcd nodes rather than stacked etcd.
- The default sample inventory under [`ansible/inventories/proxmox/hosts.example.ini`](ansible/inventories/proxmox/hosts.example.ini) and the Terraform inventory templates must stay aligned on canonical group names.
- [`script/main.sh`](script/main.sh) defaults to the playbook name `site.yml`.
- Some helper behaviors are not fully normalized across entrypoints. For example, [`Makefile`](Makefile) and [`setup-k8s.sh`](setup-k8s.sh) use different Terraform variable file conventions than some example file comments imply.
- The AWS inventory template currently hardcodes `ansible_ssh_private_key_file=~/.ssh/id_rsa`, while the Proxmox template uses a rendered absolute path.
- Health and backup workflows assume the bootstrap control-plane host is addressable as `control_plane[0]` and the dedicated etcd group is available as `etcd`.

## Documentation Map

- [`docs/architecture.md`](docs/architecture.md): architecture, component boundaries, and control flow
- [`docs/inventory-topology.md`](docs/inventory-topology.md): canonical inventory groups, generated inventory expectations, and topology contract
- [`docs/certificate-workflow.md`](docs/certificate-workflow.md): kubeadm HA external-etcd PKI workflow
- [`docs/operator-guide.md`](docs/operator-guide.md): operator usage, entrypoints, and practical workflows

## Repository Structure

```text
.
├── Makefile
├── README.md
├── setup-k8s.sh
├── ansible/
│   ├── ansible.cfg
│   ├── inventories/
│   ├── roles/
│   └── site.yml
├── docs/
├── script/
└── terraform/
```

## Contributing Documentation Changes

Documentation updates should remain aligned with the actual behavior of:

- [`ansible/site.yml`](ansible/site.yml)
- [`script/main.sh`](script/main.sh)
- [`script/modules/ansible.sh`](script/modules/ansible.sh)
- [`Makefile`](Makefile)
- [`setup-k8s.sh`](setup-k8s.sh)
- [`terraform/aws/inventory.tpl`](terraform/aws/inventory.tpl)
- [`terraform/proxmox/inventory.tpl`](terraform/proxmox/inventory.tpl)

If these implementation files change, the corresponding docs should be updated in the same change set.
