# ============================================================
# Hammerspace Anvil + DSX provisioning - shared variables.
# Mirrors group_vars/all.yml of the Ansible playbook structure.
# Replace every placeholder in your .tfvars file before running.
# ============================================================

# --- Deployment mode (selects the equivalent of one playbook) ---
#   standalone   -> provision.yml              (single Anvil + DSX)
#   ha           -> provision-ha.yml           (2-node HA Anvil + DSX)
#   ha-multi-az  -> provision-ha-multi-az.yml  (cross-AZ HA Anvil + NLB + DSX)
#   dsx          -> provision-dsx.yml          (add DSX to an existing cluster)
variable "deployment_mode" {
  type        = string
  description = "Deployment shape: standalone | ha | ha-multi-az | dsx"

  validation {
    condition     = contains(["standalone", "ha", "ha-multi-az", "dsx"], var.deployment_mode)
    error_message = "deployment_mode must be one of: standalone, ha, ha-multi-az, dsx."
  }
}

# --- Identification / tagging ---
variable "customer" {
  type        = string
  default     = ""
  description = "Optional 'customer' tag value. Empty = tag key omitted entirely."

  validation {
    # AWS tag value limit.
    condition     = length(var.customer) <= 256
    error_message = "customer is used as an AWS tag value and must be 256 characters or fewer."
  }
}

variable "owner" {
  type        = string
  default     = "douglas"
  description = "'owner' tag value, applied to every resource - IT automation stops untagged VMs. Empty = tag key omitted entirely."

  validation {
    condition     = length(var.owner) <= 256
    error_message = "owner is used as an AWS tag value and must be 256 characters or fewer."
  }
}

variable "random_name" {
  type        = string
  default     = ""
  description = <<-EOT
    Deployment label used in instance names (anvil-1-<label>-<5char>,
    dsx-1-<label>-<5char>) and the security-group name. A 5-character random
    tail is always appended per deployment, so applying the same config in a
    second state yields distinguishable resources. Empty label is OK - the
    random tail alone is used.
  EOT

  validation {
    # Feeds instance Name tags and the security group name, and HA peer
    # discovery resolves nodes by tag:Name - keep it to safe characters.
    condition     = can(regex("^[A-Za-z0-9._-]*$", var.random_name)) && length(var.random_name) <= 32
    error_message = "random_name must be 32 characters or fewer, using only letters, digits, dot, underscore or hyphen."
  }
}

# --- AWS account / network (must already exist in YOUR account) ---
variable "region" {
  type        = string
  description = "AWS region, e.g. us-west-2"

  validation {
    condition     = length(trimspace(var.region)) > 0 && !startswith(trimspace(var.region), "<")
    error_message = "region must be set (not empty, not a <PLACEHOLDER>)."
  }
}

variable "vpc" {
  type        = string
  description = "Existing VPC ID, e.g. vpc-xxxxxxxx"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,}$", trimspace(var.vpc)))
    error_message = "vpc must be a VPC ID like vpc-0123456789abcdef0 (not empty, not a placeholder)."
  }
}

variable "subnet_public" {
  type        = string
  default     = ""
  description = "Subnet the nodes launch into (standalone / ha / dsx modes)."

  validation {
    condition     = var.subnet_public == "" || can(regex("^subnet-[0-9a-f]{8,}$", var.subnet_public))
    error_message = "subnet_public must be a subnet ID like subnet-0123456789abcdef0 (or empty for ha-multi-az, which uses subnet_az1/subnet_az2)."
  }
}

variable "key_name" {
  type        = string
  default     = ""
  description = "Existing EC2 key pair name. Empty = no key pair attached."

  validation {
    condition     = var.key_name == "" || (length(var.key_name) <= 255 && !startswith(var.key_name, "<"))
    error_message = "key_name must be an existing EC2 key pair name (255 characters or fewer), or empty for none - not a <PLACEHOLDER>."
  }
}

variable "aws_profile" {
  type        = string
  default     = ""
  description = "Named AWS CLI profile, or empty for the default credentials chain."

  validation {
    condition     = var.aws_profile == "" || can(regex("^[A-Za-z0-9._-]+$", var.aws_profile))
    error_message = "aws_profile must be a plain profile name - it is interpolated into the aws CLI command line."
  }
}

