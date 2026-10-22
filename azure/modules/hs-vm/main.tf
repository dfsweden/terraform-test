# ============================================================
# One Hammerspace VM (Anvil or DSX) + the setAdminPassword
# extension, mirroring the ARM template's VM resources.
#
# Uses azurerm_linux_virtual_machine. The classic azurerm_virtual_machine
# resource was used originally because it supports inline storage_data_disk
# blocks, on the reasoning that disks must exist at first boot. Two things
# retired that:
#
#   1. It breaks. On azurerm 3.117 the legacy resource fails with
#      "polling after CreateOrUpdate: internal-error: unimplemented polling
#      status \"Unknown\"" - the provider cannot parse the long-running
#      operation status Azure returns, and the apply dies with the VM in an
#      indeterminate state (HS-41966, 2026-08-08).
#
#   2. The race it was avoiding does not exist. The PremiumV2/Ultra path in
#      this same module has always created disks separately and attached them,
#      and the original comment conceded why that is safe: attachments land
#      seconds after VM creation, while Hammerspace first-boot storage
#      discovery runs minutes into boot. All data disks now take that path.
#
# The legacy resource is also deprecated and removed in provider 5.0, so this
# is the direction of travel regardless.
# ============================================================

locals {
  ultra_ssd = length([for d in var.data_disks : d if d.type == "UltraSSD_LRS"]) > 0

  # Every data disk is now a standalone managed disk + attachment. PremiumV2
  # and Ultra additionally carry explicit IOPS/throughput; the others take the
  # type's defaults, which is what the inline blocks did.
  all_disks = { for d in var.data_disks : d.lun => d }
  perf_disk = { for d in var.data_disks : d.lun => d if contains(["PremiumV2_LRS", "UltraSSD_LRS"], d.type) }
}

resource "azurerm_linux_virtual_machine" "this" {
  name                         = var.name
  computer_name                = var.computer_name
  location                     = var.location
  resource_group_name          = var.resource_group
  network_interface_ids        = var.nic_ids
  size                         = var.instance_type
  availability_set_id          = var.availability_set_id
  proximity_placement_group_id = var.ppg_id
  # ha-multi-az: pinned to one zone. Azure places a VM in an availability set
  # OR a zone, never both - enforced below, and by the root preconditions.
  zone                            = var.zone
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  # base64 here, not at the call sites: callers pass plain JSON, which the legacy
  # resource encoded for them (Base64EncodeIfNot). This one validates strictly.
  custom_data = base64encode(var.custom_data)
  tags        = var.tags

  # Marketplace images need the purchase plan attached (ARM 'plan' block).
  dynamic "plan" {
    for_each = var.marketplace_image != null ? [var.marketplace_image] : []
    content {
      name      = plan.value.sku
      publisher = plan.value.publisher
      product   = plan.value.offer
    }
  }

  # A custom image is referenced by id; a marketplace image by its 4-tuple.
  source_image_id = var.marketplace_image == null ? var.image_id : null

  dynamic "source_image_reference" {
    for_each = var.marketplace_image != null ? [var.marketplace_image] : []
    content {
      publisher = source_image_reference.value.publisher
      offer     = source_image_reference.value.offer
      sku       = source_image_reference.value.sku
      version   = source_image_reference.value.version
    }
  }

  os_disk {
    name                 = "${var.name}OsDisk"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size
  }

  # Serial-console/boot log capture - invaluable when a node never comes up.
  dynamic "boot_diagnostics" {
    for_each = var.diag_storage_uri != "" ? [1] : []
    content {
      storage_account_uri = var.diag_storage_uri
    }
  }

  # ARM: ultraSSDEnabled when an Ultra disk type is selected.
  additional_capabilities {
    ultra_ssd_enabled = local.ultra_ssd
  }

  # Force-delete (skip the graceful guest shutdown) is already on, set once for
  # every VM in providers.tf features.virtual_machine - it is a provider
  # setting, not a resource argument.
  #
  # This bounds the operation instead. Without a timeout a stuck VM operation
  # hangs the destroy indefinitely: measured 24+ minutes and still going on
  # 2026-08-14, on a node whose first boot failed and whose setAdminPassword
  # extension was wedged in "Updating". A bounded failure is recoverable - the
  # resource group can be deleted directly - an unbounded wait is not.
  timeouts {
    delete = "15m"
  }

  lifecycle {
    # custom_data is base64 of the provisioning payload; Azure does not return
    # it, so a diff here would replace the VM on every plan.
    ignore_changes = [custom_data]

    # A ternary, not ||: Terraform evaluates both operands of ||, and when the
    # availability set is created in the same run its id is unknown at plan,
    # which would defer this check to apply for EVERY mode. With the ternary
    # the common zone = null case resolves at plan without touching the id.
    precondition {
      condition     = var.zone == null ? true : var.availability_set_id == null
      error_message = "${var.name}: zone and availability_set_id are both set - Azure places a VM in an availability set OR a zone, never both."
    }
  }
}

