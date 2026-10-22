# ============================================================
# Hammerspace Anvil + DSX on Azure - deployment variables.
# Mirrors the Azure Marketplace ARM template
# (datasphere tools/azure/templates/mainTemplate.jinja.json).
# ============================================================

# --- Deployment mode ---
#   standalone -> single-node Anvil + DSX   (ARM: anvilConfiguration=Standalone)
#   ha         -> 2-node HA Anvil + DSX     (ARM: anvilConfiguration=High Availability)
#   ha-multi-az -> 2-node HA Anvil + DSX across availability ZONES
#                  (no ARM equivalent - the marketplace template only knows
#                  availability sets; the counterpart of the AWS root's
#                  ha-multi-az)
#   dsx        -> add DSX to an existing cluster
#                 (ARM: solutionDeploymentType=Add Data Services (DSX) ...)
#
# ha and ha-multi-az differ in PLACEMENT only: an availability set (fault
# domains inside one datacenter) versus one zone per Anvil (separate
# datacenters). Both use the same internal load balancer and the same
# dedicated heartbeat subnet - an Azure subnet spans every zone, so unlike
# the AWS root there is no per-zone subnet. Zonal placement is also what
# lets HA Anvils keep PremiumV2/Ultra metadata disks, which Azure forbids on
# availability-set VMs. It needs a region that HAS zones (westus does not).
variable "deployment_mode" {
  type        = string
  description = "Deployment shape: standalone | ha | ha-multi-az | dsx"

  validation {
    condition     = contains(["standalone", "ha", "ha-multi-az", "dsx"], var.deployment_mode)
    error_message = "deployment_mode must be one of: standalone, ha, ha-multi-az, dsx."
  }
}

variable "subscription_id" {
  type        = string
  default     = ""
  description = "Azure subscription. Empty = the Azure CLI's current subscription."

  validation {
    condition     = var.subscription_id == "" || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a GUID, or empty to use the az CLI's current subscription."
  }
}

# --- Naming ---
# ARM 'name' parameter: prefix for every created resource
# (<prefix>Anvil1, <prefix>Dsx1, <prefix>NetSecGroup, ...).
variable "name" {
  type        = string
  description = "Name prefix for created resources. Must start with a letter; alphanumerics and hyphens only."

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{2,23}$", var.name))
    error_message = "name must be 3-24 chars, start with a letter, and contain only alphanumerics and hyphens."
  }
}

# --- Existing resources (the deployment does NOT create the network) ---
variable "resource_group" {
  type        = string
  description = "Existing resource group all new resources are created in."

  validation {
    condition     = length(trimspace(var.resource_group)) > 0 && !startswith(trimspace(var.resource_group), "<")
    error_message = "resource_group must be set (not empty, not a <PLACEHOLDER>)."
  }
}

variable "location" {
  type        = string
  default     = ""
  description = "Azure location. Empty = the resource group's location."

  validation {
    # Azure region names are lower-case and unspaced ("westus", not "West US").
    condition     = var.location == "" || can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be an Azure region short name such as westus (lower case, no spaces), or empty to inherit the resource group's."
  }
}

variable "virtual_network_name" {
  type        = string
  description = "Existing virtual network name."

  validation {
    condition     = length(trimspace(var.virtual_network_name)) > 0 && !startswith(trimspace(var.virtual_network_name), "<")
    error_message = "virtual_network_name must be set (not empty, not a <PLACEHOLDER>)."
  }
}

variable "virtual_network_resource_group" {
  type        = string
  default     = ""
  description = "Resource group of the VNet, when different from resource_group."

  validation {
    condition     = var.virtual_network_resource_group == "" || can(regex("^[-\\w._()]{1,90}$", var.virtual_network_resource_group))
    error_message = "virtual_network_resource_group must be a valid Azure resource group name (1-90 chars), or empty to use the deployment's."
  }
}

