variable "mode" {
  type = string
}

variable "region" {
  type = string
}

variable "aws_profile" {
  type    = string
  default = ""
}

variable "vpc" {
  type = string
}

variable "subnet_ids" {
  type        = list(string)
  description = "Deployment subnet(s). EC2 API reachability is validated for every one (multi-AZ passes both)."
}

variable "deployer_actions" {
  type        = list(string)
  description = "IAM actions the deploying credentials must be allowed."
}

variable "iam_instance_profile_name" {
  type        = string
  default     = ""
  description = "Instance profile (name or ARN). Existence is a hard check when set; empty skips the profile checks."
}

variable "instance_profile_actions" {
  type        = list(string)
  default     = []
  description = "IAM actions the instance-profile role must be allowed (runtime HA needs)."
}

variable "check_sts" {
  type    = bool
  default = true
}

variable "check_anvil" {
  type        = bool
  default     = false
  description = "dsx mode: probe the existing Anvil and verify AMI/cluster version compatibility."
}

variable "anvil_ip" {
  type    = string
  default = ""
}

variable "anvil_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "hsuser" {
  type    = string
  default = "admin"
}

variable "hs_ami" {
  type    = string
  default = ""
}
