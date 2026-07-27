variable "node_count" {
  type = number
}

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

variable "data_disk_count" {
  type = number
}

variable "data_disk_size" {
  type = number
}

variable "data_disk_type" {
  type = string
}

variable "data_disk_striping" {
  type        = bool
  default     = false
  description = "node.storage.options = raid0 across the data disks (ARM DSXDataDiskStriping)."
}

variable "metadata_ip" {
  type        = string
  description = "Cluster metadata IP the DSX joins (LB frontend for HA, Anvil NIC IP for standalone, or the existing cluster's IP)."
}

variable "subnet_prefixlen" {
  type        = string
  description = "Prefix length appended to the metadata IP in custom data (ARM dataNetNum)."
}

variable "public_ip" {
  type    = bool
  default = false
}

variable "static_ips" {
  type        = list(string)
  default     = []
  description = "Optional static private IPs, one per node in order; nodes beyond the list length stay dynamic."
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
