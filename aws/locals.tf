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
  aws_tags = merge(
    {
      for k, v in { customer = var.customer, owner = var.owner } :
      k => v if trimspace(v) != ""
    },
    var.tags,
  )

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

  # --- Elastic IPs created by this deployment (create_eips) ---
  # Kept separate from var.eip, which associates a pre-existing address: the
  # two are mutually exclusive (precondition in validation.tf).
  created_anvil_eip = var.create_eips ? one(aws_eip.anvil[*].public_ip) : ""

  # Allocation IDs are passed as LISTS, and every branch below has a length
  # that is known at plan: a splat over a counted resource is a known-length
  # list even when the IDs inside it are not yet known, whereas
  # `<unknown id> != ""` makes terraform refuse to plan the count at all.
  #
  # Anvil: the created address, else the looked-up one in standalone mode
  # (other modes give var.eip to the DSX instead).
  anvil_eip_allocation_ids = (
    var.create_eips
    ? aws_eip.anvil[*].id
    : (local.is_standalone && local.eip_allocation_id != "" ? [local.eip_allocation_id] : [])
  )

  # One per DSX node when created here; a lone var.eip lands on dsx[0] in the
  # modes that give it to the DSX, as before.
  dsx_eip_allocation_ids = (
    var.create_eips
    ? aws_eip.dsx[*].id
    : (!local.is_standalone && local.eip_allocation_id != "" ? [local.eip_allocation_id] : [])
  )

  # Extra deployer permissions needed only when this apply allocates addresses.
  eip_deployer_actions = var.create_eips ? [
    "ec2:AllocateAddress",
    "ec2:AssociateAddress",
    "ec2:DescribeAddresses",
  ] : []

  # Control-host-reachable REST endpoint (:8443) for readiness + cluster-ID
  # tagging. Multi-AZ uses the Primary's private IP because the overlay cluster
  # IP is not routable from outside the VPC (and the NLB fronts 443/22, not the
  # 8443 REST port). With create_eips the operator has no private path in at
  # all, so this uses the Anvil's public address - while the DSX still joins on
  # the private one (see local.anvil_ip).
  anvil_mgmt_endpoint = (
    local.is_multiaz
    ? one(module.anvil_ha_multiaz[*].primary_private_ip)
    : (local.created_anvil_eip != "" ? local.created_anvil_eip : local.anvil_ip)
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

  # --- Runtime IAM the NODE role must allow ---
  #
  # Derived from the product source, not guessed:
  # pd-system/pd-platform/extras/events.d/98.aws is the CTDB event handler that
  # moves any cluster-managed address, and it branches on the prefix length:
  #
  #   prefix != /32  -> aws ec2 assign-private-ip-addresses --allow-reassignment
  #                     aws ec2 unassign-private-ip-addresses     (on release)
  #   prefix == /32  -> aws ec2 replace-route, falling back to create-route,
  #                     over every table from floating_ip_route_table_ids(),
  #                     which itself calls describe-route-tables
  #
  # The ENI is resolved from IMDS (169.254.169.254), so that step needs no IAM.
  #
  # The SAME script serves the Anvil's HA cluster IP and a DSX portal floating
  # IP - one code path, so one set of permissions.
  fip_eni_actions = [
    "ec2:AssignPrivateIpAddresses",
    "ec2:UnassignPrivateIpAddresses",
  ]
  fip_route_actions = [
    "ec2:DescribeRouteTables",
    "ec2:CreateRoute",
    "ec2:ReplaceRoute",
    "ec2:DeleteRoute",
  ]

  # HA peer discovery filters describe-instances by tag:Name, which is
  # authorized by ec2:DescribeInstances - ec2:DescribeTags is deliberately NOT
  # required.
  anvil_ha_actions = concat([
    "ec2:DescribeInstances",
    "ec2:DescribeInstanceAttribute",
  ], local.fip_eni_actions)

  # DSX portal floating IPs run through the same handler, so the DSX nodes need
  # the same permissions. Pre-flight previously required NOTHING at runtime for
  # standalone and dsx modes, so a deployment whose node role could not move an
  # address passed cleanly and only failed later, at failover, on a live
  # cluster. Multi-AZ additionally needs the route actions: a portal address
  # cannot be a secondary IP inside two different AZ subnets, so it is carried
  # as a /32 over route tables.
  portal_fip_actions = (
    var.portal_floating_ips && var.dsx_count > 0
    ? (local.is_multiaz ? concat(local.fip_eni_actions, local.fip_route_actions) : local.fip_eni_actions)
    : []
  )

  preflight_instance_profile_actions = {
    standalone    = local.portal_fip_actions
    ha            = distinct(concat(local.anvil_ha_actions, local.portal_fip_actions))
    "ha-multi-az" = distinct(concat(local.anvil_ha_actions, local.fip_route_actions, local.portal_fip_actions))
    dsx           = local.portal_fip_actions
  }

  preflight_subnets = local.is_multiaz ? [var.subnet_az1, var.subnet_az2] : [var.subnet_public]

  # Allocation ID of the optional EIP. Resolved at root so a nonexistent
  # address fails the PLAN; the modules take the ID rather than the address.
  #
  # Guarded on var.eip rather than left to one(): with no EIP the data source
  # has count 0, one([]) returns NULL, and `null != ""` is TRUE - so every
  # deployment without an EIP planned an aws_eip_association with a null
  # allocation_id, which fails at apply. Caught by the first real plan.
  eip_allocation_id = var.eip != "" ? one(data.aws_eip.assoc[*].id) : ""

  # --- Ephemeral / instance-store detection ---
  # Read from the ROOT instance-type data sources that already exist for the
  # vCPU/memory minimums. Each anvil module used to look this up itself, but
  # every module is called with depends_on, which defers its data sources to
  # apply - so meta_devices was unknown at plan and the plan could not show
  # whether 0 or 4 EBS volumes would be created. Their count guards already
  # match the modules that need the flag: creates_anvil covers standalone / ha /
  # ha-multi-az, dsx_count > 0 covers dsx. Four duplicate lookups removed.
  anvil_has_ephemeral = one(data.aws_ec2_instance_type.anvil_minimum[*].instance_storage_supported)
  dsx_has_ephemeral   = one(data.aws_ec2_instance_type.dsx_minimum[*].instance_storage_supported)

  # --- Pinned cluster IP vs subnet_public (ha only) ---
  #
  # The EXACT OPPOSITE requirement to the multi-AZ check below, and it was
  # missing entirely. In single-AZ HA the cluster IP is a SECONDARY PRIVATE IP
  # assigned to an ENI in subnet_public, so it must fall INSIDE that subnet.
  # Nothing looked subnet_public up, so an out-of-range address passed the plan
  # and failed during apply, at
  #
  #   aws ec2 assign-private-ip-addresses ... --private-ip-addresses <ip>
  #
  # by which point the ENI exists and the Anvils are launching. Multi-AZ had its
  # mirror-image check at plan; the more common shape had none.
  #
  # An empty anvil_cluster_ip means "let AWS allocate one" and is not checked.
  ha_pinned_cluster_ip = local.is_ha && trimspace(var.anvil_cluster_ip) != ""

  # Falls back to a CIDR that contains only 0.0.0.0 when the check does not
  # apply, so the arithmetic below never sees a null.
  _ha_subnet_cidr = coalesce(one(data.aws_subnet.public[*].cidr_block), "0.0.0.0/32")
  _ha_ip_octets = (
    local.ha_pinned_cluster_ip
    ? [for o in split(".", trimspace(var.anvil_cluster_ip)) : tonumber(o)]
    : [0, 0, 0, 0]
  )
  _ha_ip_num = local._ha_ip_octets[0] * 16777216 + local._ha_ip_octets[1] * 65536 + local._ha_ip_octets[2] * 256 + local._ha_ip_octets[3]
  _ha_net_first = (
    tonumber(split(".", cidrhost(local._ha_subnet_cidr, 0))[0]) * 16777216
    + tonumber(split(".", cidrhost(local._ha_subnet_cidr, 0))[1]) * 65536
    + tonumber(split(".", cidrhost(local._ha_subnet_cidr, 0))[2]) * 256
    + tonumber(split(".", cidrhost(local._ha_subnet_cidr, 0))[3])
  )
  _ha_net_size = pow(2, 32 - tonumber(split("/", local._ha_subnet_cidr)[1]))

  ha_cluster_ip_inside_subnet = (
    local._ha_ip_num >= local._ha_net_first
    && local._ha_ip_num < local._ha_net_first + local._ha_net_size
  )

  # AWS reserves the first four addresses of every subnet (network, VPC router,
  # DNS, future use) and the last (broadcast). Assigning one of those to the
  # cluster IP is rejected at apply, so it is worth catching here too.
  ha_cluster_ip_reserved = (
    local._ha_ip_num < local._ha_net_first + 4
    || local._ha_ip_num >= local._ha_net_first + local._ha_net_size - 1
  )

  # --- Overlay cluster IP vs the VPC CIDRs (ha-multi-az only) ---
  # IPv4 maths for the inside/outside-VPC-CIDR test (no cidrcontains() in HCL).
  # anvil_cluster_ip is validated as a bare IPv4 literal, so tonumber() here
  # cannot be handed something that is not an octet.
  multiaz_vpc_cidrs = [
    for a in flatten(data.aws_vpc.multiaz[*].cidr_block_associations) : a.cidr_block
  ]
  _ip_octets = local.is_multiaz ? [for o in split(".", var.anvil_cluster_ip) : tonumber(o)] : [0, 0, 0, 0]
  _ip_num    = local._ip_octets[0] * 16777216 + local._ip_octets[1] * 65536 + local._ip_octets[2] * 256 + local._ip_octets[3]
  _cidr_ranges = [
    for c in local.multiaz_vpc_cidrs : {
      first = (
        tonumber(split(".", cidrhost(c, 0))[0]) * 16777216
        + tonumber(split(".", cidrhost(c, 0))[1]) * 65536
        + tonumber(split(".", cidrhost(c, 0))[2]) * 256
        + tonumber(split(".", cidrhost(c, 0))[3])
      )
      size = pow(2, 32 - tonumber(split("/", c)[1]))
    }
  ]
  cluster_ip_inside_vpc = anytrue([
    for r in local._cidr_ranges : local._ip_num >= r.first && local._ip_num < r.first + r.size
  ])
}

# The 5-character per-deployment tail. It lives in state and is stable across
# applies - but ONLY while the state survives.
#
# Lose or recreate the state and a new suffix is generated, so every instance
# Name tag and the security group name change. That matters more than it looks:
# HA peer and cluster-IP discovery resolve nodes by tag:Name, so the running
# cluster would no longer match what Terraform believes it deployed. It is also
# how an Azure custom role name collided with its own not-yet-propagated
# deletion (HS-41971). Treat the state file as part of the deployment.
resource "random_string" "run_suffix" {
  length  = 5
  lower   = true
  upper   = false
  numeric = true
  special = false
}
