# ============================================================
# 2-node High-Availability Anvil (single AZ) - Terraform port
# of the aws_provision_anvil_ha Ansible role. Mirrors the AWS
# CloudFormation "High Availability" deployment.
#
# Cluster IP atomicity: the Secondary node's ENI is pre-created
# with the cluster IP attached, then the Secondary launches
# BOUND to that ENI - so the cluster IP is present in IMDS from
# boot second 0 and pd-first-boot never races the IP assignment.
# ============================================================

data "aws_ec2_instance_type" "anvil" {
  instance_type = var.instance_type
}

locals {
  pinned        = trimspace(var.cluster_ip) != ""
  has_ephemeral = data.aws_ec2_instance_type.anvil.instance_storage_supported
  meta_devices  = local.has_ephemeral ? [] : slice(["/dev/sdb", "/dev/sdc", "/dev/sdd", "/dev/sde"], 0, var.meta_disk_count)
  raid_opt      = var.raid_type == "stripe" ? "raid0" : "raid1"

  # Node 0 = Primary, node 1 = Secondary. The hostname is reused verbatim as
  # the EC2 Name tag - HA peer / cluster-IP discovery resolves nodes by
  # tag:Name, so the instances must not be renamed.
  hostnames = ["anvil-1-${var.name_suffix}", "anvil-2-${var.name_suffix}"]

  # eth0 of the Secondary carries cluster_ips only when an explicit cluster
  # IP is pinned; otherwise it is auto-discovered from the secondary private
  # IP assigned on the pre-created ENI.
  eth0_primary = { roles = var.node_roles, mtu = var.network_mtu }
  eth0_secondary = merge(
    local.eth0_primary,
    { for k, v in { cluster_ips = [var.cluster_ip] } : k => v if local.pinned },
  )

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

  user_data_base = merge(
    {
      cluster = { password_auth = true }
      nodes   = local.nodes_map
    },
    {
      for k, v in { aws = { iam_admin_group = var.iam_admin_group } } :
      k => v if trimspace(var.iam_admin_group) != ""
    },
  )

  aws_cli = join(" ", concat(
    ["aws", "--region", var.region],
    var.aws_profile != "" ? ["--profile", var.aws_profile] : [],
  ))
}

# --- Cluster (floating) IP - pre-create the Secondary's ENI ---
# Auto-allocation: AWS picks one free secondary private IP at ENI creation
# (private_ips_count). Pinned: the IP is assigned by the CLI step below
# BEFORE the Secondary instance launches (the instance depends on it), so
# either way the IP is on the ENI before first boot.
resource "aws_network_interface" "secondary" {
  subnet_id         = var.subnet_id
  security_groups   = [var.security_group_id]
  private_ips_count = local.pinned ? null : 1
  tags              = var.tags
}

resource "terraform_data" "pin_cluster_ip" {
  count = local.pinned ? 1 : 0

  triggers_replace = [aws_network_interface.secondary.id, var.cluster_ip]

  provisioner "local-exec" {
    command = "${local.aws_cli} ec2 assign-private-ip-addresses --network-interface-id ${aws_network_interface.secondary.id} --private-ip-addresses ${var.cluster_ip}"
  }
}

locals {
  # Auto-allocated cluster IP = the ENI's non-primary private IP.
  cluster_ip = (
    local.pinned
    ? var.cluster_ip
    : one(setsubtract(aws_network_interface.secondary.private_ips, [aws_network_interface.secondary.private_ip]))
  )
}

# --- Primary Anvil (auto-creates its own ENI) ---
resource "aws_instance" "primary" {
  ami                         = var.ami
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  key_name                    = var.key_name != "" ? var.key_name : null
  iam_instance_profile        = var.iam_instance_profile != "" ? var.iam_instance_profile : null
  associate_public_ip_address = false
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
}

# --- Secondary Anvil, bound to the pre-created ENI ---
# subnet / security group / public-IP settings come from the ENI and must
# not be set here.
resource "aws_instance" "secondary" {
  ami                  = var.ami
  instance_type        = var.instance_type
  key_name             = var.key_name != "" ? var.key_name : null
  iam_instance_profile = var.iam_instance_profile != "" ? var.iam_instance_profile : null
  user_data            = jsonencode(merge(local.user_data_base, { node_index = "1" }))

  network_interface {
    network_interface_id = aws_network_interface.secondary.id
    device_index         = 0
  }

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

  # A pinned cluster IP must be on the ENI before first boot.
  depends_on = [terraform_data.pin_cluster_ip]
}
