# Hammerspace on AWS — Terraform provisioning

Terraform port of the `hs-anvil-dsx-provision` Ansible playbooks. Provisions
Hammerspace **Anvil** (metadata) and **DSX** (data-services) nodes as EC2
instances in your own AWS account — a single-node Anvil, a 2-node
High-Availability Anvil cluster (single- or cross-AZ), or extra DSX nodes for
an existing cluster.

> **Scope:** provisioning only (same as the playbooks). The configuration
> launches the instances, forms the cluster, and tags the instances. It does
> **not** configure Active Directory, DNS, shares, S3, or object storage.

## Deployment modes

One root configuration; `deployment_mode` selects the equivalent playbook:

| `deployment_mode` | Ansible equivalent | Deploys |
|---|---|---|
| `standalone` | `provision.yml` | Single-node Anvil + DSX node(s) |
| `ha` | `provision-ha.yml` | 2-node HA Anvil (single AZ) + DSX node(s), with pre-flight |
| `ha-multi-az` | `provision-ha-multi-az.yml` | 2-node HA Anvil **across two AZs** + DSX (spread) + internal NLB, stricter pre-flight |
| `dsx` | `provision-dsx.yml` | DSX node(s) **added to an existing cluster** (no Anvil), with Anvil probe + version check |

Every apply ends by tagging all created instances with the cluster ID
(`HammerspaceClusterId=<cntl uoid.uuid>`), exactly like the
`aws_tag_cluster_id` role.

## Repository layout

```
main.tf                    # mode wiring: pre-flight → SG → Anvil → wait → DSX → tag
variables.tf               # all deployment variables (mirrors group_vars/all.yml)
locals.tf                  # naming, tags, per-mode pre-flight IAM action lists
validation.tf              # cross-variable input asserts (plan-time hard stop)
outputs.tf
modules/
  preflight/               # IAM + VPC-endpoint + existing-Anvil checks  (preflight.yml)
  anvil-standalone/        # single-node Anvil                (aws_provision_anvil_node)
  anvil-ha/                # 2-node HA Anvil, single AZ       (aws_provision_anvil_ha)
  anvil-ha-multiaz/        # cross-AZ HA Anvil + NLB          (aws_provision_anvil_ha_multiaz)
  dsx/                     # DSX data-services node(s)        (aws_provision_dsx_node)
../shared/
  wait-for-api/            # wait for the mgmt API on :8443       (cloud-neutral)
  cluster-tag/             # cluster-ID tagging (aws_tag_cluster_id, cloud-neutral)
examples/                  # .tfvars ports of every Ansible example file
```

## Requirements

- **Terraform ≥ 1.6** with the `aws`, `random`, and `external` providers
  (`terraform init` fetches them).
- **AWS CLI v2 + python3 + curl + bash** on the machine running Terraform.
  They power the pre-flight checks, the cluster-IP pinning, the API wait, and
  the cluster-ID tagging — the same jobs boto3/uri tasks did on the Ansible
  control host.
- **AWS credentials** with EC2 permissions — environment variables,
  `~/.aws/credentials`, or set `aws_profile`.
- **Existing AWS resources**: a VPC, subnet(s), and (for HA) an IAM instance
  profile. An EC2 key pair is optional.
- **Hammerspace AMI** — `hs_ami` is account- and region-specific; the AMI must
  be owned by, or shared with, the deploying account.
- **Network path to the Anvil**: the post-deploy wait + cluster-ID tagging
  call `https://<anvil>:8443` from wherever Terraform runs (same requirement
  the playbooks had). If :8443 is not reachable from your machine, set
  `wait_for_cluster = false` (instances are still created; tagging is skipped).

## Quick start

```bash
terraform init

# Dry run - the equivalent of `-e dry_run=true`: every input assert and the
# full pre-flight (IAM simulate, VPC endpoints, Anvil probe) runs at plan
# time; nothing is created if any check fails.
terraform plan -var-file=examples/ha-standard.tfvars

terraform apply -var-file=examples/ha-standard.tfvars
```

Use **one state per deployment** (separate directory, or
`terraform workspace new <name>`) — a deployment here corresponds to one
Ansible run, and `terraform destroy` then tears down exactly that cluster,
including the pre-created Secondary ENI that the playbooks could only note in
a `temp_aws_resources_*` file for manual cleanup.

## Pre-flight validation (hard stop)

`terraform plan`/`apply` fails **before creating anything** when (per mode,
mirroring the `preflight.yml` variants):

- required variables are empty or still a `<PLACEHOLDER>`;
- a node is below the product minimum — Anvil 16 vCPU / 32 GiB, DSX 8 vCPU /
  16 GiB (root-level `aws_ec2_instance_type` postconditions), or a boot disk
  is under 512 GB (variable validation);
