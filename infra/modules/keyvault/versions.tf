terraform {
  required_version = "~> 1.16.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.15"
    }
  }
}

data "azurerm_client_config" "current" {}
