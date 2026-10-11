output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  value = module.aks.name
}

output "acr_login_server" {
  value = module.acr.login_server
}

output "key_vault_name" {
  value = module.keyvault.name
}

output "ingest_worker_identity_client_id" {
  value       = azurerm_user_assigned_identity.ingest_worker.client_id
  description = "Goes on the ingest-worker ServiceAccount's azure.workload.identity/client-id annotation when the Helm chart is adapted for this cluster."
}

output "github_actions_client_id" {
  value       = module.github_actions_oidc.client_id
  description = "AZURE_CLIENT_ID GitHub Actions secret -- see .github/workflows/README.md."
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}
