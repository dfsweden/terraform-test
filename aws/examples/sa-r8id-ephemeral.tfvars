# ============================================================
# Standalone Anvil + DSX on r8id (built-in NVMe instance-store)
# (port of examples/sa-r8id-ephemeral.yml).
#
# r8id.* has ephemeral NVMe drives, so Terraform:
#   - PROVISIONS the boot disk only
#   - SKIPS the metadata EBS volumes (Anvil)
#   - SKIPS the data EBS volumes (DSX)
# Hammerspace uses the built-in NVMe drives instead.
# ============================================================

deployment_mode = "standalone"

customer    = "internal testing - sa r8id"
owner       = "douglas"
random_name = "sa-r8id"

region        = "us-west-2"
vpc           = "<YOUR_VPC_ID>"
subnet_public = "<YOUR_SUBNET_ID_2>"
aws_profile   = ""
key_name      = ""

iam_instance_profile_name = "<YOUR_INSTANCE_PROFILE>"
iam_admin_group           = "AnvilAdmin"

hs_ami = "<YOUR_HAMMERSPACE_AMI>" # thor3-1217   <YOUR_HAMMERSPACE_AMI> # mainline-5332

# --- Standalone Anvil (r8id.4xlarge - ephemeral NVMe) ---
anvil_instance_type = "r8id.4xlarge"
# Boot disk is always provisioned. The metadata sizing below is ignored
# because ephemeral storage is auto-detected and the EBS metadata volumes
# are skipped entirely.
anvil_boot_disk_size  = 1024
anvil_meta_disk_size  = 1024
anvil_meta_disk_count = 1
anvil_raid_type       = "stripe"

# --- DSX (r8id.2xlarge - ephemeral NVMe) ---
dsx_count         = 1
dsx_instance_type = "r8id.2xlarge"
# Only /dev/sda1 is provisioned on ephemeral types. Additional entries
# (data disks) would be skipped automatically.
dsx_volumes = [
  { device_name = "/dev/sda1", volume_type = "gp3", volume_size = 1024 },
]
