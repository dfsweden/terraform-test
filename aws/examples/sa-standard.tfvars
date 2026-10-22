# ============================================================
# Standalone: 1 Anvil + 1 DSX.
#
# The simplest complete deployment - a single metadata node and one
# data-services node. Replace every <PLACEHOLDER> before running.
#
#   1x Anvil  m8i.4xlarge   (16 vCPU / 64 GiB)
#   1x DSX    m8i.2xlarge   ( 8 vCPU / 32 GiB)
#
# Sizing is not advisory: pre-flight fails the PLAN if the Anvil is below
# 16 vCPU / 32 GiB or the DSX below 8 vCPU / 16 GiB.
#
# m8i has no instance storage, so the metadata and data EBS volumes below
# are created. On a type WITH built-in NVMe (i4i, i7ie, r8id, c8id, ...)
# they are skipped automatically and Hammerspace uses the local drives -
# see lab/sa-r8id-4xl.tfvars.
#
#   terraform plan  -var-file=examples/sa-standard.tfvars
#   terraform apply -var-file=examples/sa-standard.tfvars
# ============================================================

deployment_mode = "standalone"

# --- Identification / tagging ---
customer    = "<YOUR_PROJECT_NAME>"
owner       = "<YOUR_NAME>"
random_name = "" # empty = the 5-char random suffix alone

# --- AWS account / network (must already exist) ---
region        = "<YOUR_AWS_REGION>"
vpc           = "<YOUR_VPC_ID>"
subnet_public = "<YOUR_SUBNET_ID>" # the Anvil and the DSX both launch here
aws_profile   = ""
key_name      = "" # optional - empty means no SSH key pair is attached

# --- IAM ---
# Optional for standalone (an HA deployment requires it), but the DSX and
# Anvil use it for the S3/EC2 calls the product makes at runtime.
iam_instance_profile_name = "<YOUR_INSTANCE_PROFILE>"
iam_admin_group           = "<YOUR_IAM_ADMIN_GROUP>"

# --- Hammerspace AMI (account- and region-specific) ---
hs_ami = "<YOUR_HAMMERSPACE_AMI_ID>"

# --- Anvil ---
anvil_instance_type   = "m8i.4xlarge" # Anvil minimum is 16 vCPU / 32 GiB
anvil_boot_disk_size  = 1024
anvil_meta_disk_size  = 1024
anvil_meta_disk_count = 1
anvil_raid_type       = "stripe" # only used when anvil_meta_disk_count > 1

# --- DSX ---
dsx_count         = 1
dsx_instance_type = "m8i.2xlarge" # DSX minimum is 8 vCPU / 16 GiB
dsx_volumes = [
  { device_name = "/dev/sda1", volume_type = "gp3", volume_size = 1024 }, # boot - required, >= 512 GB
  { device_name = "/dev/sdb", volume_type = "gp3", volume_size = 1024 },  # data  - skipped on ephemeral types
]

# The cluster admin password of a fresh AWS deployment is the Anvil's EC2
# instance ID; `terraform output anvil_password` prints it.
#
# Set false when terraform runs somewhere that cannot reach the Anvil's
# :8443 - the instances are still created, only the readiness wait and the
# cluster-ID tagging are skipped.
wait_for_cluster = true
