# ============================================================
# Hammerspace Anvil + DSX on Azure - Terraform port of the
# Azure Marketplace ARM template (mainTemplate), structured
# like the AWS root: pre-flight -> NSG -> Anvil -> DSX -> tag.
#
# deployment_mode: standalone | ha | ha-multi-az | dsx.
# ha is the Azure reference design: the Anvil pair in an
# availability set (fault domains) behind an internal load
# balancer. ha-multi-az keeps the load balancer (zone-redundant
# frontend) and pins each Anvil and DSX to an availability ZONE
# instead - no set, no PPG - which is also what lets HA Anvils
# keep PremiumV2/Ultra metadata disks (forbidden on set VMs).
#
# Dry run: `terraform plan` runs every input validation and the
# pre-flight without creating anything.
# ============================================================

# --- Resource group: existing by default, created on request ---
resource "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 1 : 0

  name     = var.resource_group
  location = var.location
  tags     = local.tags
}

data "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 0 : 1

  name = var.resource_group
}

locals {
  # Referencing this local (not var.resource_group) gives every resource an
  # implicit dependency on the created group.
  resource_group = var.create_resource_group ? one(azurerm_resource_group.this[*].name) : one(data.azurerm_resource_group.this[*].name)
}

data "azurerm_subnet" "data" {
  name                 = var.data_subnet_name
  virtual_network_name = var.virtual_network_name
  resource_group_name  = local.vnet_resource_group
}

# The dedicated HA heartbeat subnet, which is REQUIRED for both HA modes - see
# the precondition in validation.tf. A subnet spans every zone, so ha-multi-az
# needs no per-zone counterpart. On Azure the heartbeat subnet IS the peer
# DISCOVERY mechanism, not merely a heartbeat link: the product's Azure
# provisioning (pd/prov/azure.py) hard-codes node_idx=0 and cannot consume the
# nodes-map / node_index pattern AWS uses, so two single-NIC Anvils never pair
# (verified live 2026-07-28 - clean 60-minute run, both nodes healthy, no
# pairing). SINGLE-NIC HA IS NOT SUPPORTED YET.
#
# The count guard stays conditional rather than keying off local.is_ha alone so
# the module keeps working unchanged for a future image that does support
# node_index; today the root validation makes the subnet mandatory.
data "azurerm_subnet" "ha" {
  count = local.is_ha_pair && var.ha_subnet_name != "" ? 1 : 0

  name                 = var.ha_subnet_name
  virtual_network_name = var.virtual_network_name
  resource_group_name  = local.vnet_resource_group
}

# --- Pre-flight: hard-stops the plan before any resource is created ---
module "preflight" {
  count  = var.skip_preflight ? 0 : 1
  source = "./modules/preflight"

  mode         = var.deployment_mode
  location     = local.location
  subscription = var.subscription_id
  vm_sizes     = local.is_dsx_only ? [var.dsx_instance_type] : [var.anvil_instance_type, var.dsx_instance_type]
  premium_sizes = compact([
    contains(["Premium_LRS", "PremiumV2_LRS", "UltraSSD_LRS"], local.anvil_os_storage_type) || contains(["Premium_LRS", "PremiumV2_LRS", "UltraSSD_LRS"], local.anvil_meta_storage_type) ? var.anvil_instance_type : "",
    contains(["Premium_LRS", "PremiumV2_LRS", "UltraSSD_LRS"], local.dsx_os_storage_type) || contains(["Premium_LRS", "PremiumV2_LRS", "UltraSSD_LRS"], local.dsx_data_storage_type) ? var.dsx_instance_type : "",
  ])
  # Product minimums (hard pre-flight stops): Anvil 16 vCPU / 32 GiB,
  # DSX 8 vCPU / 16 GiB.
  anvil_size       = local.is_dsx_only ? "" : var.anvil_instance_type
  anvil_min_vcpus  = 16
  anvil_min_mem_gb = 32
  dsx_size         = var.dsx_count > 0 ? var.dsx_instance_type : ""
  dsx_min_vcpus    = 8
  dsx_min_mem_gb   = 16
  # How many of each the apply will create - the quota check needs totals,
  # not just sizes. HA is always a pair; dsx mode creates no Anvil.
  anvil_count = local.is_dsx_only ? 0 : (local.is_ha_pair ? 2 : 1)
  dsx_count   = var.dsx_count
  # ha-multi-az: every requested zone must exist in the region and offer the
  # size - and the PremiumV2/Ultra disk SKU when one is in use. Empty lists
  # outside that mode skip the zone checks entirely.
  anvil_zones          = local.anvil_zones
  dsx_zones            = local.dsx_zones
  anvil_meta_disk_type = local.is_dsx_only ? "" : local.anvil_meta_storage_type
  dsx_data_disk_type   = var.dsx_count > 0 ? local.dsx_data_storage_type : ""
  image_id             = var.image_id
  image_generation     = var.image_generation
  image_sas_url        = var.image_sas_url
  check_anvil          = local.is_dsx_only
  anvil_ip             = var.anvil_ip
  anvil_password       = var.admin_password
  hsuser               = var.hsuser
}

