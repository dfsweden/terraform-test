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
  deployer_actions          = concat(local.preflight_deployer_actions[var.deployment_mode], local.eip_deployer_actions)
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
#
# Entries prefixed "NOT CHECKED:" mean pre-flight lacked the permission to run
# that check, not that it ran and found nothing - a clean plan is only proof
# the checks executed if no such line appears.
check "preflight_warnings" {
  assert {
    condition     = var.skip_preflight || try(module.preflight[0].warnings, "") == ""
    error_message = "PRE-FLIGHT WARNING(S) - lines marked 'NOT CHECKED' were skipped, not passed:\n${try(module.preflight[0].warnings, "")}"
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

  has_ephemeral        = local.anvil_has_ephemeral
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
  # eip (the address) only sets the module's anvil_ip output, i.e. what the DSX
  # joins on. With create_eips that must stay the PRIVATE IP - same subnet, no
  # hairpin out through the internet gateway, jumbo frames intact - so only the
  # allocation ID is passed and the address is left empty.
  eip                = var.create_eips ? "" : var.eip
  eip_allocation_ids = local.anvil_eip_allocation_ids
  tags               = local.aws_tags

  depends_on = [terraform_data.validate_inputs, module.preflight]
}

module "anvil_ha" {
  count  = local.is_ha ? 1 : 0
  source = "./modules/anvil-ha"

  has_ephemeral        = local.anvil_has_ephemeral
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

  has_ephemeral        = local.anvil_has_ephemeral
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

# --- Multi-AZ topology checks (ROOT level, for the same reason as above) ---
#
# These lived in modules/anvil-ha-multiaz, whose header claimed they "run
# natively at plan time". They did not: the module is called with depends_on,
# which defers every data source inside it to APPLY - so a subnet in the wrong
# AZ, a subnet or route table in the wrong VPC, or an overlay IP inside the VPC
# CIDR was only caught after the operator had already approved the plan.
#
# Every one of these reads a plain input variable, so at root they resolve at
# plan and their postconditions fail the plan. The module never consumed their
# values - aws_subnet and aws_route_table were referenced only as depends_on
# targets - so nothing needs passing down.
data "aws_subnet" "az1" {
  count = local.is_multiaz ? 1 : 0
  id    = var.subnet_az1

  lifecycle {
    postcondition {
      condition     = self.availability_zone == var.az1
      error_message = "subnet_az1 (${var.subnet_az1}) is in AZ ${self.availability_zone}, not az1=${var.az1}."
    }
    postcondition {
      condition     = self.vpc_id == var.vpc
      error_message = "subnet_az1 (${var.subnet_az1}) is in VPC ${self.vpc_id}, not ${var.vpc}."
    }
  }
}

data "aws_subnet" "az2" {
  count = local.is_multiaz ? 1 : 0
  id    = var.subnet_az2

  lifecycle {
    postcondition {
      condition     = self.availability_zone == var.az2
      error_message = "subnet_az2 (${var.subnet_az2}) is in AZ ${self.availability_zone}, not az2=${var.az2}."
    }
    postcondition {
      condition     = self.vpc_id == var.vpc
      error_message = "subnet_az2 (${var.subnet_az2}) is in VPC ${self.vpc_id}, not ${var.vpc}."
    }
  }
}

# The overlay cluster IP must be OUTSIDE every CIDR associated with the VPC -
# it is reached via route-table entries, not a subnet.
data "aws_vpc" "multiaz" {
  count = local.is_multiaz ? 1 : 0
  id    = var.vpc
}

# Any supplied client route tables must exist in the VPC.
data "aws_route_table" "extra" {
  for_each       = local.is_multiaz ? toset(var.route_table_ids) : toset([])
  route_table_id = each.value

  lifecycle {
    postcondition {
      condition     = self.vpc_id == var.vpc
      error_message = "route table ${each.value} is in VPC ${self.vpc_id}, not ${var.vpc}."
    }
  }
}

# subnet_public, at ROOT level so both checks below fail the PLAN. Used by
# standalone / ha / dsx (multi-AZ uses subnet_az1 + subnet_az2 above).
data "aws_subnet" "public" {
  count = !local.is_multiaz && trimspace(var.subnet_public) != "" ? 1 : 0
  id    = var.subnet_public

  lifecycle {
    postcondition {
      condition     = self.vpc_id == var.vpc
      error_message = "subnet_public (${var.subnet_public}) is in VPC ${self.vpc_id}, not ${var.vpc}."
    }
  }
}

# ha only: the cluster IP is a secondary private IP on an ENI in subnet_public,
# so unlike the multi-AZ overlay address it must be INSIDE the subnet - and not
# one of the five addresses AWS reserves in every subnet.
resource "terraform_data" "ha_cluster_ip_check" {
  count = local.ha_pinned_cluster_ip ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.ha_cluster_ip_inside_subnet
      error_message = "anvil_cluster_ip ${var.anvil_cluster_ip} is OUTSIDE subnet_public ${var.subnet_public} (${local._ha_subnet_cidr}) - in single-AZ HA the cluster IP is a secondary private IP on an ENI in that subnet, so it must fall inside it. (An overlay IP outside the range is the ha-multi-az design, not this one.)"
    }
    precondition {
      condition     = !local.ha_cluster_ip_reserved
      error_message = "anvil_cluster_ip ${var.anvil_cluster_ip} is one of the addresses AWS reserves in ${local._ha_subnet_cidr}: the first four (network, VPC router, DNS, reserved) and the last (broadcast) cannot be assigned."
    }
  }
}

# --- Elastic IPs allocated by this deployment (create_eips) ---
# For a VPC with no private path from the operator: one address for the Anvil
# (which also becomes the management endpoint) and one per DSX node. An EIP
# association survives an instance stop/start in a VPC, unlike an
# auto-assigned public IP, so these are stable across a BUSINESS_HOURS cycle.
resource "aws_eip" "anvil" {
  count = var.create_eips && local.creates_anvil ? 1 : 0

  domain = "vpc"
  tags   = merge(local.aws_tags, { Name = "anvil-1-${local.name_suffix}" })

  depends_on = [terraform_data.validate_inputs]
}

resource "aws_eip" "dsx" {
  count = var.create_eips ? var.dsx_count : 0

  domain = "vpc"
  tags   = merge(local.aws_tags, { Name = "dsx-${count.index + 1}-${local.name_suffix}" })

  depends_on = [terraform_data.validate_inputs]
}

# The optional Elastic IP, looked up at ROOT level. A singular data source
# errors when nothing matches, so this is already an existence check - it just
# used to run inside the modules, where depends_on deferred it to apply and a
# typo'd address failed only after the instances existed.
data "aws_eip" "assoc" {
  count     = var.eip != "" ? 1 : 0
  public_ip = var.eip
}

resource "terraform_data" "overlay_ip_check" {
  count = local.is_multiaz ? 1 : 0

  lifecycle {
    precondition {
      condition     = !local.cluster_ip_inside_vpc
      error_message = "anvil_cluster_ip ${var.anvil_cluster_ip} is INSIDE the VPC CIDR ${join(", ", local.multiaz_vpc_cidrs)} - multi-AZ HA needs an OVERLAY IP outside the VPC range (it is reached via route-table entries, not a subnet)."
    }
  }
}

# --- DSX node(s) ---
module "dsx" {
  count  = var.dsx_count > 0 ? 1 : 0
  source = "./modules/dsx"

  has_ephemeral        = local.dsx_has_ephemeral
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
  eip_allocation_ids   = local.dsx_eip_allocation_ids
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
