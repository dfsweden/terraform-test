# ============================================================
# Pre-flight validation for the Azure deployment - the same
# hard-stop-at-plan-time role the AWS preflight module plays,
# with Azure-appropriate checks:
#   - Azure CLI present and logged in
#   - the chosen VM sizes exist in the target location, and
#     support premium storage when a Premium_LRS disk was chosen
#   - the image resource exists (when image_id is used)
#   - dsx mode: the existing Anvil answers :8443 with the
#     supplied credentials; image-vs-cluster Major.Minor is
#     verified when the image carries an hs_version tag
#     (warning when it does not - Azure images are not
#     guaranteed to carry it, unlike the AWS AMIs)
#
# Note: there is no Azure equivalent of iam:SimulatePrincipalPolicy,
# so deployer-permission checks are weaker than on AWS - a missing
# RBAC permission surfaces at apply time instead.
#
# Requires: python3 and the Azure CLI on the machine running
# terraform.
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
    mode             = var.mode
    location         = var.location
    subscription     = var.subscription
    vm_sizes         = jsonencode(var.vm_sizes)
    premium_sizes    = jsonencode(var.premium_sizes)
    anvil_size       = var.anvil_size
    anvil_min_vcpus  = tostring(var.anvil_min_vcpus)
    anvil_min_mem_gb = tostring(var.anvil_min_mem_gb)
    dsx_size         = var.dsx_size
    dsx_min_vcpus    = tostring(var.dsx_min_vcpus)
    dsx_min_mem_gb   = tostring(var.dsx_min_mem_gb)
    image_id         = var.image_id
    image_sas_url    = var.image_sas_url
    check_anvil      = var.check_anvil ? "true" : "false"
    anvil_ip         = var.anvil_ip
    anvil_password   = var.anvil_password
    hsuser           = var.hsuser
  }

  lifecycle {
    postcondition {
      condition     = self.result.ok == "true"
      error_message = "Pre-flight validation FAILED - no resources were created. Resolve every item below and re-run (or set skip_preflight = true to bypass):\n${self.result.errors}"
    }
  }
}
