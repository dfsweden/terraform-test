# Hammerspace on Azure — Terraform provisioning

Terraform port of the Hammerspace **Azure Marketplace ARM template**
(`mainTemplate`), structured identically to the AWS root: one configuration,
`deployment_mode` selects the shape, plan-time pre-flight hard-stops before
anything is created, and every VM ends up tagged with the cluster ID.

| `deployment_mode` | ARM equivalent | Deploys |
|---|---|---|
| `standalone` | `anvilConfiguration: Standalone` | Single-node Anvil + DSX node(s) |
| `ha` | `anvilConfiguration: High Availability` | 2-node HA Anvil + internal LB + DSX node(s) |
| `dsx` | `solutionDeploymentType: Add Data Services (DSX)…` | DSX node(s) joined to an **existing** cluster |

There is **no multi-az mode**: the Azure reference design places the two
Anvils in an **availability set** (fault-domain separation) behind an internal
load balancer — availability zones are not part of the design.

## How Azure HA works here (vs AWS)

- The **floating cluster IP is the frontend IP of an internal Standard Load
  Balancer** on the data subnet — an HA-ports rule (all ports/protocols,
  floating IP enabled) forwards to both Anvil data NICs, and a **TCP health
  probe on 4505** steers all traffic to the *active* node. Failover is purely
  probe-driven: no cloud API calls, no route rewriting, and therefore **no
  managed identity / instance profile requirement** (the AWS runtime-IAM
  pre-flight has no Azure counterpart because the product doesn't need it).
- Each HA Anvil has **two NICs**: `eth0` (data/mgmt, data subnet, in the LB
  pool) and `eth1` (heartbeat) on a **dedicated HA subnet** — a /29 not shared
  with anything else (`ha_subnet_name`).
- ARM quirk kept for fidelity: Anvil1 boots `ha_mode: Secondary`, Anvil2
  boots `ha_mode: Primary`.
- The **admin password is not the instance ID** (that's the AWS convention).
  You supply `admin_password`, and each VM's `setAdminPassword` CustomScript
  extension runs `hs-init-admin-pw`, exactly like the ARM template. The
  Hammerspace login is `admin` / `admin_password`; the OS-level
  `user<hash>` account is not used to operate the product.

## Requirements

- **Terraform ≥ 1.6** with `azurerm` (`terraform init` fetches it).
- **Azure CLI (logged in: `az login`) + python3 + curl + bash** on the machine
  running Terraform — they power the pre-flight, and the cluster-ID tagging.
- **Existing resources**: a resource group, a VNet, a data subnet, and (HA) a
  dedicated HA subnet. The configuration creates NICs, NSG, LB, availability
  sets, and VMs — not the network.
- **Hammerspace image** — exactly one of:
  - `image_id` — managed image or Shared Image Gallery version (shared by
    Hammerspace into this subscription/tenant);
  - `marketplace_image` — Azure Marketplace (requires the offer's terms
    accepted on the subscription; see
    `az vm image list --publisher hammerspace --all` for live offers/SKUs);
  - `image_sas_url` — a read-only blob SAS URL to a Hammerspace `.vhd`, for
    customer sites with no access to Hammerspace resources. The VHD is
    copied server-side into a staging storage account in the resource group
    and wrapped in a managed image on the first apply (the redundant `.vhd`
    blob is deleted once the self-contained image exists); the image
    **persists across `terraform destroy`** (create-only staging), so product
    apply/destroy cycles never re-download (see
    `examples/sa-customer-sas.tfvars`; don't IP-restrict the SAS — the copy
    runs from Azure Storage, not the deploying machine).

  Customers can also stage the image **ahead of time**, decoupled from any
  deployment, with `scripts/stage-hammerspace-image.sh` (runs as-is in Azure
  Cloud Shell): it performs the same server-side copy + managed-image wrap
  and prints the `image_id` to use above. Preferred when the image will be
  reused across deployments — it survives `terraform destroy`.
- Network path to the Anvil's `:8443` for the post-deploy wait + tagging
  (`wait_for_cluster = false` to skip).

## Quick start

```bash
cd azure
terraform init

# Dry run: input validation + pre-flight (az login, VM-size availability,
# premium-storage capability, image existence, dsx-mode Anvil probe) —
# creates nothing.
terraform plan -var-file=examples/ha-standard.tfvars

terraform apply -var-file=examples/ha-standard.tfvars
```

Examples: `examples/ha-standard.tfvars`, `examples/sa-standard.tfvars`,
`examples/dsx-existing.tfvars`.

## Pre-flight validation (hard stop)

The plan fails before creating anything when:

- required variables are empty or still a `<PLACEHOLDER>` (per mode);
- the Azure CLI is not logged in;
- a chosen VM size doesn't exist (or is restricted) in the location, or a
  `Premium_LRS` disk was selected on a size without premium-storage support;
- a node is below the product minimum — Anvil 16 vCPU / 32 GiB, DSX 8 vCPU /
  16 GiB (SKU capability check), or a boot disk is under 512 GB (variable
  validation);
- `image_id` can't be found or read, or `image_sas_url` is not a readable
  https page-blob SAS URL (expired/mispermissioned tokens fail here, before
  anything is created);
- **dsx**: the existing Anvil doesn't answer 200 on `:8443` with the supplied
  credentials, or (when the image carries an `hs_version` tag) its
  `Major.Minor` doesn't match the cluster's ANVIL node(s). A missing tag is a
  warning, not an error — Azure images aren't guaranteed to carry it.

There is no `iam:SimulatePrincipalPolicy` equivalent on Azure, so deployer
RBAC problems surface at apply time rather than pre-flight.

## Notable behavior (kept from the ARM template)

- **Naming**: everything is prefixed with `name` — `<name>Anvil1`,
  `<name>Anvil2`, `<name>Dsx1…N`, `<name>NetSecGroup`, `<name>LoadBalancer`,
  `<name>AnvilAvailSet` / `<name>DSXAvailSet`; hostnames `<name>Anvil`,
  `<name>Anvil-2`, `<name>Dsx<i>`; domain `<name>.azure`.
- **NSG**: one Allow rule (priority 2000) with the explicit Hammerspace port
  set from the marketplace template, attached to every NIC (the existing
  subnet's own NSG is left untouched).
- **Disks**: managed disks, inline at VM creation (the classic
  `azurerm_virtual_machine` resource is used deliberately so data disks exist
  at first boot, matching ARM). Anvil = boot + one metadata disk (lun 1);
  DSX = boot + `dsx_data_disk_count` disks, optional `raid0` striping.
  `Default` disk types resolve to `Premium_LRS` when the size supports it,
  else `StandardSSD_LRS`; `UltraSSD_LRS` enables the VM's Ultra capability.
- **Cluster/metadata IPs** in custom data carry the data subnet's prefix
  length (`<ip>/<len>`), exactly like ARM's `dataNetNum`.
- Optional per-node **public IPs** (`public_ip_addresses`, default off) and
  **proximity placement group** (`use_proximity_placement_group`).

## Outputs

`anvil_ip` (cluster IP), `management_url`, `anvil_vm_ids`, `dsx_vm_ids`,
`dsx_private_ips`, `network_security_group_id`, `os_admin_username`,
`preflight_warnings`.
