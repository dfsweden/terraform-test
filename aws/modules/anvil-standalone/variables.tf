variable "has_ephemeral" {
  type        = bool
  description = "Whether the instance type has built-in instance storage (NVMe). Resolved at ROOT from the instance-type data source that already backs the vCPU/memory minimums - a module-local lookup would be deferred to apply by the caller's depends_on, leaving the volume count unknown at plan."
}

variable "name" {
  type        = string
  description = "Instance Name tag / hostname (anvil-1-<suffix>)."
}

variable "ami" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "subnet_id" {
  type = string
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

variable "boot_disk_size" {
  type = number
}

variable "meta_disk_size" {
  type = number
}

variable "meta_disk_count" {
  type = number
}

variable "meta_disk_iops" {
  type = number
}

variable "raid_type" {
  type = string
}

variable "network_mtu" {
  type = number
}

variable "iam_admin_group" {
  type    = string
  default = ""
}

variable "eip" {
  type        = string
  default     = ""
  description = "Elastic IP ADDRESS, used for reporting (the association itself uses eip_allocation_id). Empty = no EIP."
}

variable "eip_allocation_ids" {
  type        = list(string)
  default     = []
  description = "Elastic IP allocation ID to associate, as a 0-or-1 element list. A list rather than a string so the count is known at PLAN: the ID itself is unknown until apply when the address is allocated in the same run, and comparing an unknown to \"\" makes terraform refuse the plan."
}

variable "tags" {
  type    = map(string)
  default = {}
}
