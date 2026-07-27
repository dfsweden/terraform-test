output "cluster_ip" {
  description = "The floating cluster IP (internal load balancer frontend on the data subnet)."
  value       = local.cluster_ip
}

output "vm_ids" {
  value = [for idx in sort(keys(local.nodes)) : module.vm[idx].vm_id]
}

output "anvil_private_ips" {
  value = { for idx, nic in azurerm_network_interface.data : idx => nic.private_ip_address }
}

output "public_ips" {
  value = var.public_ip ? { for idx, pip in azurerm_public_ip.anvil : idx => pip.ip_address } : {}
}
