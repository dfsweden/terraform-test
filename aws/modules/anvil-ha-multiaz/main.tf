# ============================================================
# 2-node MULTI-AZ (cross-AZ) HA Anvil - Terraform port of the
# aws_provision_anvil_ha_multiaz Ansible role.
#
#   Anvil1 -> az1 / subnet_az1     Anvil2 -> az2 / subnet_az2
#   Cluster IP = overlay IP outside the VPC CIDR, floated by the
#                Anvil rewriting route_table_ids on failover.
#   An internal NLB (both subnets) fronts 443 (mgmt/UI) + 22 (SSH).
#
# The cross-AZ topology checks (subnet AZ/VPC membership, overlay
# IP outside the VPC CIDR, route tables in the VPC) run natively
# at plan time via data-source postconditions - the equivalent of
# the stricter multi-AZ pre-flight.
# ============================================================

data "aws_ec2_instance_type" "anvil" {
  instance_type = var.instance_type
}

# --- Cross-AZ topology validation (hard stop at plan time) ---
data "aws_subnet" "az1" {
  id = var.subnet_az1

  lifecycle {
    postcondition {
      condition     = self.availability_zone == var.az1
      error_message = "subnet_az1 (${var.subnet_az1}) is in AZ ${self.availability_zone}, not az1=${var.az1}."
    }
    postcondition {
      condition     = self.vpc_id == var.vpc_id
      error_message = "subnet_az1 (${var.subnet_az1}) is in VPC ${self.vpc_id}, not ${var.vpc_id}."
    }
  }
}

data "aws_subnet" "az2" {
  id = var.subnet_az2

  lifecycle {
    postcondition {
      condition     = self.availability_zone == var.az2
      error_message = "subnet_az2 (${var.subnet_az2}) is in AZ ${self.availability_zone}, not az2=${var.az2}."
    }
    postcondition {
      condition     = self.vpc_id == var.vpc_id
      error_message = "subnet_az2 (${var.subnet_az2}) is in VPC ${self.vpc_id}, not ${var.vpc_id}."
    }
  }
}

# The overlay cluster IP must be OUTSIDE every CIDR associated with the VPC -
# it is reached via route-table entries, not a subnet.
data "aws_vpc" "this" {
  id = var.vpc_id
}

resource "terraform_data" "overlay_ip_check" {
  lifecycle {
    precondition {
      condition     = !local.cluster_ip_inside_vpc
      error_message = "anvil_cluster_ip ${var.cluster_ip} is INSIDE the VPC CIDR ${join(", ", [for a in data.aws_vpc.this.cidr_block_associations : a.cidr_block])} - multi-AZ HA needs an OVERLAY IP outside the VPC range (it is reached via route-table entries, not a subnet)."
    }
  }
}

# Any supplied client route tables must exist in the VPC.
data "aws_route_table" "extra" {
  for_each       = toset(var.route_table_ids)
  route_table_id = each.value

  lifecycle {
    postcondition {
      condition     = self.vpc_id == var.vpc_id
      error_message = "route table ${each.value} is in VPC ${self.vpc_id}, not ${var.vpc_id}."
    }
  }
}

locals {
  # IPv4 maths for the inside/outside-VPC-CIDR test (no cidrcontains() in HCL).
  _ip_octets = [for o in split(".", var.cluster_ip) : tonumber(o)]
  _ip_num    = local._ip_octets[0] * 16777216 + local._ip_octets[1] * 65536 + local._ip_octets[2] * 256 + local._ip_octets[3]
  _cidr_ranges = [
    for a in data.aws_vpc.this.cidr_block_associations : {
      first = (
        tonumber(split(".", cidrhost(a.cidr_block, 0))[0]) * 16777216
        + tonumber(split(".", cidrhost(a.cidr_block, 0))[1]) * 65536
        + tonumber(split(".", cidrhost(a.cidr_block, 0))[2]) * 256
        + tonumber(split(".", cidrhost(a.cidr_block, 0))[3])
      )
      size = pow(2, 32 - tonumber(split("/", a.cidr_block)[1]))
    }
  ]
  cluster_ip_inside_vpc = anytrue([
    for r in local._cidr_ranges : local._ip_num >= r.first && local._ip_num < r.first + r.size
  ])

  has_ephemeral = data.aws_ec2_instance_type.anvil.instance_storage_supported
  meta_devices  = local.has_ephemeral ? [] : slice(["/dev/sdb", "/dev/sdc", "/dev/sdd", "/dev/sde"], 0, var.meta_disk_count)
  raid_opt      = var.raid_type == "stripe" ? "raid0" : "raid1"

  hostnames = ["anvil-1-${var.name_suffix}", "anvil-2-${var.name_suffix}"]

  eth0_primary = { roles = var.node_roles, mtu = var.network_mtu }
  # The Secondary's eth0 ALWAYS carries the overlay cluster IP here.
  eth0_secondary = merge(local.eth0_primary, { cluster_ips = [var.cluster_ip] })

  node_storage = {
    for k, v in { storage = { options = [local.raid_opt] } } :
    k => v if !local.has_ephemeral && var.meta_disk_count > 1
  }

  nodes_map = {
    "0" = merge({
      hostname = local.hostnames[0]
      ha_mode  = "Primary"
      features = ["metadata"]
      networks = { eth0 = local.eth0_primary }
    }, local.node_storage)
    "1" = merge({
      hostname = local.hostnames[1]
      ha_mode  = "Secondary"
      features = ["metadata"]
      networks = { eth0 = local.eth0_secondary }
    }, local.node_storage)
  }

  # aws block carries the route_table_ids the Anvil rewrites on failover (the
  # cross-AZ delta vs single-AZ HA), plus the optional iam_admin_group.
  aws_block = merge(
    { route_table_ids = var.route_table_ids },
    {
      for k, v in { iam_admin_group = var.iam_admin_group } :
      k => v if trimspace(var.iam_admin_group) != ""
    },
  )

  user_data_base = {
    cluster = { password_auth = true }
    nodes   = local.nodes_map
    aws     = local.aws_block
  }

  # ELB names: [A-Za-z0-9-] only, max 32 chars, no trailing dash.
  nlb_name   = replace(substr(replace("nlb-${var.name_suffix}", "/[^A-Za-z0-9-]/", "-"), 0, 32), "/-+$/", "")
  tg443_name = replace(substr(replace("tg443-${var.name_suffix}", "/[^A-Za-z0-9-]/", "-"), 0, 32), "/-+$/", "")
  tg22_name  = replace(substr(replace("tg22-${var.name_suffix}", "/[^A-Za-z0-9-]/", "-"), 0, 32), "/-+$/", "")
}