variable "data_subnet_name" {
  type        = string
  description = "Existing data subnet in the virtual network (all nodes' eth0)."

  validation {
    condition     = length(trimspace(var.data_subnet_name)) > 0 && !startswith(trimspace(var.data_subnet_name), "<")
    error_message = "data_subnet_name must be set (not empty, not a <PLACEHOLDER>)."
  }
}

variable "ha_subnet_name" {
  type        = string
  default     = ""
  description = <<-EOT
    ha / ha-multi-az mode: existing dedicated High-Availability heartbeat
    subnet (each Anvil gets a second NIC / eth1 there; not shared with other
    instances, a /29 recommended; a subnet spans every zone, so one serves
    both zonal Anvils). REQUIRED on Azure: the heartbeat subnet is the HA
    peer-discovery mechanism - the image's Azure provisioning path has no
    node_index support, so heartbeat-on-eth0 (the AWS layout) cannot pair.
  EOT

  validation {
    condition     = var.ha_subnet_name == "" || can(regex("^[-\\w._]{1,80}$", var.ha_subnet_name))
    error_message = "ha_subnet_name must be a valid Azure subnet name (1-80 chars). Empty is accepted only for standalone and dsx modes - ha and ha-multi-az require it, because single-NIC HA cannot pair on Azure."
  }
}

variable "network_security_group_id" {
  type        = string
  default     = ""
  description = "Existing NSG to attach to every NIC. Empty = create <name>NetSecGroup with the Hammerspace port set."

  validation {
    condition     = var.network_security_group_id == "" || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/networkSecurityGroups/[^/]+$", var.network_security_group_id))
    error_message = "network_security_group_id must be a full NSG resource ID (/subscriptions/.../networkSecurityGroups/<name>), or empty to create one."
  }
}

# --- Image ---
# Either a managed/Shared Image Gallery image ID (image_id - the equivalent
# of hs_ami), or the Marketplace image (marketplace_image + plan acceptance).
variable "image_id" {
  type        = string
  default     = ""
  description = "Hammerspace image resource ID (managed image or SIG image version). Obtain from Hammerspace."

  validation {
    # Managed image or gallery image version - both are absolute resource IDs.
    condition     = var.image_id == "" || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Compute/(images|galleries)/", var.image_id))
    error_message = "image_id must be a managed image or gallery image version resource ID (/subscriptions/.../Microsoft.Compute/images/<name>), or empty."
  }
}

variable "image_sas_url" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Read-only blob SAS URL to a Hammerspace .vhd (third alternative to image_id / marketplace_image, for customers without access to a shared image). The VHD is copied server-side into a staging storage account in the resource group, wrapped in a self-contained managed image named after the .vhd file (plus -gen2 when image_generation = V2), and the redundant blob copy is then deleted. The IMAGE persists across terraform destroy (create-only staging) so product apply/destroy cycles never re-download; delete it manually (az image delete) when no longer needed. NOTE: do not IP-restrict the SAS - the copy runs from Azure Storage, not from this machine; use a short expiry instead."

  validation {
    condition     = var.image_sas_url == "" || can(regex("^https://", var.image_sas_url))
    error_message = "image_sas_url must be an https blob SAS URL, or empty when image_id is used instead."
  }
}

variable "marketplace_image" {
  type = object({
    publisher = string
    offer     = string
    sku       = optional(string, "planformacc-byol")
    version   = optional(string, "latest")
  })
  default     = null
  description = "Azure Marketplace image (alternative to image_id). Requires the offer's terms to be accepted on the subscription."

  validation {
    # The object type enforces the shape; this catches empty strings, which
    # would otherwise reach ARM as a malformed purchase plan.
    #
    # A ternary, NOT `== null || ...`: terraform's || evaluates BOTH operands,
    # so values(null) still ran and broke every plan that left this at its
    # default, with "Invalid value for mapping parameter: argument must not be
    # null". The conditional operator evaluates only the branch it selects.
    condition = var.marketplace_image == null ? true : alltrue([
      for v in values(var.marketplace_image) : trimspace(v) != ""
    ])
    error_message = "marketplace_image publisher, offer, sku and version must all be non-empty when a marketplace image is used."
  }
}