- the deploying identity is missing any required IAM action
  (`iam:SimulatePrincipalPolicy`; degrades to a warning when the simulate
  call itself is denied — same as Ansible);
- the IAM instance profile doesn't exist, or (HA modes) its role lacks the
  runtime actions (peer discovery, floating IP; multi-AZ adds the
  route-write actions);
- the VPC lacks DNS support/hostnames, or the EC2 API is unreachable from the
  deployment subnet(s): no valid `com.amazonaws.<region>.ec2` interface
  endpoint and no `0.0.0.0/0` NAT/IGW route;
- **multi-AZ**: `az1 == az2`, a subnet is not in its stated AZ/VPC, the
  cluster IP is *inside* the VPC CIDR, or a listed route table is not in the
  VPC;
- **dsx**: the existing Anvil doesn't answer 200 on `:8443` with the supplied
  credentials, or the DSX AMI's `hs_version` tag doesn't share the cluster's
  `Major.Minor` (read from its ANVIL node(s); patch/build ignored).

Advisory findings (e.g. no STS endpoint) surface as plan **warnings**.
Bypass everything with `skip_preflight = true` (not recommended).

## Notable behavior (kept from the playbooks)

- **Naming**: `anvil-1-<label>-<5char>`, `dsx-1-<label>-<5char>`; the 5-char
  random tail is generated once per state, so two deployments of the same
  label stay distinguishable. HA peer discovery resolves nodes by `tag:Name` —
  do not rename the instances.
- **Password**: the cluster admin password is the **Primary** Anvil's EC2
  instance ID (`terraform output anvil_password`).
- **Cluster-IP atomicity (ha)**: the Secondary's ENI is pre-created with the
  floating IP (auto-allocated, or pinned via `anvil_cluster_ip`) and the
  Secondary launches bound to that ENI, so the IP is in IMDS from boot
  second 0.
- **Multi-AZ**: the cluster IP is an overlay IP outside the VPC CIDR floated
  by route-table rewrites (`source_dest_check` off); an internal NLB spans
  both subnets with TCP 443 + 22 listeners (SSH health-checks port 4505 so
  SSH lands on the active node); the DSX metadata target is
  `<cluster_ip>/<anvil_cluster_ip_prefixlen>`; readiness/tagging use the
  Primary's private IP (the overlay IP isn't routable from outside the VPC).
- **Ephemeral detection**: instance types with built-in NVMe instance-store
  (`i4i.*`, `i7ie.*`, `r8id.*`, `c8id.*`, …) skip the Anvil metadata / DSX
  data EBS volumes automatically (native `aws_ec2_instance_type` lookup —
  no CLI call needed). Boot is always provisioned.
- **Metadata disks + RAID**: 1, 2, or 4 gp3 metadata disks
  (`/dev/sdb`–`/dev/sde`, 5000 IOPS default); `anvil_raid_type` maps
  stripe→`raid0`, mirror→`raid1` in `node.storage.options`.
- **Security groups**: wide open by default (`sec_ip_cidr = 0.0.0.0/0`),
  matching the playbooks/CFT — tighten for any non-lab use. Supply
  `security_group_id` to reuse an existing group. The DSX-only mode creates
  its own `-dsx` group (port set still the upstream wide-open placeholder).
- Storage defaults: every EBS volume is `gp3` / 1024 GB, metadata volumes at
  5000 IOPS — override per deployment in your `.tfvars`.

## Differences from the Ansible version

- **State replaces tracking files**: `temp_aws_resources_*` / `temp_dsx_ips_*`
  are gone; instance IDs and DSX IPs are Terraform outputs, and `destroy`
  cleans up everything (including the HA Secondary ENI).
- **Dry run** is `terraform plan` instead of `-e dry_run=true`.
- **Changing config after deploy**: user-data (cluster config) changes force
  instance replacement — Terraform will tell you in the plan. The playbooks
  simply created new instances each run; here the same config re-applied is a
  no-op.
- `subnet_private` existed in `group_vars/all.yml` but was never used by the
  roles, so it has no Terraform counterpart.
- IMDSv2 (`http_tokens = "required"`) is set on **all** instances, including
  standalone (the playbooks set it everywhere except standalone).
- DSX volume syntax is flattened: `{ device_name, volume_type, volume_size,
  iops, throughput, encrypted, kms_key_id, delete_on_termination }` instead
  of the nested `ebs:` block.

## Outputs

`anvil_ip`, `anvil_password` (sensitive), `management_url` (NLB URL for
multi-AZ), `anvil_instance_ids`, `dsx_instance_ids`, `dsx_private_ips`,
`security_group_id`, `name_suffix`, `preflight_warnings`.

## License

Internal / private — see the repository owner.
