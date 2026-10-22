# ============================================================
# HA Anvil + DSX across Azure AVAILABILITY ZONES - the counterpart of the
# AWS root's ha-multi-az. No marketplace/ARM equivalent: the template only
# knows availability sets.
#
# What differs from ha-standard.tfvars is PLACEMENT only. Each Anvil is
# pinned to its own zone (a separate datacenter), the DSX nodes are spread
# round-robin, and the internal load balancer's frontend is zone-redundant,
# so the cluster IP outlives the loss of either Anvil's zone. Same NICs, same
# heartbeat subnet (an Azure subnet spans every zone), same custom data. A
# side effect worth having: zonal VMs may use PremiumV2/Ultra disks, which
# Azure forbids on availability-set VMs - so unlike ha, the Anvils keep the
# 5000-IOPS PremiumV2 metadata disk a standalone Anvil gets.
#
# Needs a region that HAS zones (westus2, westus3, eastus, ...; westus does
# not) - pre-flight checks that, and that every zone offers the sizes.
#
# Replace every <PLACEHOLDER> with values from your own subscription, then:
#
#   terraform plan  -var-file=examples/ha-multi-az.tfvars   # dry run
#   terraform apply -var-file=examples/ha-multi-az.tfvars
# ============================================================

deployment_mode = "ha-multi-az"

# Prefix for every created resource (<name>Anvil1, <name>Dsx1, ...).
name = "hs1"

# --- Ownership (REQUIRED) ---
# Tagged onto every resource. It is how anyone - your own cloud team included -
# tells whose deployment this is and who to ask before touching it.
owner = "<YOUR_NAME>"

# --- Existing resources ---
resource_group       = "<YOUR_RESOURCE_GROUP>"
location             = "<ZONAL_REGION>" # e.g. westus2 - must have availability zones
virtual_network_name = "<YOUR_VNET_NAME>"
# virtual_network_resource_group = ""   # set if the VNet lives elsewhere
data_subnet_name = "<YOUR_DATA_SUBNET>"
# Dedicated HA heartbeat subnet - REQUIRED. Each Anvil gets a second NIC
# (eth1) here, and the subnet is how the two Anvils DISCOVER each other.
# Must not be shared with any other instances; a /29 is recommended. One
# subnet serves both zones - subnets are not zonal.
ha_subnet_name = "<YOUR_HA_SUBNET>"

# --- Zones ---
# Azure zones are the labels "1", "2", "3" - each subscription's mapping to
# physical zones differs, so there is nothing to look up.
anvil_zones = ["1", "2"] # Anvil1, Anvil2 - must differ
dsx_zones   = ["1", "2"] # Dsx1 -> 1, Dsx2 -> 2, Dsx3 -> 1, ... (["1","2","3"] spreads over all three)

# --- Hammerspace image (from Hammerspace; managed image or SIG version ID) ---
# Managed images are regional: it must live in the same region as location.
image_id = "<YOUR_HAMMERSPACE_IMAGE_ID>"
# Or deploy from the Azure Marketplace instead of image_id:
# marketplace_image = { publisher = "hammerspace", offer = "<OFFER>" }

# --- Credentials ---
# Applied via the hs-init-admin-pw extension; the Hammerspace login is
# 'admin' with this password (NOT the instance ID as on AWS).
admin_password = "<YOUR_ADMIN_PASSWORD>"

# --- Cluster IP (zone-redundant internal load balancer frontend) ---
anvil_data_cluster_ip = "" # empty = dynamically allocated

# --- Anvil sizing ---
anvil_instance_type  = "Standard_D16s_v5" # Anvil minimum is 16 vCPU / 32 GiB; must be offered in both zones
anvil_boot_disk_size = 512                # minimum 512 GB (boot-disk performance)
# Zonal Anvils do NOT fall back to Premium_LRS the way ha does: the default
# PremiumV2 metadata disk with 5000 provisioned IOPS applies as-is.
anvil_metadata_disk_size = 256

# --- DSX (product minimum: 8 vCPU / 16 GiB - enforced by pre-flight) ---
#
# RECOMMENDED for multi-AZ: deploy the Anvils FIRST with dsx_count = 0, wait for
# the cluster, then add the DSX with a second deployment using
# deployment_mode = "dsx" and dsx_zones - see examples/dsx-add-to-existing.tfvars.
#
# Two reasons. A DSX cannot finish installing until the Anvil cluster is up, so
# creating them together buys nothing. And building both at once makes two
# modules write VMs, disks and attachments into one resource group
# simultaneously, which has twice produced
#   Error: retrieving Managed Disk "...DataDisk0" ... was not found
# on a disk Azure had just created - an ARM read-after-create race. Verified
# 2026-09-28: the sequential path was clean, the parallel path was not.
#
# Creating them together still works and is simpler; prefer it only when a
# failed apply is cheap to redo. It is not always: a DSX that boots before its
# data disk is attached latches its first boot, and re-running the apply
# converges terraform without re-running the install.
dsx_count              = 2
dsx_instance_type      = "Standard_D8s_v5"
dsx_boot_disk_size     = 512 # minimum 512 GB
dsx_data_disk_count    = 1
dsx_data_disk_size     = 256
dsx_data_disk_striping = false # true = raid0 across the data disks

# --- Placement / access ---
public_ip_addresses           = false
use_proximity_placement_group = false # must stay false: a PPG cannot span zones
# availability_set_name must stay empty: zonal VMs cannot also be in a set.

tags = {
  customer = "<YOUR_PROJECT_NAME>"
}
