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
  description = "Existing Elastic IP address to associate with the Anvil (empty = none)."
}

variable "tags" {
  type    = map(string)
  default = {}
}
