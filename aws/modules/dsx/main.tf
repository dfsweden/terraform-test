# ============================================================
# DSX data-services node(s) - Terraform port of the
# aws_provision_dsx_node Ansible role.
# ============================================================

# Ephemeral / instance-store detection: on types with built-in NVMe drives
# the data EBS volumes are skipped (Hammerspace uses the built-in drives).
# The boot volume (/dev/sda1) is ALWAYS provisioned.
data "aws_ec2_instance_type" "dsx" {
  instance_type = var.instance_type

  lifecycle {
    # Product minimum for a DSX node: 8 vCPU / 16 GiB.
    postcondition {
      condition     = self.default_vcpus >= 8 && self.memory_size >= 16384
      error_message = "DSX instance type ${var.instance_type} is below the product minimum: has ${self.default_vcpus} vCPU / ${self.memory_size} MiB, needs at least 8 vCPU / 16 GiB."
    }
  }
}

locals {
  has_ephemeral = data.aws_ec2_instance_type.dsx.instance_storage_supported

  boot_volume  = one([for v in var.volumes : v if v.device_name == "/dev/sda1"])
  data_volumes = local.has_ephemeral ? [] : [for v in var.volumes : v if v.device_name != "/dev/sda1"]

  # Multi-AZ points the metadata at the OVERLAY cluster IP with its prefix
  # length (<ip>/<prefixlen>) and carries route_table_ids in the aws block,
  # so the DSX reaches the cluster IP across AZs via the same route tables
  # the Anvil manages.
  metadata_ips = var.multiaz ? ["${var.anvil_ip}/${var.cluster_ip_prefixlen}"] : [var.anvil_ip]

  aws_block = merge(
    {
      for k, v in { iam_admin_group = var.iam_admin_group } :
      k => v if trimspace(var.iam_admin_group) != ""
    },
    {
      for k, v in { route_table_ids = var.route_table_ids } :
      k => v if var.multiaz && length(var.route_table_ids) > 0
    },
  )

  user_data = merge(
    {
      cluster = {
        password_auth = false
        password      = var.anvil_password
        metadata      = { ips = local.metadata_ips }
      }
      node = {
        networks = {
          eth0 = {
            mtu   = var.network_mtu
            dhcp  = true
            roles = ["data", "mgmt"]
          }
        }
        features    = ["storage", "portal"]
        add_volumes = true
      }
    },
    { for k, v in { aws = local.aws_block } : k => v if length(local.aws_block) > 0 },
  )
}

# One numbered instance per node: dsx-1-<suffix>, dsx-2-<suffix>, ...
resource "aws_instance" "dsx" {
  count = var.node_count

  ami                         = var.ami
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids      = [var.security_group_id]
  key_name                    = var.key_name != "" ? var.key_name : null
  iam_instance_profile        = var.iam_instance_profile != "" ? var.iam_instance_profile : null
  associate_public_ip_address = false
  user_data                   = jsonencode(local.user_data)

  root_block_device {
    volume_type           = local.boot_volume.volume_type
    volume_size           = local.boot_volume.volume_size
    iops                  = local.boot_volume.iops
    throughput            = local.boot_volume.throughput
    encrypted             = local.boot_volume.encrypted
    kms_key_id            = local.boot_volume.kms_key_id
    delete_on_termination = local.boot_volume.delete_on_termination
  }

  dynamic "ebs_block_device" {
    for_each = { for v in local.data_volumes : v.device_name => v }
    content {
      device_name           = ebs_block_device.value.device_name
      volume_type           = ebs_block_device.value.volume_type
      volume_size           = ebs_block_device.value.volume_size
      iops                  = ebs_block_device.value.iops
      throughput            = ebs_block_device.value.throughput
      encrypted             = ebs_block_device.value.encrypted
      kms_key_id            = ebs_block_device.value.kms_key_id
      delete_on_termination = ebs_block_device.value.delete_on_termination
    }
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = merge(var.tags, { Name = "dsx-${count.index + 1}-${var.name_suffix}" })
}

# Optional Elastic IP association with the first DSX node.
data "aws_eip" "this" {
  count     = var.eip != "" && var.node_count > 0 ? 1 : 0
  public_ip = var.eip
}

resource "aws_eip_association" "this" {
  count         = var.eip != "" && var.node_count > 0 ? 1 : 0
  instance_id   = aws_instance.dsx[0].id
  allocation_id = data.aws_eip.this[0].id
}