# PremiumV2/Ultra disks cannot live on availability-set VMs - ha-mode Anvil
# metadata and (outside ha-multi-az) DSX data disks fall back to Premium_LRS.
# Surfaced as a plan warning so the fallback is never silent. ha-multi-az
# never falls back: its VMs are zonal and take both disk types.
check "perf_disk_fallback" {
  assert {
    condition     = !local.anvil_meta_fallback
    error_message = "anvil_metadata_disk_type ${local.anvil_meta_requested} is not supported on availability-set VMs (ha mode) - falling back to Premium_LRS. For 5000 IOPS on Premium_LRS use anvil_metadata_disk_size = 1024, or use deployment_mode = \"ha-multi-az\", where zonal Anvils keep PremiumV2/Ultra."
  }
  assert {
    condition     = !(var.dsx_count > 0 && local.dsx_data_fallback)
    error_message = "dsx_data_disk_type ${local.dsx_data_requested} is not supported on availability-set VMs - falling back to Premium_LRS for the DSX data disks (ha-multi-az places the DSX nodes in zones, where PremiumV2/Ultra are allowed)."
  }
}

check "preflight_warnings" {
  assert {
    condition     = var.skip_preflight || try(module.preflight[0].warnings, "") == ""
    error_message = "PRE-FLIGHT WARNING(S) - lines marked 'NOT CHECKED' were skipped, not passed:\n${try(module.preflight[0].warnings, "")}"
  }
}

# --- Optional: build the boot image from a customer-delivered VHD SAS URL ---
# Stages the .vhd (server-side copy) into a storage account and wraps it in a
# managed image the VMs boot from. CREATE-ONLY: destroy keeps the image so
# apply/destroy cycles of the product never re-download - the idempotent
# staging script no-ops when the image exists. With create_resource_group,
# set image_resource_group (script auto-creates it) so the image lives
# outside the group that destroy deletes.
module "image_from_sas" {
  count  = var.image_sas_url != "" ? 1 : 0
  source = "./modules/image-from-vhd"

  location       = local.location
  resource_group = var.image_resource_group != "" ? var.image_resource_group : local.resource_group
  sas_url        = var.image_sas_url
  # Registered as the generation the deployment declares, so a V2 (Gen2/UEFI)
  # deployment from a SAS URL boots a V2 image and not a silently staged V1.
  hyperv_generation = var.image_generation
  tags              = local.tags

  depends_on = [terraform_data.validate_inputs, module.preflight]
}

locals {
  # The image the VMs actually boot from: staged-from-SAS image when
  # image_sas_url is set, otherwise the caller-supplied image_id
  # (marketplace_image bypasses both).
  image_id_effective = var.image_sas_url != "" ? one(module.image_from_sas[*].image_id) : var.image_id
}

# --- Network security group (ARM: <prefix>NetSecGroup) ---
# One Allow rule (priority 2000) with the Hammerspace port set - the Azure
# reference is port-scoped, unlike the AWS playbooks' wide-open placeholder.
# Attached per-NIC (the existing subnet keeps its own NSG untouched).
resource "azurerm_network_security_group" "this" {
  count = var.network_security_group_id == "" ? 1 : 0

  name                = "${local.prefix}NetSecGroup"
  location            = local.location
  resource_group_name = local.resource_group
  tags                = local.tags

  security_rule {
    name                       = "${local.prefix}NetSecGroup-rule-in-2000"
    priority                   = 2000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    destination_port_ranges    = local.nsg_ports
  }

  depends_on = [terraform_data.validate_inputs]
}

# --- Boot diagnostics (serial console/boot log for every VM) ---
resource "azurerm_storage_account" "diag" {
  count = var.boot_diagnostics ? 1 : 0

  # Prefix in the hash: multiple deployments (e.g. a dsx add) share a
  # resource group, and each needs its own diagnostics account.
  name                     = "hsdiag${substr(sha1("${local.resource_group}-${local.location}-${local.prefix}"), 0, 16)}"
  resource_group_name      = local.resource_group
  location                 = local.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = local.tags
}

