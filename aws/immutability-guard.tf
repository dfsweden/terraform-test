# ============================================================
# OPTIONAL: block a re-apply that would modify an existing cluster.
#
# DISABLED BY DEFAULT - uncomment the two blocks below to enable.
# Recommended for production; left off so lab teardown stays a single
# `terraform destroy` (see "Cost" below).
#
# ---------------------------------------------------------------------------
# Why
# ---------------------------------------------------------------------------
# Re-applying against an existing cluster is NOT supported: the nodes read
# their configuration from user_data once, at first boot, and Hammerspace has
# no path to re-read it. Worse, several inputs are ForceNew on aws_instance -
# pointing an existing state at a new hs_ami or a larger anvil_instance_type
# plans a REPLACEMENT of both Anvils, which destroys the cluster. Terraform
# will do that without comment if you approve the plan.
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
# That is intentional friction for a production cluster. It is also why this
# ships disabled - tools/terraform/azure/scripts/test-portal-floating-ips.sh
# and the lab harnesses destroy on every run.
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
#   # them either replaces a node outright or reaches the node only through
#   # user_data, which is ignore_changes'd and therefore never re-read.
#   immutable_fingerprint = sha256(jsonencode({
#     deployment_mode            = var.deployment_mode
#     name_suffix                = local.name_suffix
#     region                     = var.region
#     vpc                        = var.vpc
#     subnet_public              = var.subnet_public
#     az1                        = var.az1
#     az2                        = var.az2
#     subnet_az1                 = var.subnet_az1
#     subnet_az2                 = var.subnet_az2
#     hs_ami                     = var.hs_ami
#     key_name                   = var.key_name
#     iam_instance_profile_name  = var.iam_instance_profile_name
#     iam_admin_group            = var.iam_admin_group
#     security_group_id          = var.security_group_id
#     network_mtu                = var.network_mtu
#     anvil_instance_type        = var.anvil_instance_type
#     anvil_boot_disk_size       = var.anvil_boot_disk_size
#     anvil_meta_disk_size       = var.anvil_meta_disk_size
#     anvil_meta_disk_count      = var.anvil_meta_disk_count
#     anvil_meta_disk_iops       = var.anvil_meta_disk_iops
#     anvil_raid_type            = var.anvil_raid_type
#     anvil_cluster_ip           = var.anvil_cluster_ip
#     anvil_cluster_ip_prefixlen = var.anvil_cluster_ip_prefixlen
#     route_table_ids            = var.route_table_ids
#     nlb_enabled                = var.nlb_enabled
#     nlb_scheme                 = var.nlb_scheme
#     dsx_count                  = var.dsx_count
#     dsx_instance_type          = var.dsx_instance_type
#     dsx_volumes                = var.dsx_volumes
#
#     # DELIBERATELY ABSENT - these do not touch a node:
#     #   customer, owner    tag values, applied with CreateTags
#     #   eip                association only; does not touch a node
#     #   sec_ip_cidr        edits the security group, does not replace a node
#     #   aws_profile, hsuser, anvil_password, cluster_id_tag_key,
#     #   wait_for_cluster, skip_preflight, check_sts_endpoint
#     #                      operational only, never reach a node
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
