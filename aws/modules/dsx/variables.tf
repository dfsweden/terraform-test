variable "has_ephemeral" {
  type        = bool
  description = "Whether the instance type has built-in instance storage (NVMe). Resolved at ROOT from the instance-type data source that already backs the vCPU/memory minimums - a module-local lookup would be deferred to apply by the caller's depends_on, leaving the volume count unknown at plan."
}

variable "node_count" {
  type = number
}

variable "name_suffix" {
  type = string
}

variable "ami" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet(s) to launch into. Multiple subnets = round-robin spread (dsx-1 -> [0], dsx-2 -> [1], ...) - the multi-AZ path."
}

variable "security_group_id" {
  type = string
}

variable "key_name" {
  type    = string
  default = ""
}

variable "iam_instance_profile" {
  type    = string
  default = ""
}

variable "volumes" {
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
  description = "Per-node volume list. /dev/sda1 = boot (required, always provisioned); the rest are data disks, skipped on ephemeral types."
}

variable "network_mtu" {
  type = number
}

variable "iam_admin_group" {
  type    = string
  default = ""
}

variable "anvil_ip" {
  type        = string
  description = "Cluster metadata IP the DSX joins (the floating/overlay cluster IP, or the standalone Anvil's IP)."
}

variable "anvil_password" {
  type      = string
  sensitive = true
}

variable "multiaz" {
  type        = bool
  default     = false
  description = "Cross-AZ deployment: metadata target becomes <anvil_ip>/<prefixlen> and route_table_ids ride along in the aws block."
}

variable "cluster_ip_prefixlen" {
  type    = number
  default = 20
}

variable "route_table_ids" {
  type    = list(string)
  default = []
}


variable "eip_allocation_ids" {
  type        = list(string)
  default     = []
  description = "Elastic IP allocation IDs, one per node in order. Empty = no association. A single entry associates with the first node only, which is what a lone var.eip does."
}

variable "tags" {
  type    = map(string)
  default = {}
}