resource "azurerm_managed_disk" "data" {
  for_each = local.all_disks

  name                 = "${var.name}DataDisk${each.value.lun}"
  location             = var.location
  resource_group_name  = var.resource_group
  storage_account_type = each.value.type
  create_option        = "Empty"
  disk_size_gb         = each.value.size
  # A zonal VM only attaches disks in its own zone; null keeps the regional
  # disk the availability-set shapes use.
  zone = var.zone
  # Only PremiumV2/Ultra accept explicit performance; others must leave it null
  # or Azure rejects the request.
  disk_iops_read_write = contains(keys(local.perf_disk), each.key) ? each.value.iops : null
  disk_mbps_read_write = contains(keys(local.perf_disk), each.key) ? each.value.throughput : null

  # 512, not Azure's default of 4096, and only PremiumV2/Ultra accept the
  # setting at all.
  #
  # Azure creates Premium SSD v2 and Ultra disks as 4Kn - 4096-byte LOGICAL
  # sectors - where every other disk type is 512e. pd-node-setup cannot
  # partition a 4Kn disk: it sizes partitions from /sys/block/<dev>/size, which
  # the kernel always reports in 512-byte units, then passes those numbers to
  # parted with the "s" suffix, which parted resolves against the device's
  # LOGICAL sector size. On a 512e disk the two agree; on 4Kn every boundary
  # lands 8x too far out and first boot dies with
  #
  #   parted -s --align=optimal /dev/sdc mkpart primary 256s 268435199s
  #   Error: The location 268435199s is outside of the device /dev/sdc.
  #   ... SORRY, FATAL INSTALLATION FAILURE. PLEASE RETRY.
  #
  # Measured 2026-08-14 on hs-5.3.0-83857. At the time it hit STANDALONE Anvils
  # only, which is what made it look like a deployment-shape problem: HA Anvils
  # sat in an availability set, PremiumV2 is not allowed there, and the
  # fallback to Premium_LRS handed them a 512e disk that partitions fine.
  # ha-multi-az Anvils are zonal, not set-based, keep their PremiumV2/Ultra
  # metadata disks and depend on this setting the same way.
  logical_sector_size = contains(keys(local.perf_disk), each.key) ? 512 : null

  tags = var.tags

  # Create the disks only once the VM exists, so they are attached seconds
  # after creation instead of sitting unattached while the VM waits on its
  # image. With image_sas_url the VM waits for the whole VHD copy (7 min
  # measured, 2026-10-22), and subscription hygiene automation that reaps
  # unattached disks deleted the metadata disk in that window - the apply
  # then failed at the attachment with "managed disk was not found".
  # Cost: disk creation starts ~2 min later. It changes nothing on destroy:
  # the attachment still goes first, then disk and VM.
  depends_on = [azurerm_linux_virtual_machine.this]

  timeouts {
    delete = "10m"
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  for_each = local.all_disks

  managed_disk_id    = azurerm_managed_disk.data[each.key].id
  virtual_machine_id = azurerm_linux_virtual_machine.this.id
  lun                = each.value.lun
  caching            = "None"

  # Terraform destroys the attachment BEFORE the VM, so a detach is issued
  # against a VM that may be wedged. Azure serialises VM operations, so the
  # detach then queues behind whatever is stuck - that is what hung a destroy
  # for 24+ minutes. Bounded so it fails instead.
  timeouts {
    delete = "10m"
  }
}

# ARM: <vm>/setAdminPassword CustomScript extension - sets the Hammerspace
# 'admin' password (the OS admin account is not the product login).
#
# Deliberately NOT an azurerm_virtual_machine_extension resource: destroying
# that resource waits for the guest agent to uninstall the extension, which
# hangs for many minutes on a busy/half-booted node - and is pointless, since
# the extension is removed with the VM anyway. A create-only az CLI step
# means destroy never touches the guest.
#
# Depends on the disk attachments so the password step cannot race first boot.
resource "terraform_data" "set_admin_password" {
  triggers_replace = [azurerm_linux_virtual_machine.this.id]

  depends_on = [azurerm_virtual_machine_data_disk_attachment.data]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -uo pipefail
      f=$(mktemp)
      trap 'rm -f "$f"' EXIT
      # The password crosses TWO quoting layers and needs escaping for both:
      # json.dumps for the JSON document, and shlex.quote for the shell that
      # CustomScript runs it in. Only the first used to be handled, so a
      # password containing " or $ was silently corrupted or broke the command
      # outright - and hs-init-admin-pw reads it from the environment, so by
      # then the real value is already gone and it cannot detect the damage.
      #
      # No interpreter is named: hs-init-admin-pw installs 0755 (install(PROGRAMS)
      # in pd-system/pd-platform/apps/CMakeLists.txt) with a #!/usr/bin/env python3
      # shebang, so it resolves the right python on EL8 (3.6) and EL9 (3.9/3.11)
      # by itself. Naming a version here is what broke Azure on EL9 (HS-42032).
      #
      # This python3 runs HERE, on whatever machine runs terraform - only to
      # build the JSON. The command inside it is what runs on the node.
      python3 -c 'import json, os, shlex; print(json.dumps({"commandToExecute": "ADMIN_PASSWORD=%s /usr/bin/hs-init-admin-pw" % shlex.quote(os.environ["ADMIN_PASSWORD"])}))' > "$f"
      # Retry: right after VM creation the guest agent may not accept
      # extension operations yet (VMAgentStatusCommunicationError etc.).
      for attempt in $(seq 1 10); do
        if az vm extension set \
          --resource-group "$RG" --vm-name "$VM" \
          --name CustomScript --publisher Microsoft.Azure.Extensions \
          --version 2.0 --extension-instance-name setAdminPassword \
          --protected-settings @"$f" --output none; then
          echo "admin password set (attempt $attempt)"
          exit 0
        fi
        echo "az vm extension set failed (attempt $attempt/10) - retrying in 30s"
        sleep 30
      done
      echo "ERROR: could not set the admin password on $VM after 10 attempts" >&2
      exit 1
    EOT

    environment = {
      RG             = var.resource_group
      VM             = azurerm_linux_virtual_machine.this.name
      ADMIN_PASSWORD = var.admin_password
    }
  }
}
