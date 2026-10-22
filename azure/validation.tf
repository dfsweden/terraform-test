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
      condition     = !var.create_resource_group || var.location != ""
      error_message = "create_resource_group = true needs location (the region cannot be inherited from a group that does not exist yet)."
    }

    precondition {
      condition     = !var.create_resource_group || var.virtual_network_resource_group != ""
      error_message = "create_resource_group = true needs virtual_network_resource_group: the pre-existing VNet cannot live in the group being created."
    }

    precondition {
      condition     = !(var.create_resource_group && var.image_sas_url != "" && var.image_resource_group == "")
      error_message = "With create_resource_group and image_sas_url, set image_resource_group (auto-created if missing): otherwise destroy deletes the resource group INCLUDING the staged image, forcing a re-download on the next apply."
    }

    precondition {
      condition     = !local.is_ha_pair || (length(trimspace(var.ha_subnet_name)) > 0 && !startswith(trimspace(var.ha_subnet_name), "<"))
      error_message = "ha and ha-multi-az modes need ha_subnet_name: a dedicated HA heartbeat subnet (a /29, not shared with other instances; a subnet spans every zone, so one serves both zonal Anvils). On Azure the heartbeat subnet IS the peer-discovery mechanism - the product's Azure provisioning has no node_index support, so single-NIC HA cannot pair (verified 2026-07-28)."
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

    # --- Static IPs must belong to the data subnet ---
    # data.azurerm_subnet.data resolves at plan, so all three of these fail
    # before a NIC is created rather than part-way through the apply.
    precondition {
      condition     = length(local.pinned_ips_outside_subnet) == 0
      error_message = "static IP(s) outside the data subnet ${local.data_subnet_cidr}: ${join(", ", local.pinned_ips_outside_subnet)}. anvil_node_ips, dsx_static_ips and anvil_data_cluster_ip are all assigned to NICs in ${var.data_subnet_name}."
    }

    precondition {
      condition     = length(local.pinned_ips_reserved) == 0
      error_message = "static IP(s) in Azure's reserved range for ${local.data_subnet_cidr}: ${join(", ", local.pinned_ips_reserved)}. Azure reserves the first four addresses of every subnet (network, default gateway, two DNS) and the last (broadcast)."
    }

    precondition {
      condition     = length(local.pinned_ips_duplicated) == 0
      error_message = "the same static IP is pinned to more than one node: ${join(", ", local.pinned_ips_duplicated)}. Each NIC needs its own address."
    }

    # ha has exactly two Anvils, so a partial list is always a mistake: with one
    # entry Anvil1 got a static IP and Anvil2 silently fell back to Dynamic.
    precondition {
      condition     = !local.is_ha_pair || contains([0, 2], length(var.anvil_node_ips))
      error_message = "anvil_node_ips must be empty (both Anvils dynamic) or contain exactly 2 addresses, one per Anvil - ${length(var.anvil_node_ips)} given."
    }

    precondition {
      condition     = length(var.dsx_static_ips) <= var.dsx_count
      error_message = "dsx_static_ips has ${length(var.dsx_static_ips)} addresses but only ${var.dsx_count} DSX node(s) are being created - the extra entries would be silently ignored."
    }

    # --- ha-multi-az placement ---
    # Zone membership and duplicates are variable validations (malformed in
    # any mode); the SHAPE depends on the mode, so it is checked here.
    precondition {
      condition     = !local.is_multiaz || length(var.anvil_zones) == 2
      error_message = "ha-multi-az needs anvil_zones with exactly 2 entries (one per Anvil, in node order) - ${length(var.anvil_zones)} given. Two different zones is the point of the mode; for a same-zone pair use deployment_mode = \"ha\"."
    }

    precondition {
      condition     = !local.is_multiaz || var.dsx_count == 0 || length(var.dsx_zones) > 0
      error_message = "ha-multi-az with dsx_count > 0 needs at least one dsx_zones entry: there is no DSX availability set in this mode, so every DSX node is zonal (round-robin over the list)."
    }

    precondition {
      condition     = !local.is_multiaz || !var.use_proximity_placement_group
      error_message = "ha-multi-az cannot use a proximity placement group - a PPG pins its members to ONE zone, the opposite of spreading the Anvils across two. Set use_proximity_placement_group = false, or use deployment_mode = \"ha\" for a single-zone, latency-optimised pair."
    }

    precondition {
      condition     = !local.is_multiaz || var.availability_set_name == ""
      error_message = "ha-multi-az places every VM in an availability zone, and Azure allows a VM in an availability set OR a zone, never both - leave availability_set_name empty."
    }

    # Kept here rather than as variable validations: a failing variable
    # validation prints the value even for a sensitive variable, and this one
    # is the cluster admin password (verified on terraform 1.9.8). A
    # precondition reports only the expression.
    #
    # Azure's own VM password policy is the full set below, not just a length:
    # 12-72 characters AND at least three of the four character classes. A
    # 12-character all-lowercase password used to pass the plan and fail at VM
    # creation with ProvisioningState/Failed, after the disks and NICs existed.
    precondition {
      condition     = length(var.admin_password) >= 12
      error_message = "admin_password must be at least 12 characters (Azure VM password policy)."
    }

    precondition {
      condition     = length(var.admin_password) <= 72
      error_message = "admin_password must be at most 72 characters (Azure VM password policy)."
    }

    precondition {
      condition = length([
        for pattern in ["[a-z]", "[A-Z]", "[0-9]", "[^a-zA-Z0-9]"] :
        pattern if can(regex(pattern, var.admin_password))
      ]) >= 3
      error_message = "admin_password must contain at least THREE of: lowercase, uppercase, digit, special character (Azure VM password policy). Note the separate rule below forbidding \" \\ ` and $, so pick a different special character."
    }

    precondition {
      condition     = !can(regex("[\"\\\\$`]", var.admin_password))
      error_message = "admin_password must not contain double quotes, backslashes, backticks or dollar signs (it is passed through the hs-init-admin-pw shell command, same as the ARM template)."
    }

    # A <PLACEHOLDER> password satisfies both checks above - it is long enough
    # and contains no forbidden metacharacter - so without this an unedited
    # example applies cleanly and produces a cluster whose admin password is
    # literally "<SET_AT_APPLY_TIME>". Kept as a precondition, like the others,
    # so the message cannot echo the value.
    precondition {
      condition     = !startswith(var.admin_password, "<")
      error_message = "admin_password is still a <PLACEHOLDER> - pass the real password, e.g. -var \"admin_password=$(cat ~/.hs-lab-pw)\"."
    }
  }
}
