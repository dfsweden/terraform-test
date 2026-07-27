provider "azurerm" {
  features {
    # Destroys must never wait for a clean guest shutdown - delete VMs
    # forcefully (skip the graceful shutdown + use forceDeletion).
    virtual_machine {
      skip_shutdown_and_force_delete = true
    }
  }

  # Empty = use the Azure CLI's current subscription (az account show).
  subscription_id = var.subscription_id != "" ? var.subscription_id : null
}
