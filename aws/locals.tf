locals {
  is_standalone = var.deployment_mode == "standalone"
  is_ha         = var.deployment_mode == "ha"
  is_multiaz    = var.deployment_mode == "ha-multi-az"
  is_dsx_only   = var.deployment_mode == "dsx"
  creates_anvil = !local.is_dsx_only

  # Deployment label + per-deployment 5-char random tail, mirroring the
  # Ansible naming: anvil-1-<label>-<5char> / dsx-1-<label>-<5char>.
  # An empty label is OK - the random tail alone is used.
  name_suffix = (
    trimspace(var.random_name) != ""
    ? "${trimspace(var.random_name)}-${random_string.run_suffix.result}"
    : random_string.run_suffix.result
  )

  # customer / owner are OPTIONAL tag values - when empty the tag key is
  # omitted from every resource (no empty-valued tags).
  aws_tags = {
    for k, v in { customer = var.customer, owner = var.owner } :
    k => v if trimspace(v) != ""
  }

  # Instance profile may be given as a name or an ARN - aws_instance wants the name.
  iam_instance_profile = (
    trimspace(var.iam_instance_profile_name) != ""
    ? replace(var.iam_instance_profile_name, "/^.*instance-profile\\//", "")
    : ""
  )

  # Security group: reuse when supplied, else the one created below.
  security_group_id = (
    trimspace(var.security_group_id) != ""
    ? var.security_group_id
    : coalesce(
      one(aws_security_group.cluster[*].id),
      one(aws_security_group.dsx[*].id),
    )
  )

  # --- Cluster facts published by the Anvil modules (or supplied for dsx mode) ---
  # anvil_ip is the DSX metadata / join target:
  #   standalone  -> the Anvil's IP (EIP when set, else private IP)
  #   ha          -> the floating cluster IP (pinned or auto-allocated)
  #   ha-multi-az -> the overlay cluster IP (outside the VPC CIDR)
  #   dsx         -> the existing cluster's IP, from var.anvil_ip
  anvil_ip = coalesce(
    one(module.anvil_standalone[*].anvil_ip),
    one(module.anvil_ha[*].cluster_ip),
    local.is_multiaz ? var.anvil_cluster_ip : null,
    trimspace(var.anvil_ip) != "" ? var.anvil_ip : null,
  )

  # A fresh cluster's admin password is its Primary Anvil instance ID.
  anvil_password = coalesce(
    one(module.anvil_standalone[*].instance_id),
    one(module.anvil_ha[*].primary_instance_id),
    one(module.anvil_ha_multiaz[*].primary_instance_id),
    trimspace(var.anvil_password) != "" ? var.anvil_password : null,
  )

  # Control-host-reachable REST endpoint (:8443) for readiness + cluster-ID
  # tagging. Multi-AZ uses the Primary's private IP because the overlay
  # cluster IP is not routable from outside the VPC (and the NLB fronts
  # 443/22, not the 8443 REST port).
  anvil_mgmt_endpoint = (
    local.is_multiaz
    ? one(module.anvil_ha_multiaz[*].primary_private_ip)
    : local.anvil_ip
  )

  # Every instance created this apply - the Terraform state replaces the
  # Ansible temp_aws_resources_<timestamp> tracking files.
  all_instance_ids = flatten([
    module.anvil_standalone[*].instance_id,
    module.anvil_ha[*].instance_ids,
    module.anvil_ha_multiaz[*].instance_ids,
    module.dsx[*].instance_ids,
  ])

  # --- Pre-flight action lists (verbatim from the Ansible role defaults) ---
  preflight_deployer_actions = {
    standalone = [
      "ec2:RunInstances",
      "ec2:CreateTags",
      "ec2:CreateSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateVolume",
      "ec2:AttachVolume",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeInstanceTypes", # for ephemeral-storage detection
      "iam:PassRole",
    ]
    ha = [
      "ec2:RunInstances",
      "ec2:CreateTags",
      "ec2:CreateSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateVolume",
      "ec2:AttachVolume",
      "ec2:AssignPrivateIpAddresses",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeInstanceTypes",
      "iam:PassRole",
    ]
    "ha-multi-az" = [
      "ec2:RunInstances",
      "ec2:CreateTags",
      "ec2:CreateSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateVolume",
      "ec2:AttachVolume",
      "ec2:ModifyInstanceAttribute", # source/dest check off
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeSubnets",
      "ec2:DescribeRouteTables",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:AddTags",
      "iam:PassRole",
    ]
    dsx = [
      "ec2:RunInstances",
      "ec2:CreateTags",
      "ec2:CreateSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateVolume",
      "ec2:AttachVolume",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeImages", # for the AMI hs_version compatibility check
      "iam:PassRole",
    ]
  }

  # Runtime IAM the Anvil instance profile must allow. HA peer discovery
  # filters describe-instances by tag:Name, which is authorized by
  # ec2:DescribeInstances - ec2:DescribeTags is deliberately NOT required.
  preflight_instance_profile_actions = {
    standalone = []
    ha = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceAttribute",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses",
    ]
    "ha-multi-az" = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceAttribute",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:ReplaceRoute",
      "ec2:DescribeRouteTables",
    ]
    dsx = []
  }

  preflight_subnets = local.is_multiaz ? [var.subnet_az1, var.subnet_az2] : [var.subnet_public]
}

resource "random_string" "run_suffix" {
  length  = 5
  lower   = true
  upper   = false
  numeric = true
  special = false
}
