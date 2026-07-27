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
}

variable "owner" {
  type        = string
  default     = "douglas"
  description = "'owner' tag value, applied to every resource - IT automation stops untagged VMs. Empty = tag key omitted entirely."
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
    condition     = length(trimspace(var.vpc)) > 0 && !startswith(trimspace(var.vpc), "<")
    error_message = "vpc must be set (not empty, not a <PLACEHOLDER>)."
  }
}

variable "subnet_public" {
  type        = string
  default     = ""
  description = "Subnet the nodes launch into (standalone / ha / dsx modes)."
}

variable "key_name" {
  type        = string
  default     = ""
  description = "Existing EC2 key pair name. Empty = no key pair attached."
}

variable "aws_profile" {
  type        = string
  default     = ""
  description = "Named AWS CLI profile, or empty for the default credentials chain."
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
}

variable "iam_admin_group" {
  type        = string
  default     = ""
  description = "IAM group whose members may SSH to the Anvil (aws.iam_admin_group in user-data)."
}

# --- Hammerspace AMI ---
variable "hs_ami" {
  type        = string
  description = <<-EOT
    Hammerspace AMI ID. Account- and region-specific: the AMI must be owned
    by, or shared with, the deploying account. Obtain it from Hammerspace.
  EOT

  validation {
    condition     = length(trimspace(var.hs_ami)) > 0 && !startswith(trimspace(var.hs_ami), "<")
    error_message = "hs_ami must be set (not empty, not a <PLACEHOLDER>)."
  }
}

# --- Instance sizing ---
variable "anvil_instance_type" {
  type = string
  # Product minimum: 16 vCPU / 32 GiB (enforced at plan time). i7ie keeps
  # NVMe instance storage for the metadata filesystem; 6xlarge is the
  # smallest i7ie size meeting the minimum.
  default = "i7ie.6xlarge"
}

variable "dsx_instance_type" {
  type    = string
  default = "i7ie.2xlarge"
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
  EOT
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
  description = "'stripe' (raid0) or 'mirror' (raid1) across the metadata disks when anvil_meta_disk_count > 1."

  validation {
    condition     = contains(["stripe", "mirror"], var.anvil_raid_type)
    error_message = "anvil_raid_type must be 'stripe' or 'mirror'."
  }
}

variable "anvil_meta_disk_iops" {
  type        = number
  default     = 5000
  description = "Provisioned IOPS per gp3 metadata volume (gp3 baseline is 3000)."
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
  EOT
}

# --- Multi-AZ (ha-multi-az mode only) ---
variable "az1" {
  type        = string
  default     = ""
  description = "Availability zone of the Primary Anvil (ha-multi-az)."
}

variable "az2" {
  type        = string
  default     = ""
  description = "Availability zone of the Secondary Anvil (ha-multi-az). Must differ from az1."
}

variable "subnet_az1" {
  type        = string
  default     = ""
  description = "Subnet in az1 for the Primary Anvil (ha-multi-az)."
}

variable "subnet_az2" {
  type        = string
  default     = ""
  description = "Subnet in az2 for the Secondary Anvil (ha-multi-az)."
}

variable "route_table_ids" {
  type        = list(string)
  default     = []
  description = <<-EOT
    ha-multi-az: additional client route tables the Anvil updates with the
    floating /32 on failover (the data subnets' own route tables are handled
    by the product).
  EOT
}

variable "anvil_cluster_ip_prefixlen" {
  type        = number
  default     = 20
  description = "ha-multi-az: prefix length appended to the overlay cluster IP in the DSX metadata config (CFT uses <ClusterIp>/20)."
}

variable "sec_ip_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Security-group source CIDR (0.0.0.0/0 = open, matching the CFT SecIpCidr)."
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
}

# --- Existing cluster (dsx mode; also set automatically by the Anvil modules) ---
variable "security_group_id" {
  type        = string
  default     = ""
  description = "Existing security group to reuse. Empty = create one (wide open - tighten for non-lab use)."
}

variable "anvil_ip" {
  type        = string
  default     = ""
  description = "dsx mode: the EXISTING cluster's Anvil / cluster IP the DSX joins. Leave empty for the other modes."
}

variable "anvil_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "dsx mode: admin password of the existing cluster (a fresh cluster's password is its Primary Anvil instance ID). Leave empty for the other modes."
}

variable "hsuser" {
  type        = string
  default     = "admin"
  description = "Hammerspace management API user."
}

# --- Pre-flight / post-deploy ---
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
