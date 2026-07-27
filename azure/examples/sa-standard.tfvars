# ============================================================
# Standalone Anvil + DSX on Azure - the marketplace "Standalone"
# deployment shape.
#
#   terraform apply -var-file=examples/sa-standard.tfvars
# ============================================================

deployment_mode = "standalone"

name = "hs1"

# --- Existing resources ---
resource_group       = "<YOUR_RESOURCE_GROUP>"
virtual_network_name = "<YOUR_VNET_NAME>"
data_subnet_name     = "<YOUR_DATA_SUBNET>"
# No ha_subnet_name needed for standalone.

# --- Hammerspace image ---
image_id = "<YOUR_HAMMERSPACE_IMAGE_ID>"

# --- Credentials ---
admin_password = "<YOUR_ADMIN_PASSWORD>"

# Optional static IP for the Anvil on the data subnet (empty = dynamic).
anvil_data_cluster_ip = ""

# --- Anvil sizing ---
anvil_instance_type  = "Standard_F16s_v2" # Anvil minimum is 16 vCPU / 32 GiB
anvil_boot_disk_size = 512                # minimum 512 GB (boot-disk performance)
# Metadata disk defaults to Premium SSD v2 with provisioned performance
# (standalone Anvils are not in an availability set, so PremiumV2 works):
anvil_metadata_disk_size = 256
# anvil_metadata_disk_iops       = 5000  # default
# anvil_metadata_disk_throughput = 300   # MB/s, default
#
# Ultra disk alternative (same availability-set restrictions as PremiumV2;
# in zoned regions Ultra also requires zonal placement):
# anvil_metadata_disk_type       = "UltraSSD_LRS"
# anvil_metadata_disk_iops       = 10000
# anvil_metadata_disk_throughput = 500

# --- DSX (product minimum: 8 vCPU / 16 GiB - enforced by pre-flight) ---
dsx_count           = 1
dsx_instance_type   = "Standard_F8s_v2"
dsx_boot_disk_size  = 512 # minimum 512 GB
dsx_data_disk_count = 1
dsx_data_disk_size  = 256

public_ip_addresses = false

tags = {
  owner = "<YOUR_NAME>"
}
