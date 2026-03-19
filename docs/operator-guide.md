# Operator Guide

This guide documents the current operator-facing workflows and entrypoints in the repository.

## Choose the Right Entrypoint

The repository currently exposes three operator entrypoints.

### Primary entrypoint: [`script/main.sh`](../script/main.sh)

Use [`script/main.sh`](../script/main.sh) for day-to-day operations. It exposes the broadest current workflow surface and is the maintained wrapper around Terraform and Ansible.

Examples:

```bash
./script/main.sh proxmox plan
./script/main.sh proxmox apply --auto-approve
./script/main.sh aws ansible --playbook site.yml
./script/main.sh both health --verbose
```

### Convenience entrypoint: [`Makefile`](../Makefile)

Use [`make`](../Makefile) targets for shorthand execution of common workflows and targeted load balancer operations.

Examples:

```bash
make help
make proxmox-apply
make aws-ansible ANSIBLE_PLAYBOOK=site.yml
make lb-status-proxmox
```

### Compatibility entrypoint: [`setup-k8s.sh`](../setup-k8s.sh)

Use [`setup-k8s.sh`](../setup-k8s.sh) only when you need the older simplified interface.

Examples:

```bash
./setup-k8s.sh aws plan
./setup-k8s.sh proxmox apply
./setup-k8s.sh both ansible
```

It supports fewer actions than [`script/main.sh`](../script/main.sh).

## Current CLI Surface of [`script/main.sh`](../script/main.sh)

### Platforms

- `aws`
- `proxmox`
- `both`

### Primary actions

Infrastructure management:

- `plan`
- `apply`
- `destroy`
- `status`
- `clean`

Cluster operations:

- `ansible`
- `ping`
- `health`
- `backup`
- `update`

Maintenance and diagnostics:

- `logs`
- `troubleshoot`
- `maintenance`

### Common options

- `--auto-approve`
- `--debug`
- `--dry-run`
- `--verbose`
- `--quiet`
- `--playbook FILE`
- `--tags TAGS`
- `--limit HOSTS`
- `--extra-vars VARS`
- `--check`
- `--timeout SECS`
- `--retry COUNT`
- `--log-level LEVEL`

The default playbook is `site.yml`, matching [`ansible/site.yml`](../ansible/site.yml).

## Practical Workflows

### Full platform deployment

Use this when infrastructure does not exist yet.

```bash
./script/main.sh proxmox plan
./script/main.sh proxmox apply --auto-approve
```

What happens conceptually:

1. Terraform is initialized, validated, planned, and applied for the chosen platform.
2. The wrapper waits for infrastructure readiness.
3. The wrapper runs Ansible using the current playbook, which defaults to [`ansible/site.yml`](../ansible/site.yml).
4. Deployment verification and cluster readiness checks are performed.

The deployment flow is implemented in [`script/workflows/deployment.sh`](../script/workflows/deployment.sh).

### Ansible-only reconciliation

Use this when hosts already exist and the inventory is already present.

```bash
./script/main.sh proxmox ansible --playbook site.yml
./script/main.sh aws ansible --playbook site.yml
```

Use `--tags`, `--limit`, and `--extra-vars` for more focused execution where appropriate. These selections are now passed through as native `ansible-playbook` options by the maintained wrapper.

Example:

```bash
./script/main.sh proxmox ansible --tags control_plane --limit control_plane[0]
```

Note that the wrapper passes tag and limit selections into its Ansible handling path. Operators should test selective runs carefully against the repository's end-to-end assumptions.

### Connectivity checks

```bash
./script/main.sh proxmox ping
./script/main.sh aws ping
./script/main.sh both ping
```

This validates SSH and Ansible reachability against the generated inventory.

### Health checks

```bash
./script/main.sh proxmox health
./script/main.sh proxmox health --verbose
./script/main.sh both health
```

The health workflow currently checks:

- host connectivity
- disk and memory pressure indicators
- Kubernetes node readiness
- pod health
- additional API server, certificate, and etcd checks when `--verbose` is used

The implementation lives in [`script/workflows/maintenance.sh`](../script/workflows/maintenance.sh).

### Backups

```bash
./script/main.sh proxmox backup --backup-type full --auto-approve
./script/main.sh aws backup --backup-type etcd --auto-approve
./script/main.sh aws backup --backup-type config --auto-approve
```

The backup workflow can collect:

- etcd snapshots
- `/etc/kubernetes` configuration archives
- Kubernetes resource dumps

Backups are stored under [`backups/`](../backups/).

### Update workflows

```bash
./script/main.sh both update --update-type system --auto-approve
./script/main.sh both update --update-type kubernetes
```

The current shell implementation performs a pre-update backup before proceeding with updates.

### Logs and troubleshooting

Examples:

```bash
./script/main.sh both logs --action collect
./script/main.sh both troubleshoot --issue-type connectivity
```

