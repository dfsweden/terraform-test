# ============================================================
# Pre-flight validation - Terraform port of the Ansible
# preflight.yml task files (HA / multi-AZ / DSX variants).
#
# Runs at PLAN time via an external data source, so a plain
# `terraform plan` is the equivalent of `-e dry_run=true`:
# every check runs, nothing is created, and a failed check
# hard-stops the run via the postcondition below.
#
# Requires: python3 and the AWS CLI on the machine running
# terraform (same prerequisites as the Ansible control host).
# ============================================================

terraform {
  required_providers {
    external = {
      source = "hashicorp/external"
    }
  }
}

data "external" "preflight" {
  program = ["python3", "${path.module}/scripts/preflight.py"]

  query = {
    mode                     = var.mode
    region                   = var.region
    profile                  = var.aws_profile
    vpc                      = var.vpc
    subnet_ids               = jsonencode(var.subnet_ids)
    deployer_actions         = jsonencode(var.deployer_actions)
    instance_profile         = var.iam_instance_profile_name
    instance_profile_actions = jsonencode(var.instance_profile_actions)
    check_sts                = var.check_sts ? "true" : "false"
    check_anvil              = var.check_anvil ? "true" : "false"
    anvil_ip                 = var.anvil_ip
    anvil_password           = var.anvil_password
    hsuser                   = var.hsuser
    hs_ami                   = var.hs_ami
  }

  lifecycle {
    postcondition {
      condition     = self.result.ok == "true"
      error_message = "Pre-flight validation FAILED - no resources were created. Resolve every item below and re-run (or set skip_preflight = true to bypass):\n${self.result.errors}"
    }
  }
}
