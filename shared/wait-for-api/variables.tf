variable "endpoint" {
  type        = string
  description = "Host/IP whose :8443 management REST API to wait for."
}

variable "hsuser" {
  type    = string
  default = "admin"
}

variable "password" {
  type      = string
  sensitive = true
}

variable "retries" {
  type    = number
  default = 120
}

variable "delay" {
  type    = number
  default = 10
}
