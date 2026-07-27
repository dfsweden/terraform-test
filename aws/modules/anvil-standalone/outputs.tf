output "instance_id" {
  value = aws_instance.anvil.id
}

output "private_ip" {
  value = aws_instance.anvil.private_ip
}

output "anvil_ip" {
  description = "IP the DSX nodes join: the EIP when one was associated, else the private IP."
  value       = var.eip != "" ? var.eip : aws_instance.anvil.private_ip
}

output "password" {
  description = "The Anvil admin password is its EC2 instance ID."
  value       = aws_instance.anvil.id
}

output "has_ephemeral_storage" {
  value = local.has_ephemeral
}
