# ============================================================
# Standalone Anvil with 4 gp3 metadata disks in a RAID0 (stripe)
# layout on r8i (port of examples/sa-r8i-stripe-4.yml).
#
# 4 x 1024 GB gp3 EBS metadata volumes, striped. r8i.* is
# EBS-only (no instance-store), so metadata volumes are
# provisioned normally and node.storage.options=raid0 is set
# in user_data so the installer stripes across them.
# ============================================================

deployment_mode = "standalone"

customer    = "internal testing - sa r8i stripe"
owner       = "douglas"
random_name = "sa-r8i-stripe"

region        = "us-west-2"
vpc           = "<YOUR_VPC_ID>"
subnet_public = "<YOUR_SUBNET_ID_2>"
aws_profile   = ""
key_name      = ""

iam_instance_profile_name = "<YOUR_INSTANCE_PROFILE>"
iam_admin_group           = "AnvilAdmin"

hs_ami = "<YOUR_HAMMERSPACE_AMI>"

# --- Standalone Anvil (r8i.2xlarge - 4-disk gp3 stripe) ---
anvil_instance_type   = "r8i.4xlarge" # Anvil minimum is 16 vCPU / 32 GiB
anvil_boot_disk_size  = 1024
anvil_meta_disk_size  = 1024     # GB per metadata disk
anvil_meta_disk_count = 4        # 4 metadata disks: /dev/sdb../dev/sde
anvil_raid_type       = "stripe" # raid0 across the 4 disks

# --- DSX ---
dsx_count         = 1
dsx_instance_type = "m7a.2xlarge" # DSX minimum is 8 vCPU / 16 GiB
dsx_volumes = [
  { device_name = "/dev/sda1", volume_type = "gp3", volume_size = 1024 },
  { device_name = "/dev/sdb", volume_type = "gp3", volume_size = 1024 },
]
