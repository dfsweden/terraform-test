output "deployment_mode" {
  value = var.deployment_mode
}

output "name_suffix" {
  description = "Composed deployment label (random_name + 5-char random tail) used in all resource names."
  value       = local.name_suffix
}

output "security_group_id" {
  value = local.security_group_id
}

output "anvil_ip" {
  description = "Cluster / Anvil IP the DSX nodes join (standalone: node IP; ha: floating IP; ha-multi-az: overlay IP; dsx: the supplied existing IP)."
  value       = local.anvil_ip
}

output "anvil_password" {
  description = "Cluster admin password (a fresh cluster's password is its Primary Anvil instance ID)."
  value       = local.anvil_password
  sensitive   = true
}

output "anvil_instance_ids" {
  value = flatten([
    module.anvil_standalone[*].instance_id,
    module.anvil_ha[*].instance_ids,
    module.anvil_ha_multiaz[*].instance_ids,
  ])
}

output "anvil_primary_private_ip" {
  value = coalesce(
    one(module.anvil_standalone[*].private_ip),
    one(module.anvil_ha[*].primary_private_ip),
    one(module.anvil_ha_multiaz[*].primary_private_ip),
    "n/a",
  )
}

output "management_url" {
  description = "Management endpoint. ha-multi-az: the internal NLB (443). Other modes: the Anvil REST endpoint."
  value = (
    local.is_multiaz && var.nlb_enabled
    ? "https://${one(module.anvil_ha_multiaz[*].nlb_dns_name)}"
    : "https://${local.anvil_mgmt_endpoint}:8443"
  )
}

output "dsx_instance_ids" {
  value = flatten(module.dsx[*].instance_ids)
}

output "dsx_private_ips" {
  description = "Private IPs of the DSX nodes (the Terraform-state equivalent of the temp_dsx_ips_<timestamp> file)."
  value       = flatten(module.dsx[*].private_ips)
}

output "preflight_warnings" {
  value = var.skip_preflight ? "(pre-flight skipped by request)" : try(module.preflight[0].warnings, "")
}