# --- IAM ---
variable "iam_instance_profile_name" {
  type        = string
  default     = ""
  description = <<-EOT
    IAM instance profile attached to the nodes (name or ARN). Optional for
    standalone/dsx; REQUIRED for ha and ha-multi-az (pre-flight enforces the
    runtime IAM actions on its role).
  EOT

  validation {
    # Accepts a bare name or a full ARN; locals.tf strips the ARN prefix.
    condition     = var.iam_instance_profile_name == "" || can(regex("^(arn:aws[a-z-]*:iam::[0-9]{12}:instance-profile/)?[\\w+=,.@-]{1,128}$", var.iam_instance_profile_name))
    error_message = "iam_instance_profile_name must be an instance profile name or ARN."
  }
}

variable "iam_admin_group" {
  type        = string
  default     = ""
  description = <<-EOT
    IAM group whose members may SSH to the Anvil (aws.iam_admin_group in
    user-data).

    FIXED AT DEPLOYMENT: this reaches the node only through user_data, which
    Hammerspace reads once at first boot and terraform now ignores on update.
    Changing it later is a no-op - rebuild the node.
  EOT

  validation {
    condition     = var.iam_admin_group == "" || can(regex("^[\\w+=,.@-]{1,128}$", var.iam_admin_group))
    error_message = "iam_admin_group must be a valid IAM group name (letters, digits and +=,.@-_, 128 characters or fewer)."
  }
}

# --- Hammerspace AMI ---
variable "hs_ami" {
  type        = string
  description = <<-EOT
    Hammerspace AMI ID. Account- and region-specific: the AMI must be owned
    by, or shared with, the deploying account. Obtain it from Hammerspace.
  EOT

  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,}$", trimspace(var.hs_ami)))
    error_message = "hs_ami must be an AMI ID like ami-0123456789abcdef0 (not empty, not a placeholder)."
  }
}

# --- Instance sizing ---
variable "anvil_instance_type" {
  type = string
  # Product minimum: 16 vCPU / 32 GiB (enforced at plan time). i7ie keeps
  # NVMe instance storage for the metadata filesystem; 6xlarge is the
  # smallest i7ie size meeting the minimum.
  default = "i7ie.6xlarge"

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.[a-z0-9]+$", var.anvil_instance_type))
    error_message = "anvil_instance_type must be an EC2 instance type such as i7ie.6xlarge."
  }
}

variable "dsx_instance_type" {
  type    = string
  default = "i7ie.2xlarge"

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.[a-z0-9]+$", var.dsx_instance_type))
    error_message = "dsx_instance_type must be an EC2 instance type such as i7ie.2xlarge."
  }
}

variable "dsx_count" {
  type    = number
  default = 1

  validation {
    condition     = var.dsx_count >= 0
    error_message = "dsx_count must be >= 0."
  }
}

# --- Networking ---
variable "network_mtu" {
  type        = number
  default     = 9001
  description = <<-EOT
    MTU set on eth0 in the node user-data. AWS supports 9001-byte jumbo
    frames intra-VPC on all current EC2 instance types. Use 1500 if you need
    to talk across a router that won't fragment, or to match a peer stuck at
    1500.

    FIXED AT DEPLOYMENT: this reaches the node only through user_data, which
    Hammerspace reads once at first boot and terraform now ignores on update.
    Changing it later is a no-op - rebuild the node.
  EOT

  validation {
    condition     = var.network_mtu >= 576 && var.network_mtu <= 9216
    error_message = "network_mtu must be between 576 and 9216 (9001 is the AWS jumbo-frame MTU)."
  }
}

# --- Anvil disks ---
# Boot is ALWAYS provisioned. Metadata EBS volumes are skipped automatically
# on instance types with built-in ephemeral NVMe storage (i4i.*, i7ie.*,
# r8id.*, c8id.*, ...) - Hammerspace uses the built-in drives there.
variable "anvil_boot_disk_size" {
  type        = number
  default     = 1024
  description = "Anvil boot volume size in GB (always provisioned). Minimum 512 - the boot disk must be large enough to deliver adequate IOPS."

  validation {
    condition     = var.anvil_boot_disk_size >= 512
    error_message = "anvil_boot_disk_size must be >= 512 GB (boot disk performance requirement)."
  }
}

variable "anvil_meta_disk_size" {
  type        = number
  default     = 1024
  description = "Size in GB of EACH Anvil metadata volume."

  validation {
    condition     = var.anvil_meta_disk_size >= 1 && var.anvil_meta_disk_size <= 16384
    error_message = "anvil_meta_disk_size must be between 1 and 16384 GiB (gp3 limits)."
  }
}

