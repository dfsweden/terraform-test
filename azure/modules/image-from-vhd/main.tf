# Stage a Hammerspace VHD delivered as a read-only blob SAS URL into this
# subscription and boot from the resulting managed image.
#
# CREATE-ONLY by design: the staging runs through
# scripts/stage-hammerspace-image.sh via a terraform_data local-exec with no
# destroy-time action, so `terraform destroy` removes the Hammerspace
# deployment but NOT the image - apply/destroy cycles of the product never
# re-download the VHD. The script is idempotent (image exists -> immediate
# return) and deletes the staged .vhd blob right after image creation: a
# managed image copies the data and is self-contained, so only the image -
# not a redundant 30+ GB blob - persists long-term.
#
# The image is named after the .vhd file (Hammerspace-<version>...), so a new
# VHD version stages a new image alongside the old one. Clean up outgrown
# images/staging storage manually (az image delete / az storage account
# delete) - they are deliberately outside Terraform state.

locals {
  vhd_name   = basename(split("?", var.sas_url)[0])
  image_name = trimsuffix(local.vhd_name, ".vhd")
  tag_args   = join(" ", [for k, v in var.tags : "${k}=${v}"])
}

resource "terraform_data" "stage" {
  triggers_replace = [local.image_name, var.resource_group]

  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash", "-c"]
    environment = {
      SAS_URL = var.sas_url
    }
    # -d: delete the staged .vhd blob once the image exists - the managed
    # image copies the data at creation and is self-contained, so the blob
    # is redundant afterwards (only the image persists across destroys).
    command = <<-EOT
      exec "${path.module}/../../scripts/stage-hammerspace-image.sh" \
        -u "$SAS_URL" \
        -g "${var.resource_group}" \
        -l "${var.location}" \
        -n "${local.image_name}" \
        -d \
        ${local.tag_args != "" ? "-t \"${local.tag_args}\"" : ""}
    EOT
  }
}

# Read the staged (or pre-existing) image back; deferred to apply by the
# dependency on the staging step.
data "azurerm_image" "staged" {
  name                = local.image_name
  resource_group_name = var.resource_group

  depends_on = [terraform_data.stage]
}
