output "vm_ids" {
  value = [for idx in sort(keys(local.nodes)) : module.vm[idx].vm_id]
}

output "private_ips" {
  value = [for idx in sort(keys(local.nodes)) : azurerm_network_interface.data[idx].private_ip_address]
}

output "public_ips" {
  value = var.public_ip ? [for idx in sort(keys(local.nodes)) : azurerm_public_ip.dsx[idx].ip_address] : []
}
