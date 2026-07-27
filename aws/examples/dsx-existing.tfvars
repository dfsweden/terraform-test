# ============================================================
# Add DSX node(s) to an EXISTING Hammerspace cluster
# (port of examples/dsx-existing.yml).
#
#   terraform plan  -var-file=examples/dsx-existing.tfvars
#   terraform apply -var-file=examples/dsx-existing.tfvars
#
# NOTE: use a SEPARATE Terraform state (directory / workspace) per
# add-DSX batch so a later destroy only removes these DSX nodes.
# ============================================================

deployment_mode = "dsx"

# --- Identification / tagging ---
customer    = ""
owner       = "you"
random_name = "add-dsx"

# --- AWS account / network (must match the existing cluster's VPC) ---
region        = "us-west-2"
vpc           = "vpc-xxxxxxxx"
subnet_public = "subnet-xxxxxxxx"
aws_profile   = ""
key_name      = ""

iam_instance_profile_name = "<YOUR_INSTANCE_PROFILE>"

# --- Hammerspace AMI (match the running cluster's version) ---
# Pre-flight verifies the AMI's hs_version tag shares the cluster's
# Major.Minor (patch/build ignored) and hard-stops on a mismatch.
hs_ami = "ami-xxxxxxxxxxxxxxxxx"

# --- EXISTING cluster to join (REQUIRED) ---
# anvil_ip is the running cluster's Anvil / cluster IP; anvil_password is its
# admin password. Pre-flight probes https://<anvil_ip>:8443 with these and
# hard-stops if the Anvil is unreachable or the credentials are rejected.
anvil_ip       = "10.0.0.10"
anvil_password = "CHANGE_ME"

# --- Security group ---
# Leave empty to let the DSX create its own security group; set it to the
# existing cluster's security group ID to place the new DSX in it instead.
security_group_id = ""

# --- DSX node(s) to add ---
dsx_count         = 1
dsx_instance_type = "r8id.2xlarge"
# On ephemeral instance types only /dev/sda1 (boot) is provisioned.
dsx_volumes = [
  { device_name = "/dev/sda1", volume_type = "gp3", volume_size = 1024 },
]
