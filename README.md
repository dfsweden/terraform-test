# Hammerspace — Terraform provisioning (multi-cloud)

Terraform automation that provisions Hammerspace **Anvil** (metadata) and
**DSX** (data-services) nodes in your own cloud account. Each cloud is its own
root configuration with its own state and its own vocabulary; the pipeline
shape is identical everywhere:

**plan-time pre-flight (hard stop) → security group/NSG → Anvil → DSX →
wait for the cluster API → tag everything with the cluster ID.**

> **Scope:** provisioning only. The configurations launch the instances, form
> the cluster, and tag the instances. They do **not** configure Active
> Directory, DNS, shares, S3, or object storage.

## Repository layout

```
aws/          # port of the hs-anvil-dsx-provision Ansible playbooks
              #   modes: standalone | ha | ha-multi-az | dsx
azure/        # port of the Azure Marketplace ARM template (mainTemplate)
              #   modes: standalone | ha | dsx   (no multi-az - see below)
shared/       # cloud-neutral modules used by both roots
  wait-for-api/   # wait for the Hammerspace mgmt API on :8443
  cluster-tag/    # read the cluster ID over REST, tag via a per-cloud CLI command
```

Run Terraform from inside `aws/` or `azure/` — never from this directory.
Use **one state per deployment** (separate directory copy or workspace); a
deployment corresponds to one Ansible run / one ARM deployment, and
`terraform destroy` tears down exactly that cluster.

```bash
cd aws     # or azure
terraform init
terraform plan  -var-file=examples/<example>.tfvars   # dry run: full pre-flight, creates nothing
terraform apply -var-file=examples/<example>.tfvars
```

## Why the clouds differ (same product, different HA plumbing)

| | AWS (`aws/`) | Azure (`azure/`) |
|---|---|---|
| Reference | CloudFormation template / Ansible playbooks | Marketplace ARM template |
| HA cluster IP | Secondary private IP on the Anvil ENI (single-AZ) or overlay IP + route rewriting (multi-AZ) | **Internal Standard Load Balancer** frontend IP, HA-ports rule + floating IP, TCP 4505 probe picks the active node |
| HA network | One eth0 (data+mgmt+ha) | eth0 (data/mgmt) + **eth1 on a dedicated HA subnet** |
| Cross-AZ | `ha-multi-az` mode (overlay IP, NLB, route tables) | Not applicable — availability set (fault domains) covers the reference design |
| Runtime cloud IAM | Instance profile (peer discovery, IP moves, route writes) | **None needed** — failover is LB-probe-driven |
| Admin password | The Primary Anvil's EC2 instance ID | Your `admin_password`, applied via the `hs-init-admin-pw` extension |
| Image | `hs_ami` (AMI with `hs_version` tag) | `image_id` (managed/SIG image) or Marketplace image + plan |
| Security | Wide-open SG (upstream placeholder) | NSG with the explicit Hammerspace port set |
| Ephemeral NVMe types | Auto-detected; metadata/data EBS skipped | Not in the reference design (no L-series sizes) |

Both clouds boot nodes with the **same provisioning JSON** (user data /
custom data — one schema in the product's `pd/prov/schema.py`), wait on the
same `:8443` REST API, and tag with the same `HammerspaceClusterId`.

## Prerequisites (both clouds)

- Terraform ≥ 1.6, python3, curl, bash on the machine running Terraform
- The cloud CLI: `aws` (AWS) / `az`, logged in (Azure)
- Network path from this machine to the Anvil's `:8443` for the post-deploy
  wait + cluster-ID tagging (set `wait_for_cluster = false` if unavailable)

See `aws/README.md` and `azure/README.md` for the cloud-specific details,
variables, and examples.

## License

Internal / private — see the repository owner.
