output "client_id" {
  value       = azuread_application.this.client_id
  description = "AZURE_CLIENT_ID for azure/login's OIDC mode."
}

output "principal_id" {
  value       = azuread_service_principal.this.object_id
  description = "Grant roles (e.g. AcrPush) against this, not client_id."
}
