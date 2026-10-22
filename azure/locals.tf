locals {
  is_standalone = var.deployment_mode == "standalone"
  is_ha         = var.deployment_mode == "ha"
  is_multiaz    = var.deployment_mode == "ha-multi-az"
  is_dsx_only   = var.deployment_mode == "dsx"
  creates_anvil = !local.is_dsx_only
  # Both HA shapes: a 2-node Anvil pair behind the internal LB, paired over the
  # dedicated heartbeat subnet. They differ in PLACEMENT only - is_ha is the
  # availability-set pair, is_multiaz the zonal one - so everything the pair
  # shares keys off this, and only set/zone logic looks at the two. is_ha keeps
  # meaning exactly "ha": a site left on it by mistake keeps availability-set
  # behaviour OFF for multi-az, which is the safe direction.
  is_ha_pair = local.is_ha || local.is_multiaz

  # <name> + per-deployment 5-char random tail (AWS parity): makes every
  # incarnation's resource IDs unique, so Azure activity logs and monitoring
  # never splice two deployments' histories together.
  prefix   = "${var.name}${random_string.run_suffix.result}"
  location = var.location != "" ? var.location : one(data.azurerm_resource_group.this[*].location)
  # ARM: domain = concat(name, '.azure')
  domain = "${local.prefix}.azure"

  # ARM: adminUsername = concat('user', uniqueString(name)). The OS account is
  # not used to operate Hammerspace - hs-init-admin-pw sets the product login.
  admin_username = var.admin_username != "" ? var.admin_username : "user${substr(sha1(lower(local.prefix)), 0, 13)}"

  vnet_resource_group = var.virtual_network_resource_group != "" ? var.virtual_network_resource_group : var.resource_group

  # ARM: builtinTags = {product: <brand>} union user tags. owner is always
  # present (IT automation stops VMs without it); var.tags may override it.
  tags = merge(
    { product = "Hammerspace" },
    { for k, v in { owner = var.owner } : k => v if trimspace(v) != "" },
    var.tags,
  )

  # --- 'Default' storage-type resolution (verbatim ARM noPremiumStorage logic:
  # Premium_LRS unless the instance type cannot do premium storage) ---
  no_premium_storage = [
    "Standard_D2_v3", "Standard_D4_v3", "Standard_D8_v3", "Standard_D16_v3",
    "Standard_D32_v3", "Standard_D48_v3", "Standard_D64_v3",
    "Standard_D2a_v4", "Standard_D4a_v4", "Standard_D8a_v4", "Standard_D16a_v4",
    "Standard_D32a_v4", "Standard_D48a_v4", "Standard_D64a_v4", "Standard_D96a_v4",
    "Standard_D2_v2", "Standard_D3_v2", "Standard_D4_v2", "Standard_D5_v2",
    "Standard_E2_v3", "Standard_E4_v3", "Standard_E8_v3", "Standard_E16_v3",
    "Standard_E20_v3", "Standard_E32_v3", "Standard_E48_v3", "Standard_E64_v3",
    "Standard_E64i_v3",
    "Standard_E2a_v4", "Standard_E4a_v4", "Standard_E8a_v4", "Standard_E16a_v4",
    "Standard_E20a_v4", "Standard_E32a_v4", "Standard_E48a_v4", "Standard_E64a_v4",
    "Standard_E96a_v4",
    "Standard_D11_v2", "Standard_D12_v2", "Standard_D13_v2", "Standard_D14_v2",
    "Standard_D15_v2",
    "Standard_A2_v2", "Standard_A4_v2", "Standard_A8_v2",
    "Standard_A2m_v2", "Standard_A4m_v2", "Standard_A8m_v2",
    "Standard_H8", "Standard_H16", "Standard_H8m", "Standard_H16m",
    "Standard_H16r", "Standard_H16mr",
    "Standard_F2", "Standard_F4", "Standard_F8", "Standard_F16",
    "Basic_A3", "Basic_A4",
    "Standard_A3", "Standard_A4", "Standard_A5", "Standard_A6", "Standard_A7",
    "Standard_A8", "Standard_A9", "Standard_A10", "Standard_A11",
    "Standard_D2", "Standard_D3", "Standard_D4",
    "Standard_D11", "Standard_D12", "Standard_D13", "Standard_D14",
    "Standard_G1", "Standard_G2", "Standard_G3", "Standard_G4", "Standard_G5",
  ]

  anvil_default_storage_type = contains(local.no_premium_storage, var.anvil_instance_type) ? "StandardSSD_LRS" : "Premium_LRS"
  dsx_default_storage_type   = contains(local.no_premium_storage, var.dsx_instance_type) ? "StandardSSD_LRS" : "Premium_LRS"

  anvil_os_storage_type = var.anvil_boot_disk_type == "Default" ? local.anvil_default_storage_type : var.anvil_boot_disk_type
  dsx_os_storage_type   = var.dsx_boot_disk_type == "Default" ? local.dsx_default_storage_type : var.dsx_boot_disk_type

  # --- High-performance metadata/data disks + the availability-set rule ---
  # Azure forbids PremiumV2/Ultra disks on VMs in availability sets. The
  # standalone Anvil is NOT placed in a set (pointless for a single VM), so
  # PremiumV2 metadata works there. ha Anvils and DSX nodes need the set for
  # anti-affinity, so PremiumV2/Ultra requests FALL BACK transparently to
  # Premium_LRS (a plan warning is raised via the check block in main.tf).
  # ha-multi-az VMs are zonal - Azure allows a VM in a set OR a zone, never
  # both - so PremiumV2/Ultra work there too, as zonal disks in the VM's zone.
  # Only the set-based shapes fall back: ha Anvils, and DSX nodes in every
  # mode but ha-multi-az.
  perf_disk_types = ["PremiumV2_LRS", "UltraSSD_LRS"]

  anvil_meta_requested    = var.anvil_metadata_disk_type == "Default" ? local.anvil_default_storage_type : var.anvil_metadata_disk_type
  anvil_meta_fallback     = local.is_ha && contains(local.perf_disk_types, local.anvil_meta_requested)
  anvil_meta_storage_type = local.anvil_meta_fallback ? "Premium_LRS" : local.anvil_meta_requested

  dsx_data_requested    = var.dsx_data_disk_type == "Default" ? local.dsx_default_storage_type : var.dsx_data_disk_type
  dsx_data_fallback     = !local.is_multiaz && contains(local.perf_disk_types, local.dsx_data_requested)
  dsx_data_storage_type = local.dsx_data_fallback ? "Premium_LRS" : local.dsx_data_requested

  # The data subnet's IPv4 CIDR. Selected by family rather than taking
  # address_prefixes[0]: on a dual-stack subnet Azure may list the IPv6 prefix
  # first, and everything below (prefix length in custom data, the containment
  # checks) is IPv4 arithmetic.
  _ipv4_prefixes   = [for p in data.azurerm_subnet.data.address_prefixes : p if !strcontains(p, ":")]
  data_subnet_cidr = length(local._ipv4_prefixes) > 0 ? local._ipv4_prefixes[0] : "0.0.0.0/32"

  # Prefix length of the data subnet CIDR - appended to the cluster/metadata
  # IP in custom data (ARM dataNetNum).
  data_subnet_prefixlen = split("/", local.data_subnet_cidr)[1]

  # --- Every static IP the operator can pin, checked against that subnet ---
  #
  # These were validated as bare IPv4 literals and nothing more, so an address
  # from the wrong subnet passed the plan and failed at apply, once the NIC was
  # already being created. data.azurerm_subnet.data is a ROOT data source with
  # no depends_on, so its address_prefixes resolve at PLAN and the check is
  # expressible here - it was simply missing.
  pinned_ips = concat(
    [for i, ip in var.anvil_node_ips : { name = "anvil_node_ips[${i}]", ip = trimspace(ip) }],
    [for i, ip in var.dsx_static_ips : { name = "dsx_static_ips[${i}]", ip = trimspace(ip) }],
    trimspace(var.anvil_data_cluster_ip) != ""
    ? [{ name = "anvil_data_cluster_ip", ip = trimspace(var.anvil_data_cluster_ip) }]
    : [],
  )

  _subnet_first = (
    tonumber(split(".", cidrhost(local.data_subnet_cidr, 0))[0]) * 16777216
    + tonumber(split(".", cidrhost(local.data_subnet_cidr, 0))[1]) * 65536
    + tonumber(split(".", cidrhost(local.data_subnet_cidr, 0))[2]) * 256
    + tonumber(split(".", cidrhost(local.data_subnet_cidr, 0))[3])
  )
  _subnet_size = pow(2, 32 - tonumber(local.data_subnet_prefixlen))

  _pinned_ip_nums = {
    for p in local.pinned_ips : p.name => (
      tonumber(split(".", p.ip)[0]) * 16777216
      + tonumber(split(".", p.ip)[1]) * 65536
      + tonumber(split(".", p.ip)[2]) * 256
      + tonumber(split(".", p.ip)[3])
    )
  }

  pinned_ips_outside_subnet = [
    for name, n in local._pinned_ip_nums : name
    if n < local._subnet_first || n >= local._subnet_first + local._subnet_size
  ]

  # Azure reserves five addresses in every subnet: .0 (network), .1 (default
  # gateway), .2 and .3 (Azure DNS), and the last (broadcast). Assigning one is
  # rejected at apply.
  pinned_ips_reserved = [
    for name, n in local._pinned_ip_nums : name
    if n >= local._subnet_first && n < local._subnet_first + local._subnet_size
    && (n < local._subnet_first + 4 || n >= local._subnet_first + local._subnet_size - 1)
  ]

  # Two NICs cannot share a private address; Azure rejects the second at apply.
  pinned_ips_duplicated = [
    for ip, names in { for p in local.pinned_ips : p.ip => p.name... } : ip
    if length(names) > 1
  ]

  # --- Placement objects ---
  ppg_id = (
    var.use_proximity_placement_group
    ? (var.proximity_placement_group_name != ""
      ? one(data.azurerm_proximity_placement_group.existing[*].id)
    : one(azurerm_proximity_placement_group.this[*].id))
    : null
  )

  # The standalone Anvil is deliberately NOT in an availability set (a set
  # with one VM adds nothing, and it would forbid PremiumV2 metadata disks).
  anvil_avail_set_id = (
    local.is_ha
    ? (var.availability_set_name != ""
      ? one(data.azurerm_availability_set.existing[*].id)
    : one(azurerm_availability_set.anvil[*].id))
    : null
  )

  # Zonal DSX get no availability set - a VM is in a set OR a zone, never both.
  # That is always true for ha-multi-az and true for dsx mode when dsx_zones is set.
  dsx_avail_set_id = (
    local.is_multiaz || length(local.dsx_zones) > 0
    ? null
    : (var.availability_set_name != ""
      ? one(data.azurerm_availability_set.existing[*].id)
    : one(azurerm_availability_set.dsx[*].id))
  )

  # --- Zone placement (ha-multi-az only) ---
  # Empty lists in every other mode: the modules then set zone = null on the VM
  # and its disks, i.e. today's availability-set placement, so the ha-multi-az
  # inputs are inert outside their mode (as anvil_avail_set_id is null outside
  # ha).
  anvil_zones = local.is_multiaz ? var.anvil_zones : []
  # ha-multi-az always zonal; dsx mode zonal only when the operator asks, which
  # is how a DSX joins a zonal cluster. Empty elsewhere.
  dsx_zones = (local.is_multiaz || local.is_dsx_only) && var.dsx_count > 0 ? var.dsx_zones : []

  nsg_id = var.network_security_group_id != "" ? var.network_security_group_id : one(azurerm_network_security_group.this[*].id)

  # --- Cluster facts ---
  # anvil_ip = the DSX metadata / join target and the management endpoint:
  #   standalone -> the Anvil data NIC IP
  #   ha         -> the internal load balancer frontend IP (floating cluster IP)
  #   ha-multi-az -> the same LB frontend, zone-redundant
  #   dsx        -> the existing cluster's IP, from var.anvil_ip
  anvil_ip = coalesce(
    one(module.anvil_standalone[*].anvil_ip),
    one(module.anvil_ha[*].cluster_ip),
    trimspace(var.anvil_ip) != "" ? var.anvil_ip : null,
  )

  # Endpoint the control host uses for the post-apply wait + cluster-ID
  # tagging: always the INTERNAL cluster IP - deploy from a machine with a
  # network path to the data subnet (VPN/peering), or set
  # wait_for_cluster = false when there is none.
  anvil_mgmt_endpoint = local.anvil_ip

  all_vm_ids = flatten([
    module.anvil_standalone[*].vm_id,
    module.anvil_ha[*].vm_ids,
    module.dsx[*].vm_ids,
  ])

  # Hammerspace port set from the marketplace NSG (single Allow rule, prio 2000).
  nsg_ports = [
    "22", "80", "111", "123", "137-139", "161", "443", "445", "662",
    "2049", "2224", "3049", "4379", "4505", "4506", "5405", "7789", "7790",
    "8443", "9000-9009", "9093", "9094-9099", "9200-9201", "9292",
    "9298-9299", "9399", "20048", "20491", "20492", "21064", "30048",
    "30049", "41001-41256", "50000", "51000", "52000-52008", "53000-53008",
    "53030",
  ]
}

# The per-deployment random tail behind local.prefix. It lives in state and is
# stable across applies - but ONLY while the state survives.
#
# Lose or recreate the state and a new suffix is generated, so every resource
# name changes and terraform no longer recognises the running deployment. It is
# also how a custom role name collided with its own not-yet-propagated deletion
# (HS-41971, 2026-08-08). Treat the state file as part of the deployment.
resource "random_string" "run_suffix" {
  length  = 5
  lower   = true
  upper   = false
  numeric = true
  special = false
}
