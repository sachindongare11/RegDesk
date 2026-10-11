resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project}-${var.environment}"
  location = var.location
  tags     = var.tags
}

module "acr" {
  source = "../../modules/acr"

  name                = "acr${var.project}${var.environment}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

module "keyvault" {
  source = "../../modules/keyvault"

  name                = "kv-${var.project}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
  # purge_protection_enabled left at the module's default (false) -- see
  # infra/modules/keyvault/variables.tf for why.
}

module "aks" {
  source = "../../modules/aks"

  name                = "aks-${var.project}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  dns_prefix          = "${var.project}-${var.environment}"
  tags                = var.tags
}

# -- Point 4 of the Phase 3 spec: AcrPull for the kubelet identity --
# This is what AKS's nodes actually use to pull images -- distinct from
# the cluster's own control-plane identity (SystemAssigned, see
# infra/modules/aks/main.tf) and from ingest-worker's workload identity
# below. Scoped to pull-only, nothing else.
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                = module.acr.id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity_object_id
}

# -- Point 4: a federated credential so ingest-worker reads RabbitMQ
# credentials from Key Vault with no stored secrets --
#
# This user-assigned identity is NOT the cluster's control-plane identity
# (that's SystemAssigned, inside the aks module) and NOT the kubelet
# identity (that's auto-created by AKS, used only for image pulls above).
# It exists purely so ingest-worker's pod can federate its Kubernetes
# ServiceAccount against it and request Key Vault tokens directly.
resource "azurerm_user_assigned_identity" "ingest_worker" {
  name                = "id-${var.project}-ingest-worker-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "ingest_worker" {
  name                      = "ingest-worker-workload-identity"
  user_assigned_identity_id = azurerm_user_assigned_identity.ingest_worker.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = module.aks.oidc_issuer_url
  # system:serviceaccount:<namespace>:<name> -- must match the
  # ServiceAccount the Helm chart creates for ingest-worker exactly, or
  # this federation never matches anything (see variables.tf's comment).
  subject = "system:serviceaccount:${var.ingest_worker_namespace}:${var.ingest_worker_service_account}"
}

resource "azurerm_role_assignment" "ingest_worker_keyvault_secrets_user" {
  scope                = module.keyvault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.ingest_worker.principal_id
}

# -- Cluster admin access for whoever is running Terraform --
# Required because the aks module sets local_account_disabled = true +
# azure_rbac_enabled = true (see its main.tf) -- with no static admin
# kubeconfig and no admin_group_object_ids, NO ONE has cluster access
# until an Azure RBAC role is explicitly granted on some principal. This
# grants it to the identity currently authenticated to `az`/Terraform
# (i.e. whoever ran `az login`), which for a single-developer dev
# environment is the right scope -- a real team would grant this to an
# Entra ID group instead, not an individual.
resource "azurerm_role_assignment" "deployer_cluster_admin" {
  scope                = module.aks.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

# -- Write access to Key Vault for whoever is running Terraform --
# ingest_worker_keyvault_secrets_user (above) only grants ingest-worker's
# identity *read* access ("Key Vault Secrets User") -- nothing can write
# the RabbitMQ credentials into the vault in the first place without
# this. Needed for the one-time sync in
# scripts/sync_rabbitmq_secret_to_keyvault.sh, same deploying-principal
# scope reasoning as deployer_cluster_admin above.
resource "azurerm_role_assignment" "deployer_keyvault_secrets_officer" {
  scope                = module.keyvault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# -- Phase 4 point 7: GitHub Actions -> Azure via OIDC, no stored secret --
# Scoped to pushes on main only (see the module's github_refs default) --
# the only Phase 4 job that needs Azure access at all is "build, scan,
# and push images on merge to main." Every PR-time check (ruff, pytest,
# terraform fmt/tflint/checkov) is local static analysis with nothing to
# authenticate to.
#
# github_repo is NOT "owner/repo" -- see the module variable's own
# comment on why. Confirmed via:
#   gh api repos/sachindongare11/RegDesk/actions/oidc/customization/sub
# which returned sub_claim_prefix
# "repo:sachindongare11@37418535/RegDesk@1410825958" (immutable
# subjects, this account's default). First deploy attempt failed with
# AADSTS700213 using the plain "owner/repo" form -- the actual presented
# subject claim in that failure's azure/login log is what confirmed the
# real format to use here.
module "github_actions_oidc" {
  source = "../../modules/github-oidc"

  display_name = "regdesk-github-actions"
  github_repo  = "sachindongare11@37418535/RegDesk@1410825958"
}

resource "azurerm_role_assignment" "github_actions_acr_push" {
  scope                = module.acr.id
  role_definition_name = "AcrPush"
  principal_id         = module.github_actions_oidc.principal_id
}
