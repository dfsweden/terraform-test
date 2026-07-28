# ============================================================
# Hammerspace Anvil + DSX on Azure - deployment variables.
# Mirrors the Azure Marketplace ARM template
# (datasphere tools/azure/templates/mainTemplate.jinja.json).
# ============================================================

# --- Deployment mode ---
#   standalone -> single-node Anvil + DSX   (ARM: anvilConfiguration=Standalone)
#   ha         -> 2-node HA Anvil + DSX     (ARM: anvilConfiguration=High Availability)
#   dsx        -> add DSX to an existing cluster
#                 (ARM: solutionDeploymentType=Add Data Services (DSX) ...)
# There is no multi-az mode: the Azure reference design uses an availability
# set (fault domains) + an internal load balancer, not availability zones.
variable "deployment_mode" {
  type        = string
  description = "Deployment shape: standalone | ha | dsx"

  validation {
    condition     = contains(["standalone", "ha", "dsx"], var.deployment_mode)
    error_message = "deployment_mode must be one of: standalone, ha, dsx."
  }
}

variable "subscription_id" {
  type        = string
  default     = ""
  description = "Azure subscription. Empty = the Azure CLI's current subscription."
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
    ha mode: existing dedicated High-Availability heartbeat subnet (each
    Anvil gets a second NIC / eth1 there; not shared with other instances,
    a /29 recommended). REQUIRED on Azure: the heartbeat subnet is the HA
    peer-discovery mechanism - the image's Azure provisioning path has no
    node_index support, so heartbeat-on-eth0 (the AWS layout) cannot pair.
  EOT
}

variable "network_security_group_id" {
  type        = string
  default     = ""
  description = "Existing NSG to attach to every NIC. Empty = create <name>NetSecGroup with the Hammerspace port set."
}

# --- Image ---
# Either a managed/Shared Image Gallery image ID (image_id - the equivalent
# of hs_ami), or the Marketplace image (marketplace_image + plan acceptance).
variable "image_id" {
  type        = string
  default     = ""
  description = "Hammerspace image resource ID (managed image or SIG image version). Obtain from Hammerspace."
}

variable "image_sas_url" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Read-only blob SAS URL to a Hammerspace .vhd (third alternative to image_id / marketplace_image, for customers without access to a shared image). The VHD is copied server-side into a staging storage account in the resource group, wrapped in a self-contained managed image named after the .vhd file, and the redundant blob copy is then deleted. The IMAGE persists across terraform destroy (create-only staging) so product apply/destroy cycles never re-download; delete it manually (az image delete) when no longer needed. NOTE: do not IP-restrict the SAS - the copy runs from Azure Storage, not from this machine; use a short expiry instead."
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

  validation {
    condition     = length(var.admin_password) >= 12
    error_message = "admin_password must be at least 12 characters (Azure VM password policy)."
  }

  validation {
    condition     = !can(regex("[\"\\\\$`]", var.admin_password))
    error_message = "admin_password must not contain double quotes, backslashes, backticks or dollar signs (it is passed through the hs-init-admin-pw shell command, same as the ARM template)."
  }
}

variable "admin_username" {
  type        = string
  default     = ""
  description = "OS-level admin user name. Empty = 'user<hash>' like the ARM template (the OS account is not used to operate Hammerspace)."
}

# --- Anvil sizing (ARM defaults) ---
variable "anvil_instance_type" {
  type = string
  # Product minimum: 16 vCPU / 32 GiB (enforced by pre-flight). F16s_v2 is
  # the smallest premium-capable size meeting it; use an E16-series size for
  # a larger metadata cache.
  default = "Standard_F16s_v2"
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
    allow PremiumV2/Ultra disks on VMs in availability sets, so HA
    deployments transparently FALL BACK to Premium_LRS (with a plan warning) -
    for HA, size the disk for IOPS (Premium_LRS 1024 GB = 5000 IOPS).
    'Default' = Premium_LRS if the instance type supports it.
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
}

variable "anvil_metadata_disk_throughput" {
  type        = number
  default     = 300
  description = "Provisioned throughput (MB/s) for the metadata disk - applied only to PremiumV2_LRS / UltraSSD_LRS."
}

# --- Cluster IP ---
# ha mode: static frontend IP for the internal load balancer (the floating
# cluster IP). standalone: static private IP for the Anvil NIC.
# Empty = dynamically allocated, like the ARM template's default.
variable "anvil_data_cluster_ip" {
  type        = string
  default     = ""
  description = "Optional static cluster IP on the data subnet. Empty = dynamic."
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
  default     = "Standard_F8s_v2"
  description = "DSX VM size. Product minimum is 8 vCPU / 16 GiB - enforced by pre-flight."
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
}

variable "dsx_data_disk_type" {
  type        = string
  default     = "Default"
  description = "DSX data disk type. PremiumV2/Ultra fall back to Premium_LRS (DSX VMs sit in an availability set, which Azure forbids for those disk types)."

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
  type    = bool
  default = false
}

variable "proximity_placement_group_name" {
  type        = string
  default     = ""
  description = "Existing PPG name (in resource_group). Empty = create <name>PPG when enabled."
}

variable "availability_set_name" {
  type        = string
  default     = ""
  description = "Existing availability set name to place ALL nodes in. Empty = create <name>AnvilAvailSet / <name>DSXAvailSet."
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
}

variable "boot_diagnostics" {
  type        = bool
  default     = true
  description = "Capture boot diagnostics (serial console/boot log) for every VM in a small LRS storage account - the only way to see why a node never came up."
}

variable "cluster_api_wait_retries" {
  type        = number
  default     = 120
  description = "Attempts (x10s) the post-deploy tagging waits for the management API. 120 = 20 minutes."
}

variable "anvil_node_ips" {
  type        = list(string)
  default     = []
  description = "ha mode: optional static private IPs for the two Anvil data NICs (in node order); empty = dynamic."
}

variable "dsx_static_ips" {
  type        = list(string)
  default     = []
  description = "Optional static private IPs for the DSX nodes (in order); nodes beyond the list length get dynamic IPs."
}

variable "owner" {
  type        = string
  default     = "douglas"
  description = "'owner' tag value, applied to every resource - IT automation stops untagged VMs. Empty = tag key omitted entirely."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags for every created resource (merged with the built-in product and owner tags, like the ARM template)."
}

# --- Existing cluster (dsx mode) ---
variable "anvil_ip" {
  type        = string
  default     = ""
  description = "dsx mode: the EXISTING cluster's (Anvil / cluster) IP the DSX joins."
}

variable "hsuser" {
  type    = string
  default = "admin"
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
