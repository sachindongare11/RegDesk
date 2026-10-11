# Applied once, by hand, before anything else:
#
#   cd infra/bootstrap
#   terraform init
#   terraform apply
#
# This creates the one thing every other Terraform config in infra/ needs
# before it can run: somewhere to store state remotely. It can't use that
# backend itself -- you can't point a backend at a storage account that
# doesn't exist yet -- so this state stays local (infra/bootstrap/terraform.tfstate,
# gitignored, keep it safe: it's the only record of what this created).
#
# After apply, note the storage_account_name output -- infra/envs/dev's
# backend block needs it.

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_resource_group" "state" {
  name     = "rg-${var.project}-tfstate"
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "state" {
  # Storage account names must be globally unique across all of Azure,
  # 3-24 lowercase alphanumeric characters -- the random suffix avoids a
  # clash with another subscription without needing to hand-pick one.
  name                = "st${var.project}tfstate${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  tags                = var.tags

  account_tier = "Standard"
  # checkov:skip=CKV_AZURE_206: dev state, single region; GRS costs more for
  # a bucket this disposable. See README.md's tradeoff section.
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false # no container should ever be publicly readable, dev or not

  # checkov:skip=CKV_AZURE_33: queue logging IS configured, via the
  # dedicated azurerm_storage_account_queue_properties resource below
  # (the non-deprecated replacement for this resource's own nested
  # queue_properties block, removed in azurerm provider v5.0) -- checkov's
  # policy for this check hasn't caught up to that provider schema split
  # and still only looks for the old nested block.
  #
  # Terraform state can contain secrets in plaintext (see README.md in
  # this directory) -- both of these matter even for a dev subscription.
  blob_properties {
    versioning_enabled = true # recover from a bad `terraform apply` overwriting state
    # Free, zero-downside: lets a wrongly-deleted state blob be
    # recovered within the window instead of being gone immediately.
    delete_retention_policy {
      days = 7
    }
  }
  # checkov:skip=CKV_AZURE_59: dev convenience -- `terraform apply` runs
  # from a laptop with no fixed IP/VPN to this subscription yet. See
  # README.md's tradeoff section for what a private-endpoint setup would
  # look like instead.
  # checkov:skip=CKV2_AZURE_33: same tradeoff as CKV_AZURE_59 above --
  # no private endpoint set up for this dev subscription yet.
  public_network_access_enabled = true

  # checkov:skip=CKV2_AZURE_41: this account is never accessed via SAS
  # tokens at all (Terraform's backend and every manual `az` command use
  # Azure AD auth or the account key directly, never a SAS) -- an
  # expiration policy for a mechanism nothing here uses doesn't add
  # protection.
  # checkov:skip=CKV2_AZURE_40: disabling shared-key auth
  # (shared_access_key_enabled = false) would require the Terraform
  # backend to switch to use_azuread_auth = true *and* every principal
  # that runs `terraform init`/`plan`/`apply` against this backend to
  # first have Storage Blob Data Contributor granted explicitly --
  # Azure RBAC's control-plane roles (Owner/Contributor) don't
  # automatically carry that data-plane permission. Worth doing, but as
  # a deliberate, sequenced change (grant the role, verify AAD auth
  # works, *then* disable shared key) -- not a one-line flip to make
  # under a lint gate, where getting the order wrong risks locking out
  # state access entirely.
  # checkov:skip=CKV2_AZURE_1: customer-managed-key encryption adds a Key
  # Vault dependency for marginal benefit over the platform-managed
  # encryption already active by default -- same tradeoff as
  # infra/modules/aks's CKV_AZURE_117 skip.
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
  # checkov:skip=CKV2_AZURE_21: blob read-request logging needs either
  # deprecated classic storage analytics logging or a full Azure Monitor
  # diagnostic setting (itself needing a Log Analytics workspace or
  # another storage destination) -- same "that's Phase 5's observability
  # work, not this one's" reasoning as infra/modules/aks's CKV_AZURE_4 skip.
}

resource "azurerm_storage_account_queue_properties" "state" {
  storage_account_id = azurerm_storage_account.state.id

  # No queue is actually used on this account (blob only, for tfstate),
  # but CKV_AZURE_33 wants queue logging enabled regardless -- harmless
  # to satisfy since it costs nothing idle.
  logging {
    delete                = true
    read                  = true
    write                 = true
    version               = "1.0"
    retention_policy_days = 7
  }
}
