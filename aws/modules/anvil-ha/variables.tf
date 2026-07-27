variable "name_suffix" {
  type = string
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
  type = string
}

variable "cluster_ip" {
  type        = string
  default     = ""
  description = "Optional pinned cluster (floating) IP. Empty = auto-allocate a secondary private IP on the Secondary node's ENI."
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
  type        = list(string)
  default     = ["data", "mgmt", "ha"]
  description = "Single eth0 carries data + mgmt + ha (no dedicated heartbeat network)."
}

variable "region" {
  type        = string
  description = "Used by the AWS CLI when pinning an explicit cluster IP onto the pre-created ENI."
}

variable "aws_profile" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
