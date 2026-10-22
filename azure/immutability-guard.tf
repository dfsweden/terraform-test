# ============================================================
# OPTIONAL: block a re-apply that would modify an existing cluster.
#
# DISABLED BY DEFAULT - uncomment the two blocks below to enable.
# Recommended for production; left off so lab teardown stays a single
# `terraform destroy` (see "Cost" below).
#
# The AWS root carries the same guard, with the same reasoning:
# tools/terraform/aws/immutability-guard.tf
#
# ---------------------------------------------------------------------------
# Why
# ---------------------------------------------------------------------------
# Re-applying against an existing cluster is NOT supported: the nodes read
# their configuration from custom_data once, at first boot, and Hammerspace has
# no path to re-read it - which is why hs-vm sets ignore_changes on it. Several
# other inputs force a VM replacement, so pointing an existing state at a new
# image_id or a larger anvil_instance_type plans a REPLACEMENT of both Anvils,
# destroying the cluster. Terraform will do that without comment if you approve
# the plan.
#
# NOTHING about a live cluster may be changed by re-applying its state - not
# even dsx_count. Adding a DSX node is done from its OWN state with
# deployment_mode = "dsx" (see examples/dsx-add-to-existing.tfvars), which
# leaves the original deployment untouched. dsx_count is therefore IN the
# fingerprint like everything else.
#
# ---------------------------------------------------------------------------
# Why this mechanism and not another
# ---------------------------------------------------------------------------
# Measured on terraform 1.9.8:
#
#   prevent_destroy + a fingerprint in triggers_replace
#       unchanged config -> "No changes"
#       changed config   -> plan FAILS, before anything is touched
#
#   postcondition comparing self.output
#       changed config   -> plan says "1 to change" and succeeds; the condition
#                           fires during apply, after other resources may
#                           already have been modified. Too late.
#
#   check block
#       warns only - cannot stop an apply.
#
# prevent_destroy is therefore the only construct that gives a plan-time stop.
# It cannot be driven by a variable ("Error: Variables not allowed" - it must
# be a literal), which is why enabling this is a comment/uncomment rather than
# a tfvars setting.
#
# ---------------------------------------------------------------------------
# Cost: terraform destroy is blocked too
# ---------------------------------------------------------------------------
# prevent_destroy refuses ANY plan that destroys the resource, including a
# deliberate teardown. With the guard enabled, destroying is a two-step:
#
#     terraform state rm terraform_data.deployment_guard
#     terraform destroy
#
# That is intentional friction for a production cluster, and why this ships
# disabled - the lab harnesses destroy on every run.
#
# ---------------------------------------------------------------------------
# What the error looks like
# ---------------------------------------------------------------------------
# The message is fixed by terraform and cannot be customised:
#
#     Error: Instance cannot be destroyed
#       Resource terraform_data.deployment_guard has lifecycle.prevent_destroy
#       set, but the plan calls for this resource to be destroyed.
#
# It means: an input that cannot change after deployment has changed. Compare
# your tfvars against the fingerprint list below, or rebuild the deployment.
# ============================================================

# locals {
#   # Every input that cannot change once the cluster exists. Changing any of
#   # them either replaces a VM outright or reaches the node only through
#   # custom_data, which is ignore_changes'd and therefore never re-read.
#   immutable_fingerprint = sha256(jsonencode({
#     deployment_mode                = var.deployment_mode
#     name                           = var.name
#     prefix                         = local.prefix
#     subscription_id                = var.subscription_id
#     location                       = var.location
#     resource_group                 = var.resource_group
#     virtual_network_name           = var.virtual_network_name
#     virtual_network_resource_group = var.virtual_network_resource_group
#     data_subnet_name               = var.data_subnet_name
#     ha_subnet_name                 = var.ha_subnet_name
#     network_security_group_id      = var.network_security_group_id
#     image_id                       = var.image_id
#     image_sas_url                  = var.image_sas_url
#     image_generation               = var.image_generation
#     marketplace_image              = var.marketplace_image
#     admin_username                 = var.admin_username
#     anvil_instance_type            = var.anvil_instance_type
#     anvil_boot_disk_size           = var.anvil_boot_disk_size
#     anvil_boot_disk_type           = var.anvil_boot_disk_type
#     anvil_metadata_disk_size       = var.anvil_metadata_disk_size
#     anvil_metadata_disk_type       = var.anvil_metadata_disk_type
#     anvil_metadata_disk_iops       = var.anvil_metadata_disk_iops
#     anvil_metadata_disk_throughput = var.anvil_metadata_disk_throughput
#     anvil_data_cluster_ip          = var.anvil_data_cluster_ip
#     anvil_node_ips                 = var.anvil_node_ips
#     dsx_count                      = var.dsx_count
#     dsx_instance_type              = var.dsx_instance_type
#     dsx_boot_disk_size             = var.dsx_boot_disk_size
#     dsx_boot_disk_type             = var.dsx_boot_disk_type
#     dsx_data_disk_count            = var.dsx_data_disk_count
#     dsx_data_disk_size             = var.dsx_data_disk_size
#     dsx_data_disk_type             = var.dsx_data_disk_type
#     dsx_data_disk_striping         = var.dsx_data_disk_striping
#     public_ip_addresses            = var.public_ip_addresses
#     use_proximity_placement_group  = var.use_proximity_placement_group
#     proximity_placement_group_name = var.proximity_placement_group_name
#     availability_set_name          = var.availability_set_name
#     anvil_zones                    = var.anvil_zones
#     dsx_zones                      = var.dsx_zones
#
#     # DELIBERATELY ABSENT - these do not touch a node:
#     #   dsx_static_ips       only consumed for the DSX nodes being added
#     #   owner, tags          tag values, applied to the resources not the OS
#     #   boot_diagnostics     a VM setting, not a node rebuild
#     #   create_resource_group, image_resource_group
#     #                        where things live, not what the nodes are
#     #   admin_password       applied post-boot by the extension
#     #   hsuser, anvil_ip, cluster_id_tag_key, cluster_api_wait_retries,
#     #   wait_for_cluster, skip_preflight
#     #                        operational only, never reach a node
#   }))
# }
#
# resource "terraform_data" "deployment_guard" {
#   input            = local.immutable_fingerprint
#   triggers_replace = [local.immutable_fingerprint]
#
#   lifecycle {
#     prevent_destroy = true
#   }
# }