# --- Credentials ---
# Unlike AWS (where the admin password becomes the Primary instance ID), the
# Azure reference deployment takes an explicit admin password and applies it
# post-boot via the hs-init-admin-pw CustomScript extension.
# In dsx mode this must be the EXISTING cluster's admin password.
variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Hammerspace 'admin' password (dsx mode: the existing cluster's password)."

  # Checked by preconditions in validation.tf, NOT here. A failing variable
  # validation prints the offending value even when the variable is marked
  # sensitive - verified on terraform 1.9.8:
  #   var.admin_password is "Passw0rd!23"
  # A precondition reports only the condition expression, so the password
  # never reaches the console or a CI log.
}

variable "admin_username" {
  type        = string
  default     = ""
  description = "OS-level admin user name. Empty = 'user<hash>' like the ARM template (the OS account is not used to operate Hammerspace)."

  validation {
    # Azure rejects a set of reserved names outright, and the OS admin account
    # is NOT the Hammerspace product login.
    condition     = var.admin_username == "" || (can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.admin_username)) && !contains(["admin", "administrator", "root", "guest", "test", "user"], lower(var.admin_username)))
    error_message = "admin_username must be a lower-case Linux user name and must not be a name Azure reserves (admin, administrator, root, guest, test, user)."
  }
}

# --- Anvil sizing (ARM defaults) ---
variable "anvil_instance_type" {
  type = string
  # Product minimum: 16 vCPU / 32 GiB (enforced by pre-flight). D16s_v5 is
  # the current default: 16 vCPU / 64 GiB, and the newest D-series generation
  # that still boots a GEN1 image (v6 and v7 are Gen2-only, and v7 is also
  # NVMe-only, which a managed image cannot satisfy). Use an E16-series size
  # for a larger metadata cache.
  default = "Standard_D16s_v5"

  validation {
    condition     = can(regex("^Standard_[A-Za-z0-9_]+$", var.anvil_instance_type))
    error_message = "anvil_instance_type must be an Azure VM size such as Standard_D16s_v5."
  }
}

variable "anvil_boot_disk_size" {
  type        = number
  default     = 512
  description = "Anvil OS disk size. Minimum 512 GB - the boot disk must be large enough to deliver adequate IOPS."

  validation {
    condition     = var.anvil_boot_disk_size >= 512 && var.anvil_boot_disk_size <= 2048
    error_message = "anvil_boot_disk_size must be between 512 and 2048 GB (>= 512 for adequate boot-disk performance)."
  }
}

variable "anvil_boot_disk_type" {
  type        = string
  default     = "Default"
  description = "Anvil OS disk storage type. 'Default' = Premium_LRS if the instance type supports it, else StandardSSD_LRS."

  validation {
    condition     = contains(["Default", "Standard_LRS", "Premium_LRS", "StandardSSD_LRS"], var.anvil_boot_disk_type)
    error_message = "anvil_boot_disk_type must be Default, Standard_LRS, Premium_LRS, or StandardSSD_LRS."
  }
}

variable "anvil_metadata_disk_size" {
  type    = number
  default = 256

  validation {
    condition     = var.anvil_metadata_disk_size >= 100 && var.anvil_metadata_disk_size <= 65536
    error_message = "anvil_metadata_disk_size must be between 100 and 65536 GB (only Ultra disks support over 32767)."
  }
}

