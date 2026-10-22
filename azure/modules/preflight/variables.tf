variable "mode" {
  type = string
}

variable "location" {
  type = string
}

variable "subscription" {
  type    = string
  default = ""
}

variable "vm_sizes" {
  type        = list(string)
  description = "VM sizes that must exist in the target location."
}

variable "premium_sizes" {
  type        = list(string)
  default     = []
  description = "VM sizes that must support premium storage (a Premium_LRS disk was selected for them)."
}

variable "anvil_size" {
  type        = string
  default     = ""
  description = "Anvil VM size to check against the product minimum (empty = skip)."
}

variable "anvil_min_vcpus" {
  type    = number
  default = 16
}

variable "anvil_min_mem_gb" {
  type    = number
  default = 32
}

variable "dsx_size" {
  type        = string
  default     = ""
  description = "DSX VM size to check against the product minimum (empty = skip)."
}

variable "dsx_min_vcpus" {
  type    = number
  default = 8
}

variable "dsx_min_mem_gb" {
  type    = number
  default = 16
}

variable "image_id" {
  type        = string
  default     = ""
  description = "Image resource ID to verify (empty for marketplace images)."
}

variable "image_generation" {
  type        = string
  default     = "V1"
  description = "Hyper-V generation of the Hammerspace image; every chosen VM size must support it (empty = skip the check)."
}

variable "image_sas_url" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Blob SAS URL to verify (readable, https, page blob); empty = skip."
}

variable "check_anvil" {
  type        = bool
  default     = false
  description = "dsx mode: probe the existing Anvil and (best effort) verify version compatibility."
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

variable "anvil_count" {
  type        = number
  default     = 0
  description = "Anvil VMs this apply creates (0 in dsx mode) - for the per-family vCPU quota check."
}

variable "dsx_count" {
  type        = number
  default     = 0
  description = "DSX VMs this apply creates - for the per-family vCPU quota check."
}

variable "anvil_zones" {
  type        = list(string)
  default     = []
  description = "ha-multi-az: zones the Anvils land in - each must exist in the location and offer the size (empty = skip the zone checks)."
}

variable "dsx_zones" {
  type        = list(string)
  default     = []
  description = "ha-multi-az: zones the DSX nodes land in - same checks as anvil_zones (empty = skip)."
}

variable "anvil_meta_disk_type" {
  type        = string
  default     = ""
  description = "Resolved Anvil metadata disk type; PremiumV2_LRS / UltraSSD_LRS must be offered in every requested zone (empty or other types = skip)."
}

variable "dsx_data_disk_type" {
  type        = string
  default     = ""
  description = "Resolved DSX data disk type; same zone check as anvil_meta_disk_type."
}