# --- Anvil instances ---
# source_dest_check must be off so an ENI can receive traffic for the overlay
# cluster IP (which is not the ENI's own primary IP).
resource "aws_instance" "primary" {
  ami                         = var.ami
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_az1
  vpc_security_group_ids      = [var.security_group_id]
  key_name                    = var.key_name != "" ? var.key_name : null
  iam_instance_profile        = var.iam_instance_profile != "" ? var.iam_instance_profile : null
  associate_public_ip_address = false
  source_dest_check           = false
  user_data                   = jsonencode(merge(local.user_data_base, { node_index = "0" }))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.boot_disk_size
    delete_on_termination = true
  }

  dynamic "ebs_block_device" {
    for_each = toset(local.meta_devices)
    content {
      device_name           = ebs_block_device.value
      volume_type           = "gp3"
      volume_size           = var.meta_disk_size
      iops                  = var.meta_disk_iops
      delete_on_termination = true
    }
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = merge(var.tags, { Name = local.hostnames[0] })

  depends_on = [data.aws_subnet.az1, terraform_data.overlay_ip_check, data.aws_route_table.extra]
}

resource "aws_instance" "secondary" {
  ami                         = var.ami
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_az2
  vpc_security_group_ids      = [var.security_group_id]
  key_name                    = var.key_name != "" ? var.key_name : null
  iam_instance_profile        = var.iam_instance_profile != "" ? var.iam_instance_profile : null
  associate_public_ip_address = false
  source_dest_check           = false
  user_data                   = jsonencode(merge(local.user_data_base, { node_index = "1" }))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.boot_disk_size
    delete_on_termination = true
  }

  dynamic "ebs_block_device" {
    for_each = toset(local.meta_devices)
    content {
      device_name           = ebs_block_device.value
      volume_type           = "gp3"
      volume_size           = var.meta_disk_size
      iops                  = var.meta_disk_iops
      delete_on_termination = true
    }
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = merge(var.tags, { Name = local.hostnames[1] })

  depends_on = [data.aws_subnet.az2, terraform_data.overlay_ip_check, data.aws_route_table.extra]
}

# --- Internal NLB across both subnets (mgmt 443 + SSH 22) ---
resource "aws_lb" "this" {
  count = var.nlb_enabled ? 1 : 0

  name               = local.nlb_name
  load_balancer_type = "network"
  internal           = var.nlb_scheme == "internal"
  subnets            = [var.subnet_az1, var.subnet_az2]
  tags               = var.tags
}

resource "aws_lb_target_group" "https" {
  count = var.nlb_enabled ? 1 : 0

  name        = local.tg443_name
  port        = 443
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  tags        = var.tags
}

# SSH target group health-checks 4505 so SSH lands on the ACTIVE node.
resource "aws_lb_target_group" "ssh" {
  count = var.nlb_enabled ? 1 : 0

  name        = local.tg22_name
  port        = 22
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  tags        = var.tags

  health_check {
    protocol = "TCP"
    port     = "4505"
  }
}

resource "aws_lb_target_group_attachment" "https" {
  for_each = var.nlb_enabled ? {
    primary   = aws_instance.primary.private_ip
    secondary = aws_instance.secondary.private_ip
  } : {}

  target_group_arn = aws_lb_target_group.https[0].arn
  target_id        = each.value
  port             = 443
}

resource "aws_lb_target_group_attachment" "ssh" {
  for_each = var.nlb_enabled ? {
    primary   = aws_instance.primary.private_ip
    secondary = aws_instance.secondary.private_ip
  } : {}

  target_group_arn = aws_lb_target_group.ssh[0].arn
  target_id        = each.value
  port             = 22
}

resource "aws_lb_listener" "https" {
  count = var.nlb_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this[0].arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https[0].arn
  }
}

resource "aws_lb_listener" "ssh" {
  count = var.nlb_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this[0].arn
  port              = 22
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ssh[0].arn
  }
}
