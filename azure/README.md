# Hammerspace on Azure — Terraform provisioning

Terraform port of the Hammerspace **Azure Marketplace ARM template**
(`mainTemplate`), structured identically to the AWS root: one configuration,
`deployment_mode` selects the shape, plan-time pre-flight hard-stops before
anything is created, and every VM ends up tagged with the cluster ID.

| `deployment_mode` | ARM equivalent | Deploys |
|---|---|---|
| `standalone` | `anvilConfiguration: Standalone` | Single-node Anvil + DSX node(s) |
| `ha` | `anvilConfiguration: High Availability` | 2-node HA Anvil + internal LB + DSX node(s) |
| `ha-multi-az` | — (no ARM equivalent) | 2-node HA Anvil, **one per availability zone**, zone-redundant internal LB + DSX node(s) spread over zones |
| `dsx` | `solutionDeploymentType: Add Data Services (DSX)…` | DSX node(s) joined to an **existing** cluster |

`ha` is the Azure reference design: the two Anvils in an **availability set**
(fault-domain separation inside one datacenter) behind an internal load
balancer. `ha-multi-az` keeps the same load balancer with a **zone-redundant
frontend** and pins Anvil1/Anvil2 to `anvil_zones` and the DSX nodes
round-robin over `dsx_zones` — separate datacenters, the counterpart of the
AWS `ha-multi-az`. It needs a region that has zones (`westus` does not;
pre-flight checks), cannot use a proximity placement group or
`availability_set_name` (a VM is in a set *or* a zone), and still needs the
heartbeat subnet (subnets span zones, so one serves both). Because zonal VMs
may use PremiumV2/Ultra disks — which Azure forbids on availability-set VMs —
`ha-multi-az` Anvils keep the PremiumV2 metadata disk that `ha` falls back
from.

## How Azure HA works here (vs AWS)

- The **floating cluster IP is the frontend IP of an internal Standard Load
  Balancer** on the data subnet — an HA-ports rule (all ports/protocols,
  floating IP enabled) forwards to both Anvil data NICs, and a **TCP health
  probe on 4505** steers all traffic to the *active* node. Failover is purely
  probe-driven: no cloud API calls, no route rewriting, and therefore **no
  managed identity / instance profile requirement** (the AWS runtime-IAM
  pre-flight has no Azure counterpart because the product doesn't need it).
- Each HA Anvil has **two NICs**: `eth0` (data/mgmt, in the LB pool) and
  `eth1` (heartbeat) on a **dedicated HA subnet** (`ha_subnet_name`, a /29
  not shared with anything else). The dedicated subnet is not optional on
  Azure — it is how the two Anvils **discover each other**: the image's
  Azure provisioning path has no `node_index` support, so the AWS-style
  single-NIC layout cannot pair (verified live 2026-07-28).
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
- **Existing resources**: a resource group (or `create_resource_group =
  true`), a VNet, a data subnet, and (HA) a dedicated heartbeat subnet. The
  configuration creates NICs, NSG, LB, availability sets, and VMs — not the
  network.
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
    runs from Azure Storage, not the deploying machine). The image is
    registered as the generation `image_generation` declares (default V1);
    set `V2` for a Gen2/UEFI deployment and it is staged as `<vhd>-gen2`
    alongside any V1 image of the same VHD.

  Customers can also stage the image **ahead of time**, decoupled from any
  deployment, with `scripts/stage-hammerspace-image.sh` (runs as-is in Azure
  Cloud Shell): it performs the same server-side copy + managed-image wrap
  and prints the `image_id` to use above (`-G V2` registers a Gen2 image).
  Preferred when the image will be reused across deployments — it survives
  `terraform destroy`.

  **Generation is a property of the registration, not of the VHD.** The
  Hammerspace VHD is hybrid-boot (GPT plus a populated EFI partition), so
  one blob serves both generations, but Azure accepts the generation only
  when an image is created from a VHD blob: a V1 image can never become V2
  later. Every Gen2-only size (all v6/v7 series) needs a V2 image, and v6/v7
  additionally need it published through a Compute Gallery definition that
  declares `DiskControllerTypes = "SCSI, NVMe"`, which this configuration
  does not create; a staged managed image boots Gen2 on dual-generation
  sizes such as v5.
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

Examples: `examples/ha-standard.tfvars`, `examples/ha-multi-az.tfvars`,
`examples/sa-standard.tfvars`, `examples/dsx-add-to-existing.tfvars`.

## Pre-flight validation (hard stop)

The plan fails before creating anything when:

- required variables are empty or still a `<PLACEHOLDER>` (per mode);
- the Azure CLI is not logged in;
- a chosen VM size doesn't exist (or is restricted) in the location, or a
  `Premium_LRS` disk was selected on a size without premium-storage support;
- `ha-multi-az`: the location has no availability zones, a requested zone
  doesn't exist, doesn't offer the VM size, is restricted for the
  subscription, or lacks the PremiumV2/Ultra disk SKU in use;
- the per-family vCPU quota (and the regional total) cannot fit the
  deployment;
- a chosen VM size does not support the image's generation
  (`image_generation`, default V1): Gen2-only sizes (the whole v6/v7 series,
  Mv2, ARM64, confidential-computing sizes…) reject a V1 image and Gen1-only
  sizes reject a V2 one; sizes supporting both generations pass either way;
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

- **Naming**: everything is prefixed with `name` plus a per-deployment
  5-char random tail (AWS parity — keeps each incarnation's resource IDs
  unique so activity logs never splice deployments): `<name><rand>Anvil1`,
  `<name><rand>Anvil2`, `<name><rand>Dsx1…N`, `<name><rand>NetSecGroup`, `<name><rand>LoadBalancer`,
  `<name>AnvilAvailSet` / `<name>DSXAvailSet` (not in `ha-multi-az`); hostnames `<name>Anvil`,
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
