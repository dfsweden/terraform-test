# ============================================================
# Hammerspace Anvil + DSX on AWS - Terraform port of the
# hs-anvil-dsx-provision Ansible playbooks.
#
# deployment_mode selects the equivalent playbook:
#   standalone / ha / ha-multi-az / dsx
#
# Dry run: `terraform plan` runs every input validation and the
# full pre-flight (IAM + VPC endpoints + existing-Anvil probe)
# without creating anything - the equivalent of -e dry_run=true.
# ============================================================

# --- Pre-flight: hard-stops the plan before any resource is created ---
module "preflight" {
  count  = var.skip_preflight ? 0 : 1
  source = "./modules/preflight"

  mode                      = var.deployment_mode
  region                    = var.region
  aws_profile               = var.aws_profile
  vpc                       = var.vpc
  subnet_ids                = local.preflight_subnets
  deployer_actions          = local.preflight_deployer_actions[var.deployment_mode]
  iam_instance_profile_name = var.iam_instance_profile_name
  instance_profile_actions  = local.preflight_instance_profile_actions[var.deployment_mode]
  check_sts                 = var.check_sts_endpoint

  # dsx mode only: probe the existing Anvil (reachability + credentials) and
  # verify the DSX AMI's hs_version Major.Minor matches the cluster's.
  check_anvil    = local.is_dsx_only
  anvil_ip       = var.anvil_ip
  anvil_password = var.anvil_password
  hsuser         = var.hsuser
  hs_ami         = var.hs_ami
}

# Pre-flight warnings surface as plan warnings (errors fail the plan outright).
check "preflight_warnings" {
  assert {
    condition     = var.skip_preflight || try(module.preflight[0].warnings, "") == ""
    error_message = "PRE-FLIGHT WARNING(S):\n${try(module.preflight[0].warnings, "")}"
  }
}

