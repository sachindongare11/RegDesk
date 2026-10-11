# deploy/platform/

Plain Kubernetes manifests (not Helm) for the upstream pieces
`deploy/charts/regdesk` assumes already exist: Qdrant, a RabbitmqCluster
(via the RabbitMQ Cluster Operator), and Ollama. Installed by
`scripts/platform_up.sh` (kind) or `scripts/platform_up_azure.sh` (AKS),
after the cluster exists and before `helm install`/`helm upgrade` on the
chart itself.

- `qdrant.yaml`, `rabbitmq.yaml`, `ollama.yaml`, `ollama-pull-models-job.yaml`,
  `networkpolicies.yaml` -- the kind versions. Used as-is on any cluster
  *except* Ollama's Deployment.
- `azure/ollama.yaml` -- the one file that has to differ: adds the
  nodeSelector + toleration for `infra/modules/aks`'s dedicated,
  tainted `ollama` node pool. kind has no such pool (one node, nothing
  tainted), so the base file has neither field. Apply this one *instead
  of* (not in addition to) `../ollama.yaml` when targeting AKS.

Everything else here (Qdrant, RabbitMQ, the NetworkPolicies, the
model-pull Job) is cluster-agnostic as written -- no Azure variant
needed.

## Why RabbitMQ's credentials need an extra step on Azure

The RabbitMQ Cluster Operator generates `rabbitmq-default-user`'s
password at `RabbitmqCluster` creation time -- Terraform has no way to
know it upfront. So "ingest-worker reads it from Key Vault" (Phase 3's
whole point for this service) needs a one-time sync step, after the
RabbitmqCluster is `Available`, copying that Secret's values into Key
Vault: see `scripts/sync_rabbitmq_secret_to_keyvault.sh`. Nothing here
automates that sync itself -- it's a deliberate, explicit step, not
something that happens silently on every apply.
