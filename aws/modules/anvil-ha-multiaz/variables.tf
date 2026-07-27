variable "name_suffix" {
  type = string
}

variable "ami" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "az1" {
  type        = string
  description = "AZ of the Primary Anvil. Must differ from az2."
}

variable "az2" {
  type        = string
  description = "AZ of the Secondary Anvil."
}

variable "subnet_az1" {
  type = string
}

variable "subnet_az2" {
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
  type = string
}

variable "cluster_ip" {
  type        = string
  description = "REQUIRED overlay cluster IP, OUTSIDE the VPC CIDR - floated by the Anvil rewriting route-table entries on failover."
}

variable "route_table_ids" {
  type        = list(string)
  default     = []
  description = "Additional client route tables the Anvil updates with the floating /32 (validated to exist in the VPC)."
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

variable "node_roles" {
  type    = list(string)
  default = ["data", "mgmt", "ha"]
}

variable "nlb_enabled" {
  type    = bool
  default = true
}

variable "nlb_scheme" {
  type    = string
  default = "internal"
}

variable "tags" {
  type    = map(string)
  default = {}
}
