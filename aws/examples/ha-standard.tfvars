# ============================================================
# Example HA deployment values (port of examples/ha-standard.yml).
#
# Shows the variable set for a High-Availability deployment
# modelled on the reference CloudFormation template. Every
# AWS-specific identifier below is a <PLACEHOLDER> - replace
# each one with a value from your own account, then:
#
#   terraform plan  -var-file=examples/ha-standard.tfvars   # dry run
#   terraform apply -var-file=examples/ha-standard.tfvars
# ============================================================

deployment_mode = "ha"

# --- Identification / tagging ---
customer    = "<YOUR_PROJECT_NAME>"
owner       = "<YOUR_NAME>"
random_name = "" # empty = random 5-char suffix only

# --- AWS account / network ---
region        = "<YOUR_AWS_REGION>"
vpc           = "<YOUR_VPC_ID>"
subnet_public = "<YOUR_SUBNET_ID>" # both Anvils and the DSX nodes launch here
aws_profile   = ""
key_name      = "" # optional - empty means no SSH key pair is attached

# --- IAM ---
iam_instance_profile_name = "<YOUR_INSTANCE_PROFILE>"
iam_admin_group           = "<YOUR_IAM_ADMIN_GROUP>"

# --- Hammerspace AMI (account- and region-specific) ---
hs_ami = "<YOUR_HAMMERSPACE_AMI_ID>"

# --- HA Anvil ---
anvil_instance_type = "m7a.4xlarge" # Anvil minimum is 16 vCPU / 32 GiB

# ----------------------------------------------------------
# Anvil disk configuration
# ----------------------------------------------------------
# EBS-backed instance types (no built-in instance-store NVMe):
#   anvil_boot_disk_size   GB  - boot volume, ALWAYS provisioned
#   anvil_meta_disk_size   GB  - size of each metadata volume
#   anvil_meta_disk_count  1, 2, or 4 metadata volumes per node
#   anvil_raid_type        "stripe" (raid0) or "mirror" (raid1)
#                          (ignored when anvil_meta_disk_count == 1)
#
# Instance types WITH ephemeral NVMe (i4i.*, i7ie.*, r8id.*, ...):
# metadata disks are SKIPPED automatically - Hammerspace uses the
# built-in drives. The boot disk is still provisioned.
# ----------------------------------------------------------
anvil_boot_disk_size  = 1024
anvil_meta_disk_size  = 1024
anvil_meta_disk_count = 1
anvil_raid_type       = "stripe" # only used when anvil_meta_disk_count > 1
anvil_cluster_ip      = ""       # empty => auto-allocate the floating IP

# --- DSX ---
dsx_count         = 1
dsx_instance_type = "m7a.2xlarge" # DSX minimum is 8 vCPU / 16 GiB

# ----------------------------------------------------------
# DSX disk configuration
#   - /dev/sda1 (boot) is REQUIRED and is always provisioned.
#   - other entries are data disks, skipped on ephemeral types.
# Tune volume_type / iops / throughput / encrypted / kms_key_id per entry.
# ----------------------------------------------------------
dsx_volumes = [
  { device_name = "/dev/sda1", volume_type = "gp3", volume_size = 1024 }, # boot - required
  { device_name = "/dev/sdb", volume_type = "gp3", volume_size = 1024 },  # data - skipped on ephemeral types
]

# --- Pre-flight ---
skip_preflight = false
