variable "name" {
  type        = string
  description = "VM resource name (e.g. <prefix>Anvil1)."
}

variable "computer_name" {
  type        = string
  description = "OS hostname (ARM computerName - e.g. <prefix>Anvil, <prefix>Anvil-2, <prefix>Dsx1)."
}

variable "location" {
  type = string
}

variable "resource_group" {
  type = string
}

variable "nic_ids" {
  type        = list(string)
  description = "NIC IDs in order; the first is the primary (data) interface."
}

variable "instance_type" {
  type = string
}

variable "availability_set_id" {
  type    = string
  default = null
}

variable "ppg_id" {
  type    = string
  default = null
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

variable "os_disk_size" {
  type = number
}

variable "os_disk_type" {
  type = string
}

variable "data_disks" {
  type = list(object({
    lun        = number
    size       = number
    type       = string
    iops       = optional(number)
    throughput = optional(number)
  }))
  default     = []
  description = "iops/throughput apply only to PremiumV2_LRS / UltraSSD_LRS disks (which are created as standalone managed disks)."
}

variable "custom_data" {
  type        = string
  description = "Raw provisioning JSON (the legacy VM resource base64-encodes it, matching the ARM base64() call)."
}

variable "admin_username" {
  type = string
}

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "diag_storage_uri" {
  type        = string
  default     = ""
  description = "Blob endpoint of a storage account for boot diagnostics (empty = disabled)."
}

variable "tags" {
  type    = map(string)
  default = {}
}
