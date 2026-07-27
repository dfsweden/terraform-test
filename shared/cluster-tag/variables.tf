variable "endpoint" {
  type        = string
  description = "Control-host-reachable management REST endpoint (:8443)."
}

variable "hsuser" {
  type    = string
  default = "admin"
}

variable "password" {
  type      = string
  sensitive = true
}

variable "tag_command" {
  type        = string
  description = <<-EOT
    Cloud-specific shell command that tags every instance created this
    deployment. The literal token __CLUSTER_ID__ is replaced with the
    cluster ID read from the management API before execution.
    AWS example:   aws ec2 create-tags --resources i-… --tags Key=K,Value=__CLUSTER_ID__
    Azure example: for id in …; do az tag update --resource-id "$id" …; done
  EOT
}

variable "triggers" {
  type        = list(string)
  description = "Values whose change re-runs the tagging (typically the instance/VM IDs)."
}

variable "wait_retries" {
  type        = number
  default     = 120
  description = "Attempts (x delay seconds) waiting for the management API to come up before reading the cluster ID."
}

variable "retries" {
  type    = number
  default = 30
}

variable "delay" {
  type    = number
  default = 10
}
