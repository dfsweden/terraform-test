output "instance_ids" {
  value = aws_instance.dsx[*].id
}

output "private_ips" {
  value = aws_instance.dsx[*].private_ip
}

# The addresses actually associated, in node order. Read from the association
# resources rather than an input, so it reflects what was attached whether the
# caller supplied one address or one per node.
output "eip_public_ips" {
  value = aws_eip_association.this[*].public_ip
}

output "has_ephemeral_storage" {
  value = local.has_ephemeral
}