variable "anvil_meta_disk_count" {
  type        = number
  default     = 1
  description = "Metadata volumes per Anvil node: 1, 2, or 4 (/dev/sdb../dev/sde)."

  validation {
    condition     = contains([1, 2, 4], var.anvil_meta_disk_count)
    error_message = "anvil_meta_disk_count must be 1, 2, or 4."
  }
}

variable "anvil_raid_type" {
  type        = string
  default     = "stripe"
  description = <<-EOT
    'stripe' (raid0) or 'mirror' (raid1) across the metadata disks when
    anvil_meta_disk_count > 1.

    FIXED AT DEPLOYMENT: this reaches the node only through user_data, which
    Hammerspace reads once at first boot and terraform now ignores on update.
    Changing it later is a no-op - rebuild the node.
  EOT

  validation {
    condition     = contains(["stripe", "mirror"], var.anvil_raid_type)
    error_message = "anvil_raid_type must be 'stripe' or 'mirror'."
  }
}

variable "anvil_meta_disk_iops" {
  type        = number
  default     = 5000
  description = "Provisioned IOPS per gp3 metadata volume (gp3 baseline is 3000)."

  validation {
    condition     = var.anvil_meta_disk_iops >= 3000 && var.anvil_meta_disk_iops <= 16000
    error_message = "anvil_meta_disk_iops must be between 3000 and 16000 (gp3 limits; 3000 is the free baseline)."
  }
}

# --- HA cluster (floating) IP ---
variable "anvil_cluster_ip" {
  type        = string
  default     = ""
  description = <<-EOT
    ha mode: optionally pin the cluster (floating) IP; empty = auto-allocate a
    free secondary private IP on the Secondary node's ENI.
    ha-multi-az mode: REQUIRED, and must be an overlay IP OUTSIDE the VPC CIDR
    (it is reached via route-table entries the Anvil rewrites on failover).

    FIXED AT DEPLOYMENT. The nodes read it from user_data at first boot, so
    changing it later is a no-op - rebuild the deployment to move it.
  EOT

  validation {
    # This value is interpolated into a shell command (aws ec2
    # assign-private-ip-addresses in modules/anvil-ha), so a malformed one fails
    # part-way through an apply, after the ENI already exists. Rejecting it at
    # plan time costs nothing. Both checks are needed: a regex alone accepts
    # 999.1.1.1, and cidrhost alone accepts IPv6 and prefixed forms.
    condition = var.anvil_cluster_ip == "" || (
      can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", var.anvil_cluster_ip)) &&
      can(cidrhost("${var.anvil_cluster_ip}/32", 0))
    )
    error_message = "anvil_cluster_ip must be a bare IPv4 address such as 10.0.1.50 - no prefix length, no hostname - or empty to auto-allocate."
  }
}

# --- Multi-AZ (ha-multi-az mode only) ---
variable "az1" {
  type        = string
  default     = ""
  description = "Availability zone of the Primary Anvil (ha-multi-az)."

  validation {
    condition     = var.az1 == "" || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9][a-z]$", var.az1))
    error_message = "az1 must be an availability zone such as us-west-2a (required for ha-multi-az, empty otherwise)."
  }
}

variable "az2" {
  type        = string
  default     = ""
  description = "Availability zone of the Secondary Anvil (ha-multi-az). Must differ from az1."

  validation {
    condition     = var.az2 == "" || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9][a-z]$", var.az2))
    error_message = "az2 must be an availability zone such as us-west-2b (required for ha-multi-az, empty otherwise)."
  }
}

variable "subnet_az1" {
  type        = string
  default     = ""
  description = "Subnet in az1 for the Primary Anvil (ha-multi-az)."

  validation {
    condition     = var.subnet_az1 == "" || can(regex("^subnet-[0-9a-f]{8,}$", var.subnet_az1))
    error_message = "subnet_az1 must be a subnet ID like subnet-0123456789abcdef0."
  }
}

variable "subnet_az2" {
  type        = string
  default     = ""
  description = "Subnet in az2 for the Secondary Anvil (ha-multi-az)."

  validation {
    condition     = var.subnet_az2 == "" || can(regex("^subnet-[0-9a-f]{8,}$", var.subnet_az2))
    error_message = "subnet_az2 must be a subnet ID like subnet-0123456789abcdef0."
  }
}

