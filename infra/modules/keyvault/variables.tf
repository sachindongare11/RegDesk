variable "name" {
  description = "Key Vault name. Globally unique, 3-24 alphanumeric/hyphen characters."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "sku_name" {
  type    = string
  default = "standard"
}

variable "purge_protection_enabled" {
  description = <<-EOT
    Prevents permanent deletion during the retention window, even by an
    Owner -- the right default for a vault holding secrets that matter.
    Defaulted to false here specifically because this is a dev
    environment meant to be destroyed and rebuilt repeatedly, and the
    Phase 3 done-check requires `terraform destroy` to leave nothing
    behind: purge protection makes that impossible (a soft-deleted vault
    lingers for soft_delete_retention_days, visible in the portal, and
    blocks recreating a vault with the same name until it expires or is
    purged by hand). A real/prod environment calling this module should
    pass true and accept that tradeoff.
  EOT
  type        = bool
  default     = false
}

variable "soft_delete_retention_days" {
  type    = number
  default = 7 # minimum allowed; keeps the teardown-and-rebuild dev loop fast
}

variable "tags" {
  type    = map(string)
  default = {}
}
