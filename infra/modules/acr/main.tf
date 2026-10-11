resource "azurerm_container_registry" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  tags                = var.tags

  # admin_user defaults to false and is left that way deliberately: nothing
  # should authenticate to this registry with a static username/password.
  # AKS's kubelet identity gets AcrPull via the role assignment in
  # infra/envs/dev instead (see that config's comment on why), and CI
  # (Phase 4) will use the GitHub OIDC federation from point 7 of the
  # Phase 3 spec -- neither needs admin_enabled.

  # checkov:skip=CKV_AZURE_237: dedicated data endpoints are Premium-only.
  # checkov:skip=CKV_AZURE_233: zone redundancy is Premium-only.
  # checkov:skip=CKV_AZURE_167: retention policies are Premium-only.
  # checkov:skip=CKV_AZURE_164: content trust (signed images) is Premium-only.
  # checkov:skip=CKV_AZURE_165: geo-replication is Premium-only, and moot
  # for a single-region dev cluster besides.
  # checkov:skip=CKV_AZURE_166: image quarantine is Premium-only.
  # checkov:skip=CKV_AZURE_139: private endpoints are Premium-only; public
  # access is the same dev tradeoff as the storage account and Key Vault
  # (no VPN/private endpoint set up yet).
  #
  # None of the above are available on Basic -- Premium runs roughly 10x
  # Basic's monthly cost for a registry holding 3 small service images on
  # a $200 dev credit, so Basic is the deliberate choice here. A real
  # environment serving traffic would use Premium and get all of these
  # for free with no config change beyond the sku variable.
  #
  # checkov:skip=CKV_AZURE_163: vulnerability scanning is Microsoft
  # Defender for Containers, a subscription-level Defender plan
  # (azurerm_security_center_subscription_pricing), not an ACR-resource
  # property -- out of scope for this module, worth adding at the
  # subscription level if this review goes past dev/learning scope.
}
