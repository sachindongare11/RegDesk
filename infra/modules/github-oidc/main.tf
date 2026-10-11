# Lets GitHub Actions authenticate to Azure with zero stored secrets --
# same workload-identity principle as infra/modules/aks's pods, just for
# CI instead of a Kubernetes ServiceAccount. azure/login's own OIDC mode
# exchanges a GitHub-minted token for an Azure AD token via the
# federated credential below; nothing resembling a password or client
# secret ever exists for this identity.

resource "azuread_application" "this" {
  display_name = var.display_name
}

resource "azuread_service_principal" "this" {
  client_id = azuread_application.this.client_id
}

resource "azuread_application_federated_identity_credential" "this" {
  # checkov:skip=CKV_AZURE_249: this check reads the raw HCL string
  # ("repo:${var.github_repo}:${each.value}") rather than resolving the
  # for_each/interpolation, so it can't see the actual value -- which
  # IS correctly scoped: an exact repo, an exact ref (github_refs'
  # default is a single named branch, no wildcards), no "*" anywhere.
  # Confirmed by reading checkov's own check source
  # (GithubActionsOIDCTrustPolicy.py): it fails anything it can't parse
  # as a literal subject string, which any for_each-derived value here
  # always will be.
  for_each = toset(var.github_refs)

  application_id = azuread_application.this.id
  display_name   = "github-${replace(each.value, "/[^a-zA-Z0-9-]/", "-")}"
  description    = "GitHub Actions OIDC trust for ${var.github_repo} (${each.value})"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:${each.value}"
}
