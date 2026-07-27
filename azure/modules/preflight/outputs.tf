output "warnings" {
  description = "Advisory pre-flight findings (newline separated, empty when clean)."
  value       = data.external.preflight.result.warnings
}

output "account" {
  value = data.external.preflight.result.account
}
