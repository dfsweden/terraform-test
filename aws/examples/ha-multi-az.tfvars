# ============================================================
# MULTI-AZ (cross-AZ) HA Anvil + DSX cluster
# (port of examples/ha-multi-az.yml).
#
#   terraform plan  -var-file=examples/ha-multi-az.tfvars
#   terraform apply -var-file=examples/ha-multi-az.tfvars
# ============================================================

deployment_mode = "ha-multi-az"

# --- Identification / tagging ---
customer    = "internal testing - multi-az"
owner       = "you"
random_name = "ha-maz"

# --- AWS account / network ---
region      = "us-west-2"
vpc         = "<YOUR_VPC_ID>"
aws_profile = ""
key_name    = ""

iam_instance_profile_name = "<YOUR_INSTANCE_PROFILE>"

# --- Cross-AZ placement (two DIFFERENT AZs, a subnet in each) ---
az1        = "us-west-2b"
az2        = "us-west-2c"
subnet_az1 = "<YOUR_SUBNET_ID_2>" # in az1
subnet_az2 = "<YOUR_SUBNET_ID>"          # in az2

# --- Overlay cluster IP + route-based failover ---
# MUST be outside the VPC CIDR - it is reached via route-table entries the
# Anvil rewrites on failover, not via a subnet. Pre-flight enforces this.
anvil_cluster_ip = "172.30.14.5"
# Additional client route tables to carry the floating /32 (the data
# subnets' own route tables are handled by the product).
route_table_ids = []
# Prefix length used in the DSX metadata config (<cluster_ip>/<prefixlen>).
anvil_cluster_ip_prefixlen = 20
# Security-group source CIDR (0.0.0.0/0 = open).
sec_ip_cidr = "0.0.0.0/0"

# --- Hammerspace AMI ---
hs_ami = "<YOUR_HAMMERSPACE_AMI>"

# --- Anvil sizing ---
anvil_instance_type   = "m7a.4xlarge" # Anvil minimum is 16 vCPU / 32 GiB
anvil_boot_disk_size  = 1024
anvil_meta_disk_size  = 1024
anvil_meta_disk_count = 1
anvil_raid_type       = "stripe"

# --- DSX (spread round-robin across az1/az2) ---
dsx_count         = 2
dsx_instance_type = "m7a.2xlarge" # DSX minimum is 8 vCPU / 16 GiB
dsx_volumes = [
  { device_name = "/dev/sda1", volume_type = "gp3", volume_size = 1024 },
]
