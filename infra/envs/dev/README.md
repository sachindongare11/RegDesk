# infra/envs/dev

The dev environment: one resource group holding an AKS cluster (two node
pools -- see `infra/modules/aks`), an ACR, a Key Vault, and the
user-assigned identity + federated credential that let `ingest-worker`
read its RabbitMQ credentials from Key Vault with no stored secret.

## First-time setup

1. Apply `infra/bootstrap` first (see its own README) and note its
   `storage_account_name` output.
2. Edit `versions.tf` here: replace `REPLACE_WITH_BOOTSTRAP_OUTPUT` with
   that value.
3. `terraform init && terraform plan` -- review before applying.
4. `terraform apply`.

## Getting `kubectl` access

This cluster has `local_account_disabled = true` (see
`infra/modules/aks/main.tf`'s comment on why) -- there is no admin
kubeconfig to download. Every `kubectl` session authenticates through
Entra ID instead, via Azure RBAC (`azure_rbac_enabled = true`), and the
`azurerm_role_assignment.deployer_cluster_admin` resource in `main.tf`
grants that access to whoever is logged into `az` when `terraform apply`
runs.

```bash
# One-time: kubelogin plugs Entra ID auth into kubectl.
brew install Azure/kubelogin/kubelogin

az aks get-credentials \
  --resource-group "$(terraform output -raw resource_group_name)" \
  --name "$(terraform output -raw aks_cluster_name)" \
  --overwrite-existing

kubelogin convert-kubeconfig -l azurecli

kubectl get nodes   # first run opens a browser / device-code prompt
```

The browser/device-code prompt happens once per kubeconfig token
lifetime (a few hours), not once per command.

## Deploying the regdesk Helm chart here instead of kind

Two things change from Phase 2's kind deployment:

1. **Ollama needs a toleration + node selector** for the dedicated
   `ollama` node pool's taint (`workload=ollama:NoSchedule`) and label
   (`workload: ollama`) -- Phase 2's chart assumed a single untainted
   pool. Add both to Ollama's pod spec before deploying here.
2. **ingest-worker's RabbitMQ credentials come from Key Vault, not a
   Kubernetes Secret.** Its ServiceAccount needs the
   `azure.workload.identity/client-id` annotation set to this config's
   `ingest_worker_identity_client_id` output, plus the
   `azure.workload.identity/use: "true"` pod label, and a
   `SecretProviderClass` pointing at the Key Vault secret names instead
   of the `secretKeyRef` the Phase 2 chart uses against the RabbitMQ
   Cluster Operator's generated Secret directly.

Neither change is made yet -- this environment provisions the
*platform*; adapting the chart for it is the next piece of work.

## Teardown

```bash
terraform destroy
```

This leaves `infra/bootstrap`'s resource group and storage account
untouched (they're a separate state) -- destroy those separately, and
only if you're tearing down everything including the ability to manage
this environment at all.
