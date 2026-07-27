output "vm_id" {
  value = module.vm.vm_id
}

output "anvil_ip" {
  description = "The Anvil's data-subnet IP - the cluster/metadata IP for a standalone deployment."
  value       = azurerm_network_interface.data.private_ip_address
}

output "public_ip" {
  value = var.public_ip ? azurerm_public_ip.anvil[0].ip_address : null
}
