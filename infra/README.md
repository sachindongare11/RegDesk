# infra/

Terraform for every Azure resource RegDesk needs. Populated in **Phase 3**.

- `bootstrap/` -- resource group + storage account holding Terraform remote
  state. Applied once by hand; everything after it uses the `azurerm` backend.
- `envs/dev/` -- the dev environment: resource group, AKS, ACR, Key Vault,
  managed identity.
- `modules/` -- reusable modules (`aks`, `acr`, `keyvault`) consumed by
  `envs/dev` and, optionally, `envs/aws-dev` in Phase 8.

Not used by Phases 1-2, which run entirely on Docker Compose / kind.