# --- Security groups ---
# Parity with Ansible: wide open by default (sec_ip_cidr = 0.0.0.0/0).
# Tighten for any non-lab use.
resource "aws_security_group" "cluster" {
  count = local.creates_anvil && trimspace(var.security_group_id) == "" ? 1 : 0

  name        = "Open group - ${local.name_suffix}"
  description = local.is_multiaz ? "Anvil multi-AZ HA security group ${local.name_suffix}" : "Open group ${local.name_suffix}"
  vpc_id      = var.vpc
  tags        = local.aws_tags

  ingress {
    description = "allow all ports from ${var.sec_ip_cidr}"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.sec_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  depends_on = [terraform_data.validate_inputs, module.preflight]
}

# The DSX manages its OWN security group when adding nodes to an existing
# cluster and none was supplied. Its required port set differs from the
# Anvil's and is currently a wide-open placeholder (TODO(dsx-ports) upstream).
resource "aws_security_group" "dsx" {
  count = local.is_dsx_only && trimspace(var.security_group_id) == "" ? 1 : 0

  name        = "Open group - ${local.name_suffix}-dsx"
  description = "DSX security group ${local.name_suffix}"
  vpc_id      = var.vpc
  tags        = local.aws_tags

  ingress {
    description = "TEMP wide-open - DSX-specific port set TBD"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.sec_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  depends_on = [terraform_data.validate_inputs, module.preflight]
}

# --- Anvil (one module per deployment shape) ---
module "anvil_standalone" {
  count  = local.is_standalone ? 1 : 0
  source = "./modules/anvil-standalone"

  name                 = "anvil-1-${local.name_suffix}"
  ami                  = var.hs_ami
  instance_type        = var.anvil_instance_type
  subnet_id            = var.subnet_public
  security_group_id    = local.security_group_id
  key_name             = var.key_name
  iam_instance_profile = local.iam_instance_profile
  boot_disk_size       = var.anvil_boot_disk_size
  meta_disk_size       = var.anvil_meta_disk_size
  meta_disk_count      = var.anvil_meta_disk_count
  meta_disk_iops       = var.anvil_meta_disk_iops
  raid_type            = var.anvil_raid_type
  network_mtu          = var.network_mtu
  iam_admin_group      = var.iam_admin_group
  eip                  = var.eip
  tags                 = local.aws_tags

  depends_on = [terraform_data.validate_inputs, module.preflight]
}

module "anvil_ha" {
  count  = local.is_ha ? 1 : 0
  source = "./modules/anvil-ha"

  name_suffix          = local.name_suffix
  ami                  = var.hs_ami
  instance_type        = var.anvil_instance_type
  subnet_id            = var.subnet_public
  security_group_id    = local.security_group_id
  key_name             = var.key_name
  iam_instance_profile = local.iam_instance_profile
  cluster_ip           = var.anvil_cluster_ip
  boot_disk_size       = var.anvil_boot_disk_size
  meta_disk_size       = var.anvil_meta_disk_size
  meta_disk_count      = var.anvil_meta_disk_count
  meta_disk_iops       = var.anvil_meta_disk_iops
  raid_type            = var.anvil_raid_type
  network_mtu          = var.network_mtu
  iam_admin_group      = var.iam_admin_group
  region               = var.region
  aws_profile          = var.aws_profile
  tags                 = local.aws_tags

  depends_on = [terraform_data.validate_inputs, module.preflight]
}

module "anvil_ha_multiaz" {
  count  = local.is_multiaz ? 1 : 0
  source = "./modules/anvil-ha-multiaz"

  name_suffix          = local.name_suffix
  ami                  = var.hs_ami
  instance_type        = var.anvil_instance_type
  vpc_id               = var.vpc
  az1                  = var.az1
  az2                  = var.az2
  subnet_az1           = var.subnet_az1
  subnet_az2           = var.subnet_az2
  security_group_id    = local.security_group_id
  key_name             = var.key_name
  iam_instance_profile = local.iam_instance_profile
  cluster_ip           = var.anvil_cluster_ip
  route_table_ids      = var.route_table_ids
  boot_disk_size       = var.anvil_boot_disk_size
  meta_disk_size       = var.anvil_meta_disk_size
  meta_disk_count      = var.anvil_meta_disk_count
  meta_disk_iops       = var.anvil_meta_disk_iops
  raid_type            = var.anvil_raid_type
  network_mtu          = var.network_mtu
  iam_admin_group      = var.iam_admin_group
  nlb_enabled          = var.nlb_enabled
  nlb_scheme           = var.nlb_scheme
  tags                 = local.aws_tags

  depends_on = [terraform_data.validate_inputs, module.preflight]
}

# --- Wait for the HA cluster management API before launching DSX ---
# Mirrors the Ansible ordering: the HA plays wait for :8443 to answer 200
# before the DSX play runs. (Standalone launches DSX immediately, dsx mode
# probed the existing Anvil in pre-flight - same as Ansible.)
module "wait_for_cluster" {
  count  = (local.is_ha || local.is_multiaz) && var.wait_for_cluster ? 1 : 0
  source = "../shared/wait-for-api"

  endpoint = local.anvil_mgmt_endpoint
  hsuser   = var.hsuser
  password = local.anvil_password
}

# Product minimum for an Anvil node: 16 vCPU / 32 GiB. Checked at ROOT level
# so it fails the PLAN - data sources inside the anvil modules are deferred to
# apply by their depends_on.
data "aws_ec2_instance_type" "anvil_minimum" {
  count = local.creates_anvil ? 1 : 0

  instance_type = var.anvil_instance_type

  lifecycle {
    postcondition {
      condition     = self.default_vcpus >= 16 && self.memory_size >= 32768
      error_message = "Anvil instance type ${var.anvil_instance_type} is below the product minimum: has ${self.default_vcpus} vCPU / ${self.memory_size} MiB, needs at least 16 vCPU / 32 GiB."
    }
  }
}

# Product minimum for a DSX node: 8 vCPU / 16 GiB. Checked at ROOT level so
# it fails the PLAN - data sources inside module "dsx" are deferred to apply
# by that module's depends_on.
data "aws_ec2_instance_type" "dsx_minimum" {
  count = var.dsx_count > 0 ? 1 : 0

  instance_type = var.dsx_instance_type

  lifecycle {
    postcondition {
      condition     = self.default_vcpus >= 8 && self.memory_size >= 16384
      error_message = "DSX instance type ${var.dsx_instance_type} is below the product minimum: has ${self.default_vcpus} vCPU / ${self.memory_size} MiB, needs at least 8 vCPU / 16 GiB."
    }
  }
}

# --- DSX node(s) ---
module "dsx" {
  count  = var.dsx_count > 0 ? 1 : 0
  source = "./modules/dsx"

  node_count           = var.dsx_count
  name_suffix          = local.name_suffix
  ami                  = var.hs_ami
  instance_type        = var.dsx_instance_type
  subnet_ids           = local.is_multiaz ? [var.subnet_az1, var.subnet_az2] : [var.subnet_public]
  security_group_id    = local.security_group_id
  key_name             = var.key_name
  iam_instance_profile = local.iam_instance_profile
  volumes              = var.dsx_volumes
  network_mtu          = var.network_mtu
  iam_admin_group      = var.iam_admin_group
  anvil_ip             = local.anvil_ip
  anvil_password       = local.anvil_password
  multiaz              = local.is_multiaz
  cluster_ip_prefixlen = var.anvil_cluster_ip_prefixlen
  route_table_ids      = var.route_table_ids
  eip                  = local.is_standalone ? "" : var.eip
  tags                 = local.aws_tags

  depends_on = [terraform_data.validate_inputs, module.preflight, module.wait_for_cluster]
}

# --- Wait for the cluster API, then tag every instance with the cluster ID ---
# Equivalent of the aws_tag_cluster_id role: reads the cntl object's
# uoid.uuid over the management REST API and tags all instances created this
# apply with <cluster_id_tag_key>=<uuid>.
module "cluster_tag" {
  count  = var.wait_for_cluster && length(local.all_instance_ids) > 0 ? 1 : 0
  source = "../shared/cluster-tag"

  endpoint = local.anvil_mgmt_endpoint
  hsuser   = var.hsuser
  password = local.anvil_password
  triggers = local.all_instance_ids
  tag_command = join(" ", concat(
    ["aws", "--region", var.region],
    var.aws_profile != "" ? ["--profile", var.aws_profile] : [],
    ["ec2", "create-tags", "--resources"],
    local.all_instance_ids,
    ["--tags", "Key=${var.cluster_id_tag_key},Value=__CLUSTER_ID__"],
  ))

  depends_on = [module.dsx, module.anvil_standalone, module.anvil_ha, module.anvil_ha_multiaz]
}
