# infra/

Terraform for every Azure resource RegDesk needs. Populated in **Phase 3**.

- `bootstrap/` -- resource group + storage account holding Terraform remote
  state. Applied once by hand; everything after it uses the `azurerm` backend.
  See `bootstrap/README.md`.
- `envs/dev/` -- the dev environment: resource group, AKS (two node pools,
  workload identity, Key Vault CSI add-on, Calico network policy), ACR,
  Key Vault, and the user-assigned identity + federated credential that
  let `ingest-worker` read secrets from Key Vault with no stored
  credential. See `envs/dev/README.md`, especially for `kubectl` access --
  this cluster has no local admin account.
- `modules/` -- reusable modules (`aks`, `acr`, `keyvault`) consumed by
  `envs/dev` and, optionally, `envs/aws-dev` in Phase 8.
- `.tflint.hcl` -- shared TFLint config (the `azurerm` ruleset plugin);
  every subdirectory here lints against it: `tflint --config ../../.tflint.hcl`
  (adjust `../..` to wherever you're running from).

## Apply order

`bootstrap` first (by hand, local state), then `envs/dev` (remote state,
backend pointed at bootstrap's output). `envs/dev` never touches
`bootstrap`'s resources or vice versa -- separate state files,
deliberately, so destroying one environment can never take out the state
backend everything else depends on.

## Before every apply

```bash
terraform fmt -check
terraform validate
tflint --config <path-to-this-dir>/.tflint.hcl
checkov -d . --framework terraform --compact
```

All three (fmt, tflint, checkov) run clean (0 failures) as of this
writing, modulo documented `checkov:skip` annotations -- each one has an
inline comment explaining the tradeoff (almost always: dev cost, or a
feature gated behind setup that hasn't been done yet, like a VPN or a
subscription feature registration). Grep for `checkov:skip` to read all
of them. These become CI gates in Phase 4; running them locally first
means Phase 4 just automates what's already known to pass.

Not used by Phases 1-2, which run entirely on Docker Compose / kind.