These actions are exposed by [`script/main.sh`](../script/main.sh), even if operators may still need to inspect implementation details in the shell modules when diagnosing complex issues.

## Make Target Guide

[`Makefile`](../Makefile) wraps the shell entrypoint and also provides direct ad-hoc HAProxy operations.

### Common platform targets

AWS:

- `aws-plan`
- `aws-apply`
- `aws-destroy`
- `aws-status`
- `aws-health`
- `aws-backup`
- `aws-ansible`
- `aws-ping`

Proxmox:

- `proxmox-plan`
- `proxmox-apply`
- `proxmox-destroy`
- `proxmox-status`
- `proxmox-health`
- `proxmox-backup`
- `proxmox-ansible`
- `proxmox-ping`

Multi-platform:

- `both-plan`
- `both-apply`
- `both-destroy`
- `both-ansible`
- `both-health`

### Load balancer targets

These targets interact directly with the canonical `load_balancers` inventory group:

- `lb-deploy`
- `lb-health`
- `lb-restart`
- `lb-status`
- `lb-logs`
- `lb-config`
- `lb-ping`

Platform-specific variants such as `lb-deploy-proxmox` and `lb-health-aws` are also provided.

By default, `PLATFORM` is `proxmox`, `LB_GROUP` is `load_balancers`, and `ANSIBLE_PLAYBOOK` is `site.yml`.

## Terraform Variable File Guidance

The repository currently contains a few different conventions across scripts and examples. Operators should be aware of the real entrypoint behavior.

### AWS

Relevant files:

- example variables: [`terraform/aws/terraform.tfvars.example`](../terraform/aws/terraform.tfvars.example)
- inventory template: [`terraform/aws/inventory.tpl`](../terraform/aws/inventory.tpl)

Current behavior to note:

- `make setup-aws` copies the example to `terraform/aws/configs.auto.tfvars`
- [`setup-k8s.sh`](../setup-k8s.sh) expects at least one `*.auto.tfvars` file in the platform directory
- the AWS example file is named `terraform.tfvars.example`, not `configs.auto.tfvars.example`

Operators should verify the exact files expected by the wrapper they choose before running `plan` or `apply`.

### Proxmox

Relevant files:

- non-secret example variables: [`terraform/proxmox/configs.auto.tfvars.example`](../terraform/proxmox/configs.auto.tfvars.example)
- secret example variables: [`terraform/proxmox/secrets.auto.tfvars.example`](../terraform/proxmox/secrets.auto.tfvars.example)
- inventory template: [`terraform/proxmox/inventory.tpl`](../terraform/proxmox/inventory.tpl)

Current behavior to note:

- `make setup-proxmox` copies the example files into `configs.auto.tfvars` and `secrets.auto.tfvars`
- comments inside the example files may not perfectly match the current wrapper behavior

## Inventory and Playbook Expectations

Before running any Ansible-backed workflow, ensure:

- the inventory exists at `ansible/inventories/<platform>/hosts.ini`
- the inventory contains the canonical groups documented in [`docs/inventory-topology.md`](inventory-topology.md); maintained shell workflows now fail fast when those canonical groups are missing
- `control_plane_endpoint` is defined through inventory or group vars
- the intended playbook exists under `ansible/`, with `site.yml` as the default and current primary entrypoint

There is no active repository path using `ansible/playbooks/site.yaml`.

## Runtime Assumptions for Operators

Current operator-facing assumptions in the repository include:

- target nodes are prepared for containerd, not Docker
- external etcd is part of the intended HA topology
- at least one worker node is required by the current playbook assertions
- `control_plane[0]` serves as the bootstrap control-plane node for join generation, verification, and some maintenance actions
- HAProxy operations expect hosts in `load_balancers`

## Major Caveats

- Not every wrapper exposes the same features. Prefer [`script/main.sh`](../script/main.sh) unless there is a specific reason to use another entrypoint.
- Wrapper behavior around Terraform variable file naming is not perfectly uniform.
- The inventory generated by Terraform is part of the runtime contract. If it drifts from the canonical Ansible group names, the deployment can fail or behave unexpectedly.
- Selective Ansible execution with custom limits and tags can bypass assumptions made by the end-to-end workflow.
- Backup and health workflows assume the external etcd topology is present, correctly grouped, and using the `/etc/etcd/pki` runtime certificate layout.

## Recommended Operator Sequence

For the least ambiguous current workflow:

1. prepare platform Terraform variable files
2. run [`./script/main.sh <platform> plan`](../script/main.sh)
3. run [`./script/main.sh <platform> apply --auto-approve`](../script/main.sh)
4. validate with [`./script/main.sh <platform> health --verbose`](../script/main.sh)
5. use targeted Make or Ansible-only workflows only after the baseline deployment is working

This sequence best matches the repository's current control flow and validation logic.