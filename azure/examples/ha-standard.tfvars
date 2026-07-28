# ============================================================
# HA Anvil + DSX on Azure - the marketplace "High Availability"
# deployment shape. Replace every <PLACEHOLDER> with values from
# your own subscription, then:
#
#   terraform plan  -var-file=examples/ha-standard.tfvars   # dry run
#   terraform apply -var-file=examples/ha-standard.tfvars
# ============================================================

deployment_mode = "ha"

# Prefix for every created resource (<name>Anvil1, <name>Dsx1, ...).
name = "hs1"

# --- Existing resources ---
resource_group       = "<YOUR_RESOURCE_GROUP>"
virtual_network_name = "<YOUR_VNET_NAME>"
# virtual_network_resource_group = ""   # set if the VNet lives elsewhere
data_subnet_name = "<YOUR_DATA_SUBNET>"
# Dedicated HA heartbeat subnet - REQUIRED. Each Anvil gets a second NIC
# (eth1) here, and the subnet is how the two Anvils DISCOVER each other.
# Must not be shared with any other instances; a /29 is recommended.
ha_subnet_name = "<YOUR_HA_SUBNET>"

# --- Hammerspace image (from Hammerspace; managed image or SIG version ID) ---
image_id = "<YOUR_HAMMERSPACE_IMAGE_ID>"
# Or deploy from the Azure Marketplace instead of image_id:
# marketplace_image = { publisher = "hammerspace", offer = "<OFFER>" }

# --- Credentials ---
# Applied via the hs-init-admin-pw extension; the Hammerspace login is
# 'admin' with this password (NOT the instance ID as on AWS).
admin_password = "<YOUR_ADMIN_PASSWORD>"

# --- Cluster IP (internal load balancer frontend) ---
anvil_data_cluster_ip = "" # empty = dynamically allocated

# --- Anvil sizing ---
anvil_instance_type  = "Standard_F16s_v2" # Anvil minimum is 16 vCPU / 32 GiB
anvil_boot_disk_size = 512                # minimum 512 GB (boot-disk performance)
# HA note: PremiumV2/Ultra metadata disks are not allowed on availability-set
# VMs, so HA falls back to Premium_LRS - size the disk for IOPS
# (Premium_LRS 1024 GB = 5000 IOPS, matching the AWS gp3 default).
anvil_metadata_disk_size = 1024

# --- DSX (product minimum: 8 vCPU / 16 GiB - enforced by pre-flight) ---
dsx_count              = 1
dsx_instance_type      = "Standard_F8s_v2"
dsx_boot_disk_size     = 512 # minimum 512 GB
dsx_data_disk_count    = 1
dsx_data_disk_size     = 256
dsx_data_disk_striping = false # true = raid0 across the data disks

# --- Placement / access ---
public_ip_addresses           = false
use_proximity_placement_group = false

tags = {
  customer = "<YOUR_PROJECT_NAME>"
  owner    = "<YOUR_NAME>"
}
