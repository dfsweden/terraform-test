# ============================================================
# Single-node (Standalone) Anvil - Terraform port of the
# aws_provision_anvil_node Ansible role.
# ============================================================

# Ephemeral / instance-store detection: on types with built-in NVMe drives
# the metadata EBS volumes are skipped (Hammerspace uses the built-in
# drives). The boot volume is ALWAYS provisioned.
locals {
  has_ephemeral = var.has_ephemeral
  meta_devices  = local.has_ephemeral ? [] : slice(["/dev/sdb", "/dev/sdc", "/dev/sdd", "/dev/sde"], 0, var.meta_disk_count)
  raid_opt      = var.raid_type == "stripe" ? "raid0" : "raid1"

  node_base = {
    ha_mode = "Standalone"
    networks = {
      eth0 = {
        mtu   = var.network_mtu
        dhcp  = true
        roles = ["data", "mgmt"]
      }
    }
  }

  # node.storage.options = raid0|raid1 only with >1 metadata disks on an
  # EBS-backed type (no RAID needed for a single disk; ephemeral types
  # manage their own drives).
  node_storage = {
    for k, v in { storage = { options = [local.raid_opt] } } :
    k => v if !local.has_ephemeral && var.meta_disk_count > 1
  }
  node = merge(local.node_base, local.node_storage)

  aws_block = {
    for k, v in { aws = { iam_admin_group = var.iam_admin_group } } :
    k => v if trimspace(var.iam_admin_group) != ""
  }

  user_data = merge(
    {
      cluster = { password_auth = false }
      node    = local.node
    },
    local.aws_block,
  )
}

resource "aws_instance" "anvil" {
  ami                         = var.ami
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  key_name                    = var.key_name != "" ? var.key_name : null
  iam_instance_profile        = var.iam_instance_profile != "" ? var.iam_instance_profile : null
  associate_public_ip_address = false
  user_data                   = jsonencode(local.user_data)

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

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    # Hammerspace reads user_data ONCE, at first boot. Without this, editing
    # anything that feeds it - MTU, node roles, iam_admin_group, raid type, the
    # cluster IP - produces a diff terraform applies while the running node
    # keeps its original configuration: the apply reports success and nothing
    # on the node changes.
    #
    # Deliberately ignore_changes and NOT user_data_replace_on_change = true:
    # the latter is "correct" but destroys and recreates a live Anvil or DSX on
    # an incidental edit, which is far worse. To change any of these, rebuild
    # the node. Azure's hs-vm module does the same with custom_data.
    ignore_changes = [user_data]
  }

}

# Optional Elastic IP association (pre-existing EIP, looked up by address).
resource "aws_eip_association" "this" {
  count         = length(var.eip_allocation_ids)
  instance_id   = aws_instance.anvil.id
  allocation_id = var.eip_allocation_ids[count.index]
}
