# ============================================================
# Cross-variable input validation - fails at plan time,
# before anything is created.
# ============================================================

resource "terraform_data" "validate_inputs" {
  lifecycle {
    precondition {
      condition     = length([for set in [var.image_id != "", var.marketplace_image != null, var.image_sas_url != ""] : set if set]) == 1
      error_message = "Set exactly ONE image source: image_id (managed/SIG image resource ID), marketplace_image (Azure Marketplace), or image_sas_url (read-only blob SAS URL to a Hammerspace .vhd)."
    }

    precondition {
      condition     = !local.is_ha || (length(trimspace(var.ha_subnet_name)) > 0 && !startswith(trimspace(var.ha_subnet_name), "<"))
      error_message = "ha mode needs ha_subnet_name: a dedicated HA heartbeat subnet (a /29 is recommended, not shared with other instances) for each Anvil's second NIC."
    }

    precondition {
      condition = (
        !local.is_dsx_only
        || (length(trimspace(var.anvil_ip)) > 0 && !startswith(trimspace(var.anvil_ip), "<"))
      )
      error_message = "deployment_mode 'dsx' adds DSX node(s) to an EXISTING cluster - anvil_ip must identify it (admin_password must be that cluster's password)."
    }

    precondition {
      condition     = local.is_dsx_only ? var.dsx_count > 0 : true
      error_message = "deployment_mode 'dsx' with dsx_count = 0 would create nothing."
    }
  }
}