variable "route_table_ids" {
  type        = list(string)
  default     = []
  description = <<-EOT
    ha-multi-az: additional client route tables the Anvil updates with the
    floating /32 on failover (the data subnets' own route tables are handled
    by the product).
  EOT

  validation {
    condition     = alltrue([for r in var.route_table_ids : can(regex("^rtb-[0-9a-f]{8,}$", r))])
    error_message = "every route_table_ids entry must be a route table ID like rtb-0123456789abcdef0."
  }
}

variable "anvil_cluster_ip_prefixlen" {
  type        = number
  default     = 20
  description = "ha-multi-az: prefix length appended to the overlay cluster IP in the DSX metadata config (CFT uses <ClusterIp>/20)."

  validation {
    condition     = var.anvil_cluster_ip_prefixlen >= 1 && var.anvil_cluster_ip_prefixlen <= 32
    error_message = "anvil_cluster_ip_prefixlen must be between 1 and 32."
  }
}

variable "sec_ip_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Security-group source CIDR (0.0.0.0/0 = open, matching the CFT SecIpCidr)."

  validation {
    # cidrhost rejects a bad prefix or out-of-range octets that a regex accepts.
    condition     = can(cidrhost(var.sec_ip_cidr, 0))
    error_message = "sec_ip_cidr must be a CIDR block such as 10.0.0.0/16 (0.0.0.0/0 is the wide-open default)."
  }
}

variable "nlb_enabled" {
  type        = bool
  default     = true
  description = "ha-multi-az: create the internal NLB fronting management (443) and SSH (22)."
}

variable "nlb_scheme" {
  type        = string
  default     = "internal"
  description = "ha-multi-az NLB scheme: internal or internet-facing."

  validation {
    condition     = contains(["internal", "internet-facing"], var.nlb_scheme)
    error_message = "nlb_scheme must be 'internal' or 'internet-facing'."
  }
}

# --- DSX storage volumes (EBS) ---
# The /dev/sda1 entry is REQUIRED (boot, always provisioned). All other
# entries are data disks, skipped automatically on ephemeral instance types.
variable "dsx_volumes" {
  type = list(object({
    device_name           = string
    volume_type           = optional(string, "gp3")
    volume_size           = optional(number, 1024)
    iops                  = optional(number)
    throughput            = optional(number)
    encrypted             = optional(bool)
    kms_key_id            = optional(string)
    delete_on_termination = optional(bool, true)
  }))
  default = [
    { device_name = "/dev/sda1" },
    { device_name = "/dev/xvdb" },
    { device_name = "/dev/xvdc" },
  ]
  description = "Per-DSX-node volume list. Boot (/dev/sda1) is required; data disks are optional and skipped on ephemeral types."

  validation {
    condition     = length([for v in var.dsx_volumes : v if v.device_name == "/dev/sda1"]) == 1
    error_message = "dsx_volumes must include exactly one /dev/sda1 boot disk entry (data disks /dev/sdb+ are optional)."
  }

  validation {
    condition     = alltrue([for v in var.dsx_volumes : v.volume_size >= 512 if v.device_name == "/dev/sda1"])
    error_message = "The DSX boot disk (/dev/sda1) must be >= 512 GB (boot disk performance requirement)."
  }
}

# --- Elastic IP (optional) ---
variable "eip" {
  type        = string
  default     = ""
  description = <<-EOT
    Existing Elastic IP address to associate. standalone mode: associated with
    the Anvil (and the Anvil is then addressed via it). Other modes: associated
    with the first DSX node. Empty = no EIP association.
  EOT

  validation {
    condition = var.eip == "" || (
      can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", var.eip)) && can(cidrhost("${var.eip}/32", 0))
    )
    error_message = "eip must be an Elastic IP ADDRESS (e.g. 52.1.2.3), not an allocation ID, or empty for no association."
  }
}

variable "create_eips" {
  type        = bool
  default     = false
  description = <<-EOT
    Allocate NEW Elastic IPs and associate one with the Anvil and one with each
    DSX node, for a VPC the operator can only reach from outside (no VPN, no
    peering). Mutually exclusive with var.eip, which associates a pre-existing
    address instead.

    The DSX still joins the cluster on the Anvil's PRIVATE IP - both are in one
    subnet, so that path is always available, needs no hairpin out through the
    internet gateway, and keeps jumbo frames working. Only the management
    endpoint (the readiness wait and cluster-ID tagging, which run from
    wherever terraform runs) uses the Anvil's public address.

    The addresses survive an instance stop/start: in a VPC an EIP association
    is retained, unlike an auto-assigned public IP.
  EOT
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Extra tags for every created resource, merged over the built-in customer /
    owner tags (AWS parity with the Azure root, which has always had this).

    This is how cost-governance tags are set, e.g.
    BUSINESS_HOURS = "08:00-18:00" to have the instance auto-started and
    auto-stopped on weekdays. Note the policy needs an owner tag too, or the
    instance is stopped about ten minutes after it starts.
  EOT

  validation {
    condition     = alltrue([for k, v in var.tags : length(k) <= 128 && length(v) <= 256])
    error_message = "every tag key must be <= 128 characters and every value <= 256 (AWS limits)."
  }

  validation {
    condition     = alltrue([for k in keys(var.tags) : !startswith(lower(k), "aws:")])
    error_message = "tag keys starting with 'aws:' are reserved by AWS and cannot be set."
  }
}

