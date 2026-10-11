# infra/bootstrap

Creates the resource group and storage account that hold every other
Terraform config's remote state. Applied once, by hand, with **local**
state -- this config can't use the `azurerm` backend because it's the
thing creating that backend.

## Apply

```bash
cd infra/bootstrap
terraform init
terraform plan   # review before applying -- this creates real, billed resources
terraform apply
terraform output storage_account_name   # copy this into envs/dev's backend block
```

`terraform.tfstate` (and `.backup`) land in this directory afterward --
gitignored, but **do not delete them**. They're the only record of what
this config created; losing them means Terraform can no longer manage (or
cleanly destroy) the resource group and storage account without manual
cleanup in the Azure portal.

## Why this matters for security

Terraform state can contain secrets in plaintext (connection strings,
generated passwords, certain resource attributes) even when the
*configuration* never hardcodes one -- a provider can write a secret value
into state as part of recording a resource's attributes. That makes the
storage account created here sensitive in its own right:

- `min_tls_version = "TLS1_2"` and blob versioning are set so a bad
  `apply` (or an accidental overwrite) can be recovered from.
- Treat this storage account like you'd treat a secrets store: don't
  grant broad access to it, and don't assume "it's just Terraform state"
  means it's safe to make public.

`public_network_access_enabled = true` is left on for this dev
subscription for convenience (no VPN/private endpoint to manage while
iterating). The honest tradeoff: in a real environment this would be
`false` with a private endpoint instead, and `terraform plan` run from
somewhere on that private network (a self-hosted CI runner, a jumpbox).

## Destroy

Only do this if you're tearing down *everything*, including every env
built on top of it -- there's no coming back from this without the state
files.

```bash
cd infra/bootstrap
terraform destroy
```
