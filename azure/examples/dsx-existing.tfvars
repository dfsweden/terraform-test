# ============================================================
# Add DSX node(s) to an EXISTING Hammerspace cluster on Azure -
# the marketplace "Add Data Services (DSX) to an existing
# deployment" shape.
#
#   terraform plan  -var-file=examples/dsx-existing.tfvars
#   terraform apply -var-file=examples/dsx-existing.tfvars
#
# NOTE: use a SEPARATE Terraform state per add-DSX batch so a
# later destroy only removes these DSX nodes.
# ============================================================

deployment_mode = "dsx"

name = "hs1add"

# --- Existing resources (must match the running cluster's network) ---
resource_group       = "<YOUR_RESOURCE_GROUP>"
virtual_network_name = "<YOUR_VNET_NAME>"
data_subnet_name     = "<YOUR_DATA_SUBNET>"

# --- Hammerspace image (match the running cluster's version) ---
# Pre-flight verifies Major.Minor compatibility when the image carries an
# hs_version tag (warning when it does not).
image_id = "<YOUR_HAMMERSPACE_IMAGE_ID>"

# --- EXISTING cluster to join (REQUIRED) ---
# anvil_ip = the cluster's (Anvil / LB) IP; admin_password = that cluster's
# admin password. Pre-flight probes https://<anvil_ip>:8443 with these and
# hard-stops if the Anvil is unreachable or the credentials are rejected.
anvil_ip       = "10.0.10.10"
admin_password = "<EXISTING_CLUSTER_ADMIN_PASSWORD>"

# --- DSX node(s) to add (product minimum: 8 vCPU / 16 GiB) ---
dsx_count           = 1
dsx_instance_type   = "Standard_F8s_v2"
dsx_boot_disk_size  = 512 # minimum 512 GB
dsx_data_disk_count = 1
dsx_data_disk_size  = 256

# Reuse the cluster's NSG instead of creating one (optional):
# network_security_group_id = "/subscriptions/.../networkSecurityGroups/<name>"