# --- Existing cluster (dsx mode; also set automatically by the Anvil modules) ---
variable "security_group_id" {
  type        = string
  default     = ""
  description = "Existing security group to reuse. Empty = create one (wide open - tighten for non-lab use)."

  validation {
    condition     = var.security_group_id == "" || can(regex("^sg-[0-9a-f]{8,}$", var.security_group_id))
    error_message = "security_group_id must be a security group ID like sg-0123456789abcdef0, or empty to create one."
  }
}

variable "anvil_ip" {
  type        = string
  default     = ""
  description = "dsx mode: the EXISTING cluster's Anvil / cluster IP the DSX joins. Leave empty for the other modes."

  validation {
    condition = var.anvil_ip == "" || (
      can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", var.anvil_ip)) && can(cidrhost("${var.anvil_ip}/32", 0))
    )
    error_message = "anvil_ip must be the IPv4 address of the existing cluster (dsx mode), or empty."
  }
}

variable "anvil_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "dsx mode: admin password of the existing cluster (a fresh cluster's password is its Primary Anvil instance ID). Leave empty for the other modes."

  # Checked by a precondition in validation.tf, NOT here: a failing variable
  # validation prints the value even for a sensitive variable (verified on
  # terraform 1.9.8).
}

variable "hsuser" {
  type        = string
  default     = "admin"
  description = "Hammerspace management API user."

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.hsuser))
    error_message = "hsuser must be a plain user name - it is sent as a REST basic-auth user."
  }
}

# --- Pre-flight / post-deploy ---
variable "portal_floating_ips" {
  type        = bool
  default     = true
  description = <<-EOT
    Whether DSX portal floating IPs will be used on this cluster.

    PRE-FLIGHT ONLY - this creates no resources. AWS has no portal-floating-IP
    Terraform resource: the address is configured on the running cluster over
    the REST API, and CTDB moves it between DSX nodes by rewriting ENIs (or
    route tables for a /32). What Terraform CAN do is verify up front that the
    node role is allowed to make those calls, which is what this enables.

    Default true because portal floating IPs are commonly used, and the failure
    mode when the permission is missing is bad: everything deploys, the address
    is placed, and nothing goes wrong until a node fails - at which point the
    address is released and never reclaimed.

    Set false only if you know portal floating IPs will not be used and the node
    role deliberately lacks ec2:AssignPrivateIpAddresses.
  EOT
}

variable "skip_preflight" {
  type        = bool
  default     = false
  description = "Set true ONLY to bypass the pre-flight IAM / VPC-endpoint / reachability safety checks."
}

variable "check_sts_endpoint" {
  type        = bool
  default     = true
  description = "Advisory pre-flight check for an STS interface endpoint (warning only)."
}

variable "cluster_id_tag_key" {
  type        = string
  default     = "HammerspaceClusterId"
  description = "AWS tag key applied to every instance, recording the Hammerspace cluster ID."

  validation {
    # AWS reserves the aws: tag prefix and caps keys at 128 characters.
    condition     = length(var.cluster_id_tag_key) >= 1 && length(var.cluster_id_tag_key) <= 128 && !startswith(lower(var.cluster_id_tag_key), "aws:")
    error_message = "cluster_id_tag_key must be 1-128 characters and must not start with the reserved 'aws:' prefix."
  }
}

variable "wait_for_cluster" {
  type        = bool
  default     = true
  description = <<-EOT
    After creating the instances, wait for the cluster management API
    (:8443) from this machine and tag all instances with the cluster ID.
    Requires the Anvil's 8443 port to be reachable from wherever terraform
    runs. Set false if it is not (instances are still created; tagging is
    skipped, like the Ansible flow would time out).
  EOT
}
