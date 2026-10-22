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

variable "hyperv_generation" {
  type        = string
  default     = "V1"
  description = "Hyper-V generation to register the staged image as (V1 or V2). The VHD is hybrid-boot, so one blob serves both; the choice is permanent per image, and a V2 image is named <vhd>-gen2 so both can coexist."

  validation {
    condition     = contains(["V1", "V2"], var.hyperv_generation)
    error_message = "hyperv_generation must be V1 or V2."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