locals {
  diag_storage_uri = var.boot_diagnostics ? one(azurerm_storage_account.diag[*].primary_blob_endpoint) : ""
}

# --- Placement (ARM: PPG + availability sets, fault domain count 2) ---
# ha-multi-az creates neither: its VMs are zone-pinned, a VM is in a set OR a
# zone, and a PPG cannot span zones (both rejected in validation.tf).
resource "azurerm_proximity_placement_group" "this" {
  count = var.use_proximity_placement_group && var.proximity_placement_group_name == "" ? 1 : 0

  name                = "${local.prefix}PPG"
  location            = local.location
  resource_group_name = local.resource_group
  tags                = local.tags
}

data "azurerm_proximity_placement_group" "existing" {
  count = var.use_proximity_placement_group && var.proximity_placement_group_name != "" ? 1 : 0

  name                = var.proximity_placement_group_name
  resource_group_name = local.resource_group
}

resource "azurerm_availability_set" "anvil" {
  count = local.is_ha && var.availability_set_name == "" ? 1 : 0

  name                         = "${local.prefix}AnvilAvailSet"
  location                     = local.location
  resource_group_name          = local.resource_group
  platform_fault_domain_count  = 2
  managed                      = true
  proximity_placement_group_id = local.ppg_id
  tags                         = local.tags
}

resource "azurerm_availability_set" "dsx" {
  count = var.dsx_count > 0 && !local.is_multiaz && length(local.dsx_zones) == 0 && var.availability_set_name == "" ? 1 : 0

  name                         = "${local.prefix}DSXAvailSet"
  location                     = local.location
  resource_group_name          = local.resource_group
  platform_fault_domain_count  = 2
  managed                      = true
  proximity_placement_group_id = local.ppg_id
  tags                         = local.tags
}

data "azurerm_availability_set" "existing" {
  count = var.availability_set_name != "" ? 1 : 0

  name                = var.availability_set_name
  resource_group_name = local.resource_group
}

# --- Anvil ---
module "anvil_standalone" {
  count  = local.is_standalone ? 1 : 0
  source = "./modules/anvil-standalone"

  prefix                   = local.prefix
  location                 = local.location
  resource_group           = local.resource_group
  data_subnet_id           = data.azurerm_subnet.data.id
  nsg_id                   = local.nsg_id
  image_id                 = local.image_id_effective
  marketplace_image        = var.marketplace_image
  instance_type            = var.anvil_instance_type
  boot_disk_size           = var.anvil_boot_disk_size
  boot_disk_type           = local.anvil_os_storage_type
  metadata_disk_size       = var.anvil_metadata_disk_size
  metadata_disk_type       = local.anvil_meta_storage_type
  metadata_disk_iops       = var.anvil_metadata_disk_iops
  metadata_disk_throughput = var.anvil_metadata_disk_throughput
  static_ip                = var.anvil_data_cluster_ip
  public_ip                = var.public_ip_addresses
  availability_set_id      = local.anvil_avail_set_id
  ppg_id                   = local.ppg_id
  admin_username           = local.admin_username
  admin_password           = var.admin_password
  domain                   = local.domain
  diag_storage_uri         = local.diag_storage_uri
  tags                     = local.tags

  depends_on = [terraform_data.validate_inputs, module.preflight]
}

module "anvil_ha" {
  count  = local.is_ha_pair ? 1 : 0
  source = "./modules/anvil-ha"

  prefix                   = local.prefix
  location                 = local.location
  resource_group           = local.resource_group
  data_subnet_id           = data.azurerm_subnet.data.id
  ha_subnet_id             = one(data.azurerm_subnet.ha[*].id)
  node_ips                 = var.anvil_node_ips
  subnet_prefixlen         = local.data_subnet_prefixlen
  nsg_id                   = local.nsg_id
  image_id                 = local.image_id_effective
  marketplace_image        = var.marketplace_image
  instance_type            = var.anvil_instance_type
  boot_disk_size           = var.anvil_boot_disk_size
  boot_disk_type           = local.anvil_os_storage_type
  metadata_disk_size       = var.anvil_metadata_disk_size
  metadata_disk_type       = local.anvil_meta_storage_type
  metadata_disk_iops       = var.anvil_metadata_disk_iops
  metadata_disk_throughput = var.anvil_metadata_disk_throughput
  zones                    = local.anvil_zones
  cluster_ip               = var.anvil_data_cluster_ip
  public_ip                = var.public_ip_addresses
  availability_set_id      = local.anvil_avail_set_id
  ppg_id                   = local.ppg_id
  admin_username           = local.admin_username
  admin_password           = var.admin_password
  domain                   = local.domain
  diag_storage_uri         = local.diag_storage_uri
  tags                     = local.tags

