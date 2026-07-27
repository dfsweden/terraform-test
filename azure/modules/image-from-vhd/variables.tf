variable "location" {
  type = string
}

variable "resource_group" {
  type = string
}

variable "sas_url" {
  type        = string
  sensitive   = true
  description = "Read-only blob SAS URL to the Hammerspace .vhd (from Hammerspace)."
}

variable "tags" {
  type    = map(string)
  default = {}
}
