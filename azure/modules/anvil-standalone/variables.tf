variable "prefix" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group" {
  type = string
}

variable "data_subnet_id" {
  type = string
}

variable "nsg_id" {
  type = string
}

variable "image_id" {
  type    = string
  default = ""
}

variable "marketplace_image" {
  type = object({
    publisher = string
    offer     = string
    sku       = optional(string, "planformacc-byol")
    version   = optional(string, "latest")
  })
  default = null
}

variable "instance_type" {
  type = string
}

variable "boot_disk_size" {
  type = number
}

variable "boot_disk_type" {
  type = string
}

variable "metadata_disk_size" {
  type = number
}

variable "metadata_disk_type" {
  type = string
}

variable "metadata_disk_iops" {
  type    = number
  default = null
}

variable "metadata_disk_throughput" {
  type    = number
  default = null
}

variable "static_ip" {
  type        = string
  default     = ""
  description = "Optional static private IP for the Anvil data NIC (ARM anvilDataClusterIP in standalone mode). Empty = dynamic."
}

variable "public_ip" {
  type    = bool
  default = false
}

variable "availability_set_id" {
  type    = string
  default = null
}

variable "ppg_id" {
  type    = string
  default = null
}

variable "admin_username" {
  type = string
}

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "domain" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "diag_storage_uri" {
  type        = string
  default     = ""
  description = "Blob endpoint for boot diagnostics (empty = disabled)."
}
