# ============================================================
# Cross-variable input validation (the equivalent of the Ansible
# assert + "required variables are configured" pre-flight tasks).
# Fails at plan time, before anything is created.
# ============================================================

resource "terraform_data" "validate_inputs" {
  lifecycle {
    precondition {
      condition = (
        local.is_multiaz
        || (length(trimspace(var.subnet_public)) > 0 && !startswith(trimspace(var.subnet_public), "<"))
      )
      error_message = "subnet_public must be set (not empty, not a <PLACEHOLDER>) for standalone / ha / dsx deployments."
    }

    precondition {
      condition = (
        !(local.is_ha || local.is_multiaz)
        || (length(trimspace(var.iam_instance_profile_name)) > 0 && !startswith(trimspace(var.iam_instance_profile_name), "<"))
      )
      error_message = "iam_instance_profile_name is required for ha and ha-multi-az deployments (the Anvils need runtime EC2 permissions for HA failover)."
    }

    precondition {
      condition = (
        !local.is_multiaz
        || alltrue([
          for v in [var.az1, var.az2, var.subnet_az1, var.subnet_az2, var.anvil_cluster_ip] :
          length(trimspace(v)) > 0 && !startswith(trimspace(v), "<")
        ])
      )
      error_message = "ha-multi-az needs az1, az2, subnet_az1, subnet_az2 and an overlay anvil_cluster_ip. See examples/ha-multi-az.tfvars."
    }

    precondition {
      condition     = !local.is_multiaz || trimspace(var.az1) != trimspace(var.az2)
      error_message = "az1 and az2 are identical - multi-AZ HA requires two DIFFERENT availability zones."
    }

    precondition {
      condition = (
        !local.is_dsx_only
        || alltrue([
          for v in [var.anvil_ip, var.anvil_password] :
          length(trimspace(v)) > 0 && !startswith(trimspace(v), "<")
        ])
      )
      error_message = "deployment_mode 'dsx' adds DSX node(s) to an EXISTING cluster - anvil_ip and anvil_password must identify it. See examples/dsx-add-to-existing.tfvars."
    }

    precondition {
      condition     = local.is_dsx_only ? var.dsx_count > 0 : true
      error_message = "deployment_mode 'dsx' with dsx_count = 0 would create nothing."
    }

    # Kept here rather than as a variable validation: a failing variable
    # validation prints the value even for a sensitive variable, and this is a
    # cluster password (verified on terraform 1.9.8).
    # --- Elastic IPs ---
    precondition {
      condition     = !(var.create_eips && trimspace(var.eip) != "")
      error_message = "create_eips allocates NEW Elastic IPs; var.eip associates a pre-existing one. Set one or the other, not both."
    }

    precondition {
      condition     = !var.create_eips || local.is_standalone || local.is_dsx_only
      error_message = "create_eips is supported for standalone and dsx modes. The HA shapes reach the cluster on their floating cluster IP, which is a private address and is not an Elastic IP."
    }

    precondition {
      condition     = var.anvil_password == "" || !startswith(var.anvil_password, "<")
      error_message = "anvil_password still contains a <PLACEHOLDER> - set the existing cluster's admin password."
    }
  }
}
