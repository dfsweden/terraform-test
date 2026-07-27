output "deployment_mode" {
  value = var.deployment_mode
}

output "anvil_ip" {
  description = "Cluster / Anvil IP the DSX nodes join (standalone: Anvil NIC IP; ha: internal LB frontend / floating cluster IP; dsx: the supplied existing IP)."
  value       = local.anvil_ip
}

output "management_url" {
  description = "Management REST endpoint reachable from the deploying machine (public IP when one was created for a standalone Anvil)."
  value       = "https://${local.anvil_mgmt_endpoint}:8443"
}

output "anvil_vm_ids" {
  value = flatten([
    module.anvil_standalone[*].vm_id,
    module.anvil_ha[*].vm_ids,
  ])
}

output "anvil_public_ips" {
  value = {
    standalone = one(module.anvil_standalone[*].public_ip)
    ha         = try(one(module.anvil_ha[*].public_ips), null)
  }
}

output "dsx_vm_ids" {
  value = flatten(module.dsx[*].vm_ids)
}

output "dsx_private_ips" {
  value = flatten(module.dsx[*].private_ips)
}

output "network_security_group_id" {
  value = local.nsg_id
}

output "os_admin_username" {
  description = "OS-level VM account (not the Hammerspace login - that is 'admin' with your admin_password)."
  value       = local.admin_username
}

output "preflight_warnings" {
  value = var.skip_preflight ? "(pre-flight skipped by request)" : try(module.preflight[0].warnings, "")
}
