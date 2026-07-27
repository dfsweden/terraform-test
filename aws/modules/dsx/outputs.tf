output "instance_ids" {
  value = aws_instance.dsx[*].id
}

output "private_ips" {
  value = aws_instance.dsx[*].private_ip
}

output "eip_public_ip" {
  value = var.eip != "" && var.node_count > 0 ? var.eip : null
}

output "has_ephemeral_storage" {
  value = local.has_ephemeral
}
