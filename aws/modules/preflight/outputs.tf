output "warnings" {
  description = "Advisory pre-flight findings (newline separated, empty when clean)."
  value       = data.external.preflight.result.warnings
}

output "deployer_arn" {
  value = data.external.preflight.result.deployer_arn
}