  depends_on = [terraform_data.validate_inputs, module.preflight]
}

# --- DSX node(s) ---
# Created AFTER the Anvil module, not in parallel with it.
#
# This was originally parallel, as a deliberate deviation from the ARM template's
# dependsOn: a DSX only needs the cluster IP in its custom data, and its first
# boot retries the join until the Anvil answers. Measured 2026-09-26/28, that
# trade is a losing one on Azure.
#
#   - It buys nothing real. The DSX install does not proceed until the Anvil
#     cluster is up, so the VMs just idle - the cluster is ready no sooner.
#   - It costs correctness. Two modules writing VMs, disks and attachments into
#     one resource group at the same time twice produced
#       Error: retrieving Managed Disk "...DataDisk0" ... was not found
#     on a disk Azure had created seconds earlier and logged complete. An ARM
#     read-after-create race, in ha and ha-multi-az (4 VMs plus a load balancer,
#     availability sets and heartbeat NICs); standalone, with far fewer
#     concurrent writes, was clean at 1 and at 5 DSX.
#   - And a failed apply here is not cheap. A DSX that boots without its data
#     disk latches its first boot; re-running converges terraform without
#     re-running the install, leaving a cluster that looks complete and is not.
#
# depends_on, not a value dependency. A first attempt passed the Anvil VM ids in
# as an unreferenced variable, which does NOT order anything: terraform only
# draws an edge from a resource to the variables that resource actually uses, so
# only the module's close node waited while every VM and disk inside it started
# immediately (confirmed with `terraform graph`).
#
# depends_on on a module normally carries a real cost in this tree - it defers
# EVERY data source inside that module to apply, which is how plan-time checks
# were silently lost before - but modules/dsx and modules/hs-vm contain no data
# sources at all, so there is nothing to defer here.
#
# Costs one VM creation, about 2m20s, and is inert in dsx mode where no Anvil
# module exists.
module "dsx" {
  count  = var.dsx_count > 0 ? 1 : 0
  source = "./modules/dsx"

  node_count          = var.dsx_count
  prefix              = local.prefix
  location            = local.location
  resource_group      = local.resource_group
  data_subnet_id      = data.azurerm_subnet.data.id
  nsg_id              = local.nsg_id
  image_id            = local.image_id_effective
  marketplace_image   = var.marketplace_image
  instance_type       = var.dsx_instance_type
  boot_disk_size      = var.dsx_boot_disk_size
  boot_disk_type      = local.dsx_os_storage_type
  data_disk_count     = var.dsx_data_disk_count
  data_disk_size      = var.dsx_data_disk_size
  data_disk_type      = local.dsx_data_storage_type
  data_disk_striping  = var.dsx_data_disk_striping
  metadata_ip         = local.anvil_ip
  subnet_prefixlen    = local.data_subnet_prefixlen
  public_ip           = var.public_ip_addresses
  static_ips          = var.dsx_static_ips
  availability_set_id = local.dsx_avail_set_id
  ppg_id              = local.ppg_id
  zones               = local.dsx_zones
  admin_username      = local.admin_username
  admin_password      = var.admin_password
  domain              = local.domain
  diag_storage_uri    = local.diag_storage_uri
  tags                = local.tags

  depends_on = [
    terraform_data.validate_inputs,
    module.preflight,
    module.anvil_standalone,
    module.anvil_ha,
  ]
}

# --- Wait for the cluster API, then tag every VM with the cluster ID ---
# Same aws_tag_cluster_id equivalent as on AWS; the tagging command is the
# only cloud-specific part (az tag update per VM).
module "cluster_tag" {
  count  = var.wait_for_cluster && length(local.all_vm_ids) > 0 ? 1 : 0
  source = "../shared/cluster-tag"

  endpoint     = local.anvil_mgmt_endpoint
  hsuser       = var.hsuser
  password     = var.admin_password
  triggers     = local.all_vm_ids
  wait_retries = var.cluster_api_wait_retries
  # Joined with &&, not ; - the tagging script checks the exit status of the
  # whole string, and with ; only the LAST command's status survives, so a
  # failure tagging any earlier VM would be invisible.
  tag_command = join(" && ", [
    for id in local.all_vm_ids :
    "az tag update --operation Merge --resource-id '${id}' --tags '${var.cluster_id_tag_key}=__CLUSTER_ID__' --output none"
  ])

  depends_on = [module.dsx, module.anvil_standalone, module.anvil_ha]
}