variable "anvil_metadata_disk_type" {
  type        = string
  default     = "PremiumV2_LRS"
  description = <<-EOT
    Anvil metadata disk storage type. Defaults to Premium SSD v2 with explicit
    IOPS (anvil_metadata_disk_iops) for metadata performance. Azure does not
    allow PremiumV2/Ultra disks on VMs in availability sets, so 'ha'
    deployments transparently FALL BACK to Premium_LRS (with a plan warning) -
    for 'ha', size the disk for IOPS (Premium_LRS 1024 GB = 5000 IOPS).
    'ha-multi-az' Anvils are zonal, not set-based, and KEEP the requested
    type with anvil_metadata_disk_iops / _throughput applied - the same disk
    a standalone Anvil gets. 'Default' = Premium_LRS if the instance type
    supports it.
  EOT

  validation {
    condition     = contains(["Default", "Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "PremiumV2_LRS", "UltraSSD_LRS"], var.anvil_metadata_disk_type)
    error_message = "anvil_metadata_disk_type must be Default, Standard_LRS, StandardSSD_LRS, Premium_LRS, PremiumV2_LRS, or UltraSSD_LRS."
  }
}

variable "anvil_metadata_disk_iops" {
  type        = number
  default     = 5000
  description = "Provisioned IOPS for the metadata disk - applied only to PremiumV2_LRS / UltraSSD_LRS (matches the AWS gp3 default of 5000)."

  validation {
    condition     = var.anvil_metadata_disk_iops >= 3000 && var.anvil_metadata_disk_iops <= 160000
    error_message = "anvil_metadata_disk_iops must be between 3000 and 160000 (PremiumV2 / Ultra limits)."
  }
}

variable "anvil_metadata_disk_throughput" {
  type        = number
  default     = 300
  description = "Provisioned throughput (MB/s) for the metadata disk - applied only to PremiumV2_LRS / UltraSSD_LRS."

  validation {
    condition     = var.anvil_metadata_disk_throughput >= 125 && var.anvil_metadata_disk_throughput <= 4000
    error_message = "anvil_metadata_disk_throughput must be between 125 and 4000 MB/s (PremiumV2 / Ultra limits)."
  }
}

# --- Cluster IP ---
# ha mode: static frontend IP for the internal load balancer (the floating
# cluster IP). standalone: static private IP for the Anvil NIC.
# Empty = dynamically allocated, like the ARM template's default.
variable "anvil_data_cluster_ip" {
  type        = string
  default     = ""
  description = <<-EOT
    Optional static cluster IP on the data subnet. Empty = dynamic.

    FIXED AT DEPLOYMENT: this reaches the node only through custom_data, which
    Hammerspace reads once at first boot and hs-vm ignores on update. Changing
    it later is a no-op - rebuild the node.
  EOT

  validation {
    # Reaches the node's network config; both checks are needed because a
    # dotted-quad regex accepts 999.1.1.1 and cidrhost accepts prefixed forms.
    condition = var.anvil_data_cluster_ip == "" || (
      can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", var.anvil_data_cluster_ip)) && can(cidrhost("${var.anvil_data_cluster_ip}/32", 0))
    )
    error_message = "anvil_data_cluster_ip must be a bare IPv4 address such as 10.0.1.100 - no prefix length - or empty to auto-assign."
  }
}

# --- DSX sizing (ARM defaults) ---
variable "dsx_count" {
  type    = number
  default = 1

  validation {
    condition     = var.dsx_count >= 0
    error_message = "dsx_count must be >= 0."
  }
}

variable "dsx_instance_type" {
  type        = string
  default     = "Standard_D8s_v5"
  description = "DSX VM size. Product minimum is 8 vCPU / 16 GiB - enforced by pre-flight."

  validation {
    condition     = can(regex("^Standard_[A-Za-z0-9_]+$", var.dsx_instance_type))
    error_message = "dsx_instance_type must be an Azure VM size such as Standard_D8s_v5."
  }
}

variable "dsx_boot_disk_size" {
  type        = number
  default     = 512
  description = "DSX OS disk size. Minimum 512 GB - the boot disk must be large enough to deliver adequate IOPS."

  validation {
    condition     = var.dsx_boot_disk_size >= 512 && var.dsx_boot_disk_size <= 2048
    error_message = "dsx_boot_disk_size must be between 512 and 2048 GB (>= 512 for adequate boot-disk performance)."
  }
}

variable "dsx_boot_disk_type" {
  type    = string
  default = "Default"

  validation {
    condition     = contains(["Default", "Standard_LRS", "Premium_LRS", "StandardSSD_LRS"], var.dsx_boot_disk_type)
    error_message = "dsx_boot_disk_type must be Default, Standard_LRS, Premium_LRS, or StandardSSD_LRS."
  }
}

variable "dsx_data_disk_count" {
  type        = number
  default     = 1
  description = "Data disks per DSX node."

  validation {
    condition     = var.dsx_data_disk_count >= 0 && var.dsx_data_disk_count <= 64
    error_message = "dsx_data_disk_count must be between 0 and 64."
  }
}

variable "dsx_data_disk_size" {
  type        = number
  default     = 256
  description = "Size in GB of EACH DSX data disk."

  validation {
    condition     = var.dsx_data_disk_size >= 4 && var.dsx_data_disk_size <= 32767
    error_message = "dsx_data_disk_size must be between 4 and 32767 GiB (Azure managed disk limits)."
  }
}

variable "dsx_data_disk_type" {
  type        = string
  default     = "Default"
  description = "DSX data disk type. PremiumV2/Ultra fall back to Premium_LRS except in ha-multi-az: in every other mode the DSX VMs sit in an availability set, which Azure forbids for those disk types; zonal DSX nodes keep the requested type."

  validation {
    condition     = contains(["Default", "Standard_LRS", "Premium_LRS", "StandardSSD_LRS", "PremiumV2_LRS", "UltraSSD_LRS"], var.dsx_data_disk_type)
    error_message = "dsx_data_disk_type must be Default, Standard_LRS, Premium_LRS, StandardSSD_LRS, PremiumV2_LRS, or UltraSSD_LRS."
  }
}

variable "dsx_data_disk_striping" {
  type        = bool
  default     = false
  description = "Stripe data across the DSX data disks within an instance (node.storage.options=raid0)."
}

# --- Placement ---
variable "public_ip_addresses" {
  type        = bool
  default     = false
  description = "Create a Standard static public IP for each node (ARM publicIPAddresses, default Disable)."
}

variable "use_proximity_placement_group" {
  type        = bool
  default     = false
  description = "Place every VM in a proximity placement group. Not with ha-multi-az: a PPG pins its members to ONE zone, the opposite of spreading the Anvils (rejected at plan)."
}

variable "proximity_placement_group_name" {
  type        = string
  default     = ""
  description = "Existing PPG name (in resource_group). Empty = create <name>PPG when enabled."

  validation {
    condition     = var.proximity_placement_group_name == "" || can(regex("^[-\\w._()]{1,80}$", var.proximity_placement_group_name))
    error_message = "proximity_placement_group_name must be a valid Azure resource name (1-80 chars)."
  }
}

variable "availability_set_name" {
  type        = string
  default     = ""
  description = "Existing availability set name to place ALL nodes in (standalone / ha / dsx - never ha-multi-az, whose VMs are zonal). Empty = create <name>AnvilAvailSet / <name>DSXAvailSet."

  validation {
    condition     = var.availability_set_name == "" || can(regex("^[-\\w._()]{1,80}$", var.availability_set_name))
    error_message = "availability_set_name must be a valid Azure resource name (1-80 chars)."
  }
}

# --- Multi-AZ (ha-multi-az mode only) ---
# Azure zones are the region-local labels "1", "2", "3" (each subscription's
# mapping to physical zones differs, so there is nothing to look up), and a
# subnet spans every zone - the data and heartbeat subnets need no per-zone
# counterpart, unlike the AWS root's subnet_az1 / subnet_az2. Membership and
# duplicates are checked here (malformed in any mode); the COUNTS depend on
# the mode and are preconditions in validation.tf.
variable "anvil_zones" {
  type        = list(string)
  default     = ["1", "2"]
  description = "ha-multi-az: availability zone of each Anvil, in node order (Anvil1, Anvil2). Exactly two DIFFERENT zones. Ignored in every other mode."

  validation {
    condition     = alltrue([for z in var.anvil_zones : contains(["1", "2", "3"], z)])
    error_message = "every anvil_zones entry must be an Azure availability zone: \"1\", \"2\" or \"3\"."
  }

  validation {
    condition     = length(distinct(var.anvil_zones)) == length(var.anvil_zones)
    error_message = "anvil_zones lists the same zone twice - the two Anvils must be in DIFFERENT zones, or there is nothing left to survive a zone loss."
  }
}

variable "dsx_zones" {
  type        = list(string)
  default     = []
  description = <<-EOT
    ha-multi-az and dsx modes: zones the DSX nodes are spread across, round-robin
    in node order (Dsx1 -> [0], Dsx2 -> [1], Dsx3 -> [0], ...). ["1", "2"] puts
    one DSX beside each Anvil, like the AWS ha-multi-az example; ["1", "2", "3"]
    spreads over all three.

    REQUIRED for ha-multi-az (there is no DSX availability set in that mode).
    OPTIONAL for dsx mode, where it is how a DSX is added to a zonal cluster:
    empty keeps the availability-set placement every other mode uses, and a
    non-empty list makes the nodes zonal instead - Azure allows a VM in a set OR
    a zone, never both, so setting this suppresses the set. Ignored by standalone
    and ha.

    Empty by default so adding a DSX to a NON-zonal cluster, or in a region
    without zones, keeps working unchanged.
  EOT

  validation {
    condition     = alltrue([for z in var.dsx_zones : contains(["1", "2", "3"], z)])
    error_message = "every dsx_zones entry must be an Azure availability zone: \"1\", \"2\" or \"3\"."
  }

  validation {
    condition     = length(distinct(var.dsx_zones)) == length(var.dsx_zones)
    error_message = "dsx_zones lists the same zone twice - list each zone once; the nodes are spread round-robin over the list."
  }
}

# --- Tagging ---
variable "create_resource_group" {
  type        = bool
  default     = false
  description = "Create resource_group instead of requiring it to exist (location must be set). Ownership follows creation: destroy deletes the group ONLY when Terraform created it - a pre-existing group is never touched (and pointing this at an existing group fails at apply rather than adopting it). With image_sas_url, set image_resource_group so the staged image survives the group. NEVER flip this on a live deployment: changing true->false makes the next apply DELETE the created group and everything in it - destroy first, then change it."
}

variable "image_resource_group" {
  type        = string
  default     = ""
  description = "Resource group for the SAS-staged image (auto-created by the staging script if missing). Empty = the deployment resource_group. Required when create_resource_group = true and image_sas_url is set, so destroy does not delete the reusable image."

  validation {
    condition     = var.image_resource_group == "" || can(regex("^[-\\w._()]{1,90}$", var.image_resource_group))
    error_message = "image_resource_group must be a valid Azure resource group name (1-90 chars), or empty to use the deployment's."
  }
}

variable "image_generation" {
  type        = string
  default     = "V1"
  description = "Hyper-V generation of the Hammerspace image (V1 or V2). Every chosen VM size must support it: Gen2-only sizes (all v6/v7 series, Mv2, ARM64, confidential) reject a V1 image, and Gen1-only sizes reject a V2 image. Set to V2 when deploying a Gen2 (UEFI) image. With image_sas_url it also selects the generation the staged image is REGISTERED as (the VHD is hybrid-boot, so the same blob serves both); with image_id it must match how that image was registered."
  validation {
    condition     = contains(["V1", "V2"], var.image_generation)
    error_message = "image_generation must be V1 or V2."
  }
}

variable "boot_diagnostics" {
  type        = bool
  default     = false
  description = "Capture boot diagnostics (serial console/boot log) for every VM in a small LRS storage account - the only way to see why a node never came up. Off by default; turn on when troubleshooting deployments."
}

variable "cluster_api_wait_retries" {
  type        = number
  default     = 120
  description = "Attempts (x10s) the post-deploy tagging waits for the management API. 120 = 20 minutes."

  validation {
    condition     = var.cluster_api_wait_retries >= 1 && var.cluster_api_wait_retries <= 1000
    error_message = "cluster_api_wait_retries must be between 1 and 1000 (each retry waits 10s; 120 = 20 minutes)."
  }
}

variable "anvil_node_ips" {
  type        = list(string)
  default     = []
  description = "ha mode: optional static private IPs for the two Anvil data NICs (in node order); empty = dynamic."

  validation {
    condition = alltrue([
      for i in var.anvil_node_ips : can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", i)) && can(cidrhost("${i}/32", 0))
    ])
    error_message = "every anvil_node_ips entry must be a bare IPv4 address."
  }
}

variable "dsx_static_ips" {
  type        = list(string)
  default     = []
  description = "Optional static private IPs for the DSX nodes (in order); nodes beyond the list length get dynamic IPs."

  validation {
    condition = alltrue([
      for i in var.dsx_static_ips : can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", i)) && can(cidrhost("${i}/32", 0))
    ])
    error_message = "every dsx_static_ips entry must be a bare IPv4 address."
  }
}

variable "owner" {
  type        = string
  description = <<-EOT
    'owner' tag value, applied to every resource. REQUIRED: Hammerspace IT
    automation stops VMs that carry no owner, and a customer deployment with
    nobody's name on it is nobody's to clean up. It used to default to a
    personal name, which silently made every external deployment look like
    that person's.
  EOT

  validation {
    condition     = length(trimspace(var.owner)) > 0 && !startswith(trimspace(var.owner), "<")
    error_message = "owner must be set to a real person or team (not empty, not a <PLACEHOLDER>) - it is the tag IT automation uses to decide whose VMs these are."
  }

  validation {
    condition     = length(var.owner) <= 256
    error_message = "owner is used as an Azure tag value and must be 256 characters or fewer."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags for every created resource (merged with the built-in product and owner tags, like the ARM template)."

  validation {
    # Azure caps tags at 50 per resource, keys at 512 and values at 256 chars.
    condition = length(var.tags) <= 50 && alltrue([
      for k, v in var.tags : length(k) <= 512 && length(v) <= 256
    ])
    error_message = "tags must have 50 or fewer entries, keys of 512 characters or fewer and values of 256 characters or fewer."
  }
}

# --- Existing cluster (dsx mode) ---
variable "anvil_ip" {
  type        = string
  default     = ""
  description = "dsx mode: the EXISTING cluster's (Anvil / cluster) IP the DSX joins."

  validation {
    condition = var.anvil_ip == "" || (
      can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", var.anvil_ip)) && can(cidrhost("${var.anvil_ip}/32", 0))
    )
    error_message = "anvil_ip must be the IPv4 address of the existing cluster (dsx mode), or empty."
  }
}

variable "hsuser" {
  type    = string
  default = "admin"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.hsuser))
    error_message = "hsuser must be a plain user name - it is sent as a REST basic-auth user."
  }
}

# --- Pre-flight / post-deploy ---
variable "skip_preflight" {
  type        = bool
  default     = false
  description = "Set true ONLY to bypass the pre-flight safety checks."
}

variable "cluster_id_tag_key" {
  type    = string
  default = "HammerspaceClusterId"

  validation {
    condition     = length(var.cluster_id_tag_key) >= 1 && length(var.cluster_id_tag_key) <= 512
    error_message = "cluster_id_tag_key must be 1-512 characters (the Azure tag key limit)."
  }
}

variable "wait_for_cluster" {
  type        = bool
  default     = true
  description = <<-EOT
    After creating the VMs, wait for the cluster management API (:8443) from
    this machine and tag every VM with the cluster ID. Requires 8443 to be
    reachable from wherever terraform runs. Set false if it is not.
  EOT
}
