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

  # No backend block here, deliberately: this config creates the storage
  # account every other Terraform config's backend points at, so it can't
  # depend on one itself. State for this one piece lives locally and is
  # applied by hand (see README.md in this directory).
}

provider "azurerm" {
  features {}
}
