# ============================================================
# Standalone Anvil + DSX at a CUSTOMER site, booting from a
# Hammerspace VHD delivered as a blob SAS URL - no access to
# Hammerspace-internal images or subscriptions required.
#
# How Hammerspace generates the URL (portal):
#   Storage account -> Containers -> the .vhd -> "..." -> Generate SAS
#   - Permissions: Read only
#   - Expiry: 24-48 h (the copy happens once, at first apply)
#   - Allowed protocols: HTTPS only
#   - Do NOT set an allowed-IP range: the copy is SERVER-SIDE
#     (Azure Storage fetches the source, not the deploying machine),
#     so an IP-restricted SAS fails. Short expiry is the control.
#   Copy the "Blob SAS URL".
#
# On the FIRST apply, the VHD is copied into a staging storage
# account inside resource_group, wrapped in a managed image, and
# the redundant .vhd blob is deleted (the image is self-contained).
# The IMAGE persists across terraform destroy, so apply/destroy
# cycles of the product never re-download - later applies reuse it
# instantly. Delete the image (az image delete) and the empty
# hsimg* storage account manually when done for good.
#
# ALTERNATIVE: stage the image ahead of time with
# scripts/stage-hammerspace-image.sh - it prints an image_id; set
# that here instead of image_sas_url.
#
#   terraform plan  -var-file=examples/sa-customer-sas.tfvars   # dry run
#   terraform apply -var-file=examples/sa-customer-sas.tfvars
# ============================================================

deployment_mode = "standalone"

name = "hs1"

# --- Customer-existing resources ---
resource_group       = "<CUSTOMER_RESOURCE_GROUP>"
virtual_network_name = "<CUSTOMER_VNET_NAME>"
data_subnet_name     = "<CUSTOMER_DATA_SUBNET>"

# --- Hammerspace image via SAS URL (instead of image_id / marketplace) ---
# Pre-flight hard-stops if the URL is unreadable, expired, or not a page
# blob - before anything is created.
image_sas_url = "https://<account>.blob.core.windows.net/<container>/<image>.vhd?sp=r&st=...&sig=..."
# Hyper-V generation to register the staged image as. The Hammerspace VHD
# boots either way; the registration decides which VM sizes can use it.
# V1 (default) boots Gen1 and dual-generation sizes (v5 and older).
# V2 (UEFI) is required for Gen2-only sizes (every v6/v7 series); the
# staged image is then named <image>-gen2. Pick once per image - the
# generation of a registered image cannot be changed afterwards.
# image_generation = "V2"

# --- Credentials ---
admin_password = "<CUSTOMER_ADMIN_PASSWORD>"

# --- Anvil sizing (minimums enforced by pre-flight) ---
anvil_instance_type      = "Standard_D16s_v5" # Anvil minimum is 16 vCPU / 32 GiB
anvil_boot_disk_size     = 512                # minimum 512 GB
anvil_metadata_disk_size = 256

# --- DSX (product minimum: 8 vCPU / 16 GiB) ---
dsx_count           = 1
dsx_instance_type   = "Standard_D8s_v5"
dsx_boot_disk_size  = 512
dsx_data_disk_count = 1
dsx_data_disk_size  = 256

public_ip_addresses = false

owner = "<CUSTOMER_CONTACT>" # tag on every resource

tags = {
  customer = "<CUSTOMER_NAME>"
}
