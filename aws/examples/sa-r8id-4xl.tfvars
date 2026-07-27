# ============================================================
# Standalone Anvil + DSX on r8id, 4xl Anvil / 2xl DSX
# (port of examples/sa-r8id-4xl.yml).
#
#   1x Anvil  r8id.4xlarge
#   1x DSX    r8id.2xlarge
#   AMI       <YOUR_HAMMERSPACE_AMI>
# ============================================================

deployment_mode = "standalone"

customer    = "internal testing - sa r8id 4xl"
owner       = "douglas"
random_name = "sa-r8id-4xl"

region        = "us-west-2"
vpc           = "<YOUR_VPC_ID>"
subnet_public = "<YOUR_SUBNET_ID_2>"
aws_profile   = ""
key_name      = ""

iam_instance_profile_name = "<YOUR_INSTANCE_PROFILE>"
iam_admin_group           = "AnvilAdmin"

hs_ami = "<YOUR_HAMMERSPACE_AMI>"

# --- Standalone Anvil (r8id.4xlarge - ephemeral NVMe: boot disk only) ---
anvil_instance_type   = "r8id.4xlarge"
anvil_boot_disk_size  = 1024
anvil_meta_disk_size  = 1024
anvil_meta_disk_count = 1
anvil_raid_type       = "stripe"

# --- DSX (r8id.2xlarge - ephemeral NVMe: boot disk only) ---
dsx_count         = 1
dsx_instance_type = "r8id.2xlarge"
dsx_volumes = [
  { device_name = "/dev/sda1", volume_type = "gp3", volume_size = 1024 },
]
