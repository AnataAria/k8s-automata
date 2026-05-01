# Certificate Workflow for kubeadm HA with External etcd

This document describes the current certificate workflow implemented for the kubeadm high-availability control-plane topology that uses dedicated external etcd nodes.

The implementation described here is driven by [`ansible/roles/cert/tasks/main.yml`](../ansible/roles/cert/tasks/main.yml), with supporting consumers in [`ansible/roles/etcd/tasks/verify.yml`](../ansible/roles/etcd/tasks/verify.yml), [`ansible/site.yml`](../ansible/site.yml), and [`ansible/roles/control_plane/tasks/main.yml`](../ansible/roles/control_plane/tasks/main.yml).

## Why This Workflow Exists

The repository is not using stacked etcd on control-plane nodes. Instead, it models:

- a dedicated `etcd` group for external etcd members
- a separate `control_plane` group for kubeadm control-plane nodes
- control-plane access to etcd over TLS using an externally generated `apiserver-etcd-client` certificate

That means the default single-node kubeadm certificate assumptions are not enough. Certificate generation and distribution have to bridge dedicated etcd nodes and dedicated control-plane nodes.

## Main Inputs

The certificate role derives its topology from inventory and shared variables.

Important inputs include:

- `groups['etcd']`
- `groups['control_plane']`
- `cert_generation_delegate`, defaulting to `groups['etcd'][0]` through [`ansible/roles/cert/defaults/main.yml`](../ansible/roles/cert/defaults/main.yml)
- `kubeadm_artifact_dir`
- `local_artifact_dir`
- `cert_kubeadm_cert_dir`, defaulting to `/etc/kubernetes/pki`
- `etcd_cert_dir`, defaulting to `/etc/etcd/pki`

The role asserts that:

- the `etcd` group is populated
- the `control_plane` group is populated
- the certificate generation delegate is a member of the `etcd` group

## High-Level Flow

The current workflow is:

1. Select one etcd node as the certificate generation host.
2. Generate the shared etcd CA on that host with kubeadm.
3. Generate the `apiserver-etcd-client` certificate on that same host with kubeadm.
4. Fetch the shared etcd CA and the apiserver-etcd client material back to the Ansible controller artifact directories.
5. On each etcd node, render a kubeadm certificate config containing node-specific SANs.
6. On each etcd node, generate its own server, peer, and healthcheck client certificates with kubeadm.
7. Copy the generated etcd runtime certificates into the etcd service PKI directory.
8. Copy the shared etcd CA and apiserver-etcd client credentials to all control-plane nodes.

## Detailed Step-by-Step Behavior

### 1. Derive topology state

The role first sets facts for:

- `cert_etcd_hosts`
- `cert_control_plane_hosts`
- `cert_generation_host`
- `cert_etcd_kubeadm_config_path`

This ensures later tasks can apply to the correct host classes.

### 2. Prepare local and remote artifact directories

The role creates:

- local controller artifact paths under `{{ local_artifact_dir }}/pki`
- local control-plane artifact paths under `{{ local_artifact_dir }}/pki/control-plane`
- remote kubeadm PKI paths on the certificate generation host

These artifacts allow the playbook to bridge certificates between the generator host, the controller, etcd members, and control-plane nodes.

### 3. Generate the shared etcd CA

On the certificate generation host, the role runs:

- `kubeadm init phase certs etcd-ca`

This produces the shared etcd CA under `{{ cert_kubeadm_cert_dir }}/etcd/`.

This CA is then fetched back to the controller as:

- `ca.crt`
- `ca.key`

The CA key remains sensitive and is staged only because subsequent etcd member certificates are generated from the shared CA.

### 4. Generate the kube-apiserver etcd client certificate

Also on the certificate generation host, the role runs:

- `kubeadm init phase certs apiserver-etcd-client`

This produces:

- `apiserver-etcd-client.crt`
- `apiserver-etcd-client.key`

Those files are fetched back to the controller and stored in the control-plane artifact directory.

These credentials are later copied to all control-plane nodes so the kube-apiserver can connect to external etcd securely.

### 5. Prepare etcd nodes for certificate staging

Before placing material on etcd nodes, the role ensures:

- an `etcd` system group exists
- an `etcd` system user exists
- kubeadm PKI workspace directories exist
- the runtime etcd certificate directory exists with ownership `etcd:etcd`

This is necessary because the runtime certificates are ultimately installed under [`/etc/etcd/pki`](../ansible/roles/etcd/defaults/main.yml).

### 6. Copy the shared CA to all etcd nodes

The role copies the fetched shared etcd CA material from the controller to each etcd node's kubeadm PKI workspace:

- `ca.crt`
- `ca.key`

The CA key is required on each node because kubeadm is used locally on each etcd member to generate node-specific etcd certificates from the common CA.

### 7. Render node-specific kubeadm certificate configuration

