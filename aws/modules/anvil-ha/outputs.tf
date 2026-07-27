output "primary_instance_id" {
  value = aws_instance.primary.id
}

output "secondary_instance_id" {
  value = aws_instance.secondary.id
}

output "instance_ids" {
  value = [aws_instance.primary.id, aws_instance.secondary.id]
}

output "primary_private_ip" {
  value = aws_instance.primary.private_ip
}

output "cluster_ip" {
  description = "The floating cluster IP (pinned, or auto-allocated on the Secondary's pre-created ENI)."
  value       = local.cluster_ip
}

output "password" {
  description = "The HA cluster admin password is the Primary node's EC2 instance ID."
  value       = aws_instance.primary.id
}

output "secondary_eni_id" {
  description = "Pre-created Secondary ENI (managed by Terraform state - destroyed with the deployment, unlike the Ansible tracking-file approach)."
  value       = aws_network_interface.secondary.id
}

output "has_ephemeral_storage" {
  value = local.has_ephemeral
}
