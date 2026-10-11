output "resource_group_name" {
  value = azurerm_resource_group.state.name
}

output "storage_account_name" {
  value       = azurerm_storage_account.state.name
  description = "Needed by infra/envs/dev's backend \"azurerm\" block."
}

output "container_name" {
  value = azurerm_storage_container.tfstate.name
}
