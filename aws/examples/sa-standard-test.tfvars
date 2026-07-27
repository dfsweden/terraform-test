# ============================================================
# Standalone Anvil + DSX, standard test config
# (port of examples/sa-standard-test.yml).
#
#   terraform apply -var-file=examples/sa-standard-test.tfvars
# ============================================================

deployment_mode = "standalone"

customer    = "internal testing - sa standard"
owner       = "douglas"
random_name = "sa-standard"

region        = "us-west-2"
vpc           = "<YOUR_VPC_ID>"
subnet_public = "<YOUR_SUBNET_ID_2>"
aws_profile   = ""
key_name      = ""

iam_instance_profile_name = "<YOUR_INSTANCE_PROFILE>"
iam_admin_group           = "AnvilAdmin"

hs_ami = "<YOUR_HAMMERSPACE_AMI>"

# --- Standalone Anvil ---
anvil_instance_type   = "m7a.4xlarge" # Anvil minimum is 16 vCPU / 32 GiB
anvil_boot_disk_size  = 1024
anvil_meta_disk_size  = 2048
anvil_meta_disk_count = 1
anvil_raid_type       = "stripe" # only used when anvil_meta_disk_count > 1

# --- DSX ---
dsx_count         = 1
dsx_instance_type = "m7a.2xlarge" # DSX minimum is 8 vCPU / 16 GiB
dsx_volumes = [
  { device_name = "/dev/sda1", volume_type = "gp3", volume_size = 1024 },
  { device_name = "/dev/sdb", volume_type = "gp3", volume_size = 1024 },
]
