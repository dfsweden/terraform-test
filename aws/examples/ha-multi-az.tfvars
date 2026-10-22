# ============================================================
# HA across two Availability Zones, with a DSX in each.
#
#   Anvil1 -> az1 / subnet_az1     Anvil2 -> az2 / subnet_az2
#   Cluster IP = an OVERLAY address OUTSIDE the VPC CIDR, floated by the
#                Anvil rewriting route tables on failover.
#   An internal NLB across both subnets fronts 443 (mgmt/UI) and 22.
#
# Replace every <PLACEHOLDER> before running. The real-value version used
# for Hammerspace testing is examples/lab/ha-multi-az.tfvars.
#
# The topology is checked at PLAN time: each subnet must be in the AZ and
# VPC you name, every route table must be in that VPC, and the cluster IP
# must be OUTSIDE every CIDR associated with the VPC. A mistake here fails
# the plan rather than half an apply.
# ============================================================

deployment_mode = "ha-multi-az"

# --- Identification / tagging ---
customer    = "<YOUR_PROJECT_NAME>"
owner       = "<YOUR_NAME>"
random_name = "" # empty = the 5-char random suffix alone

# --- AWS account / network (must already exist) ---
region      = "<YOUR_AWS_REGION>"
vpc         = "<YOUR_VPC_ID>"
aws_profile = ""
key_name    = ""

# --- IAM: REQUIRED for HA. The Anvils rewrite routes on failover, so
# pre-flight verifies the role allows CreateRoute/ReplaceRoute/DeleteRoute
# and DescribeRouteTables in addition to the usual EC2 actions.
iam_instance_profile_name = "<YOUR_INSTANCE_PROFILE>"
iam_admin_group           = "<YOUR_IAM_ADMIN_GROUP>"

# --- The two AZs and their subnets ---
az1        = "<YOUR_AZ_1>" # e.g. us-west-2b
az2        = "<YOUR_AZ_2>" # e.g. us-west-2c - MUST differ from az1
subnet_az1 = "<YOUR_SUBNET_IN_AZ_1>"
subnet_az2 = "<YOUR_SUBNET_IN_AZ_2>"

# --- Overlay cluster IP: OUTSIDE the VPC CIDR ---
# Not a subnet address. It is reached through route-table entries, so it
# must not fall inside any CIDR associated with the VPC - the plan checks.
anvil_cluster_ip           = "<AN_IP_OUTSIDE_YOUR_VPC_CIDR>" # e.g. 172.30.14.5
anvil_cluster_ip_prefixlen = 20

# Client route tables the Anvil should maintain a route in. Empty is valid;
# any listed table must belong to the VPC above.
route_table_ids = []

# Wide open by default, matching the Ansible parity. Narrow this for any
# non-lab use.
sec_ip_cidr = "0.0.0.0/0"

# --- Hammerspace AMI (account- and region-specific) ---
hs_ami = "<YOUR_HAMMERSPACE_AMI_ID>"

# --- Anvils (one per AZ) ---
anvil_instance_type   = "m8i.4xlarge" # Anvil minimum is 16 vCPU / 32 GiB
anvil_boot_disk_size  = 1024
anvil_meta_disk_size  = 1024
anvil_meta_disk_count = 1
anvil_raid_type       = "stripe"

# --- DSX: 2 nodes are spread one per AZ (count.index % len(subnets)) ---
dsx_count         = 2
dsx_instance_type = "m8i.2xlarge" # DSX minimum is 8 vCPU / 16 GiB
dsx_volumes = [
  { device_name = "/dev/sda1", volume_type = "gp3", volume_size = 1024 },
  { device_name = "/dev/sdb", volume_type = "gp3", volume_size = 1024 },
]

# The internal NLB fronting 443 and 22. management_url reports its DNS name.
nlb_enabled = true
nlb_scheme  = "internal"

# Multi-AZ waits for the cluster API before creating the DSX nodes, using
# the Primary's PRIVATE IP - the overlay cluster IP is not routable from
# outside the VPC.
wait_for_cluster = true
