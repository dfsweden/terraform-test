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

variable "ha_subnet_id" {
  type        = string
  default     = null
  description = "OPTIONAL dedicated HA heartbeat subnet (each Anvil's eth1, legacy marketplace-template layout; a /29, not shared with other instances). Default null = heartbeat on eth0, no extra subnet."
}

variable "node_ips" {
  type        = list(string)
  default     = []
  description = "Optional static private IPs for the Anvil data NICs, in node order; nodes beyond the list length stay dynamic."
}

variable "subnet_prefixlen" {
  type        = string
  description = "Prefix length of the data subnet CIDR - appended to the cluster IP in custom data (ARM dataNetNum)."
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

# Applied by hs-vm only to PremiumV2/Ultra disks - inert after the ha-mode
# fallback to Premium_LRS, live for zonal (ha-multi-az) Anvils.
variable "metadata_disk_iops" {
  type    = number
  default = null
}

variable "metadata_disk_throughput" {
  type    = number
  default = null
}

variable "cluster_ip" {
  type        = string
  default     = ""
  description = "Optional static cluster IP (the internal LB frontend). Empty = dynamically allocated."
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

variable "zones" {
  type        = list(string)
  default     = []
  description = "ha-multi-az: availability zone of each Anvil, in node order (\"1\" | \"2\" | \"3\"). Empty = no zone (availability-set placement). The root guarantees two entries when set."
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
