terraform {
  required_version = "~> 1.16.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.15"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Points at the storage account infra/bootstrap created. Fill in
  # storage_account_name after running `terraform output storage_account_name`
  # there -- see infra/bootstrap/README.md. Left as a placeholder rather
  # than a variable because backend blocks can't use variables; this is
  # the one place a real value has to be hardcoded.
  backend "azurerm" {
    resource_group_name  = "rg-regdesk-tfstate"
    container_name       = "tfstate"
    key                  = "envs/dev.tfstate"
    storage_account_name = "stregdesktfstateh8qp1l"
  }
}

provider "azurerm" {
  features {
    key_vault {
      # Lets `terraform destroy` fully remove the vault instead of leaving
      # a soft-deleted one behind for soft_delete_retention_days -- see
      # infra/modules/keyvault/variables.tf's purge_protection_enabled
      # comment for why that matters for this dev environment's
      # clean-teardown requirement.
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

data "azurerm_client_config" "current" {}
