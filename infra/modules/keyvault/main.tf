resource "azurerm_key_vault" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  tenant_id = data.azurerm_client_config.current.tenant_id
  sku_name  = var.sku_name

  # RBAC, not the legacy access-policy model -- access is granted with
  # ordinary azurerm_role_assignment resources against this vault's scope
  # (see infra/envs/dev, which grants ingest-worker's federated identity
  # Key Vault Secrets User here), consistent with how every other
  # permission in this project is granted (AcrPull on the registry, etc.)
  # rather than a second, parallel permission model just for this vault.
  rbac_authorization_enabled = true

  # checkov:skip=CKV_AZURE_110: see variables.tf's purge_protection_enabled
  # description -- off by default specifically so this dev environment's
  # `terraform destroy` can leave nothing behind, per the Phase 3 done-check.
  # checkov:skip=CKV_AZURE_42: same vault-recoverability tradeoff as above.
  purge_protection_enabled   = var.purge_protection_enabled
  soft_delete_retention_days = var.soft_delete_retention_days

  # checkov:skip=CKV_AZURE_189: dev convenience, same as infra/bootstrap's
  # storage account -- no VPN/private endpoint set up yet to reach this
  # vault otherwise, and `terraform apply` itself runs from a laptop with
  # no fixed IP.
  # checkov:skip=CKV_AZURE_109: firewall rules (network_acls) would be the
  # mechanism for scoping that access down; left open for the same reason.
  # checkov:skip=CKV2_AZURE_32: same no-private-endpoint-set-up-yet
  # tradeoff as the two skips above, just the graph-check version of it.
  public_network_access_enabled = true
}
