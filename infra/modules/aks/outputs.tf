output "id" {
  value = azurerm_kubernetes_cluster.this.id
}

output "name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "oidc_issuer_url" {
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
  description = "What a federated identity credential (e.g. ingest-worker's, in infra/envs/dev) trusts against."
}

output "kubelet_identity_object_id" {
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  description = "Grant this AcrPull on the registry -- it's what the nodes actually use to pull images, distinct from the cluster's own control-plane identity."
}

output "kube_config_raw" {
  value     = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive = true
}