For each etcd node, the role renders [`ansible/roles/cert/templates/cert-kubeadm-config.yaml.j2`](../ansible/roles/cert/templates/cert-kubeadm-config.yaml.j2) to `{{ kubeadm_artifact_dir }}/etcd-cert-kubeadm-config.yaml`.

The SAN list for each member includes unique values derived from:

- `inventory_hostname`
- `ansible_host`
- `ip`, with fallback to `access_ip` and then `ansible_host`
- `localhost`
- `127.0.0.1`

This keeps the generated etcd certificates aligned with the actual addressing used by peer traffic and health checks.

### 8. Generate per-node etcd certificates with kubeadm

On each etcd node, the role runs kubeadm phases to generate:

- etcd server certificate via `kubeadm init phase certs etcd-server --config ...`
- etcd peer certificate via `kubeadm init phase certs etcd-peer --config ...`
- etcd healthcheck client certificate via `kubeadm init phase certs etcd-healthcheck-client --config ...`

The use of a per-node config file is important because peer and server certificates need correct SAN coverage for each member.

### 9. Install runtime etcd certificate material

The role copies the kubeadm-generated files from the local kubeadm PKI workspace into the runtime etcd PKI directory with `etcd:etcd` ownership:

- `ca.crt`
- `server.crt`
- `server.key`
- `peer.crt`
- `peer.key`
- `healthcheck-client.crt`
- `healthcheck-client.key`

These are the credentials consumed by the dedicated etcd service deployment.

### 10. Stage control-plane etcd client credentials

For every control-plane node, the role ensures Kubernetes PKI directories exist and then copies:

- external etcd CA certificate to `/etc/kubernetes/pki/etcd/ca.crt`
- `apiserver-etcd-client.crt` to `/etc/kubernetes/pki/`
- `apiserver-etcd-client.key` to `/etc/kubernetes/pki/`

This is the material needed by kubeadm and the resulting kube-apiserver static pod configuration to connect to external etcd.

## How Other Parts of the Repository Use These Certificates

### etcd role verification

[`ansible/roles/etcd/tasks/verify.yml`](../ansible/roles/etcd/tasks/verify.yml) validates etcd health using:

- `ca.crt`
- `healthcheck-client.crt`
- `healthcheck-client.key`

This happens both locally per member and cluster-wide from the first etcd node.

### Site-level post-deployment verification

[`ansible/site.yml`](../ansible/site.yml) verifies external etcd health from the bootstrap control-plane node using:

- `/etc/kubernetes/pki/etcd/ca.crt`
- `/etc/kubernetes/pki/apiserver-etcd-client.crt`
- `/etc/kubernetes/pki/apiserver-etcd-client.key`

This is an important end-to-end check because it confirms the control plane can actually talk to the external etcd cluster using the staged credentials.

### Maintenance workflows

[`script/workflows/maintenance.sh`](../script/workflows/maintenance.sh) also assumes external etcd certificates are present when running:

- etcd endpoint health checks
- etcd snapshot backups

Those workflows use files under `/etc/kubernetes/pki/etcd/` and `/usr/local/bin/etcdctl` according to the current shell implementation.

## Operational Characteristics

### Certificate generation locality

The workflow intentionally mixes central and per-node generation:

- the shared CA and apiserver-etcd client certificate are generated once on the selected etcd delegate host
- etcd member server, peer, and healthcheck certificates are generated locally on each etcd node

This avoids copying node-private server and peer keys between etcd members while still preserving a common CA.

### Bootstrap ordering

The certificate role runs before:

- external etcd deployment
- kubeadm control-plane bootstrap

That ordering is required because:

- the etcd service needs its PKI at startup
- the control plane needs the external etcd CA and client credentials before `kubeadm init`

### Durability of local artifacts

The Ansible controller receives intermediate materials under `{{ local_artifact_dir }}`. By default in the sample group vars, that path resolves to `{{ playbook_dir }}/.artifacts`.

Operators should treat these artifacts as sensitive, especially when they include CA private keys.

## Important Caveats

- The current implementation is specifically aligned to external etcd, not stacked etcd.
- The workflow expects exactly three dedicated etcd hosts when `external_etcd_enabled=true` because that is asserted in [`ansible/site.yml`](../ansible/site.yml).
- The default certificate generation delegate is the first member of the `etcd` group. Reordering the group changes the delegate host.
- Addressing quality matters. If `ip`, `access_ip`, or `ansible_host` are wrong, SAN generation and etcd peer communication can fail.
- Control-plane nodes only receive the etcd CA certificate and the apiserver-etcd client certificate pair. They do not receive etcd member peer or server keys.

## What This Document Intentionally Does Not Claim

This document reflects only the current code path. It does not claim:

- automatic certificate rotation beyond the current kubeadm-generated artifacts
- support for alternate PKI backends
- support for non-kubeadm certificate issuance paths
- support for single-node or two-node external etcd topologies within the current assertions