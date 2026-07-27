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
  description = "Control-host-reachable REST endpoint (:8443) - the overlay cluster IP is not routable from outside the VPC."
  value       = aws_instance.primary.private_ip
}

output "secondary_private_ip" {
  value = aws_instance.secondary.private_ip
}

output "cluster_ip" {
  description = "The overlay cluster IP (outside the VPC CIDR, floated via route tables)."
  value       = var.cluster_ip
}

output "nlb_dns_name" {
  value = var.nlb_enabled ? aws_lb.this[0].dns_name : null
}

output "password" {
  description = "The HA cluster admin password is the Primary node's EC2 instance ID."
  value       = aws_instance.primary.id
}

output "has_ephemeral_storage" {
  value = local.has_ephemeral
}
