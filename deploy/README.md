# deploy/

Everything Argo CD syncs to the cluster. Nothing reaches AKS except through
this directory and Git.

- `charts/regdesk/` -- one Helm chart covering all three services
  (`agent-api`, `mcp-tools`, `ingest-worker`): Deployment, Service,
  ServiceAccount, ConfigMap, HPA, KEDA ScaledObject, NetworkPolicies.
  Populated in **Phase 2** (local kind cluster), then pointed at ACR images
  from **Phase 4** onward.
- `argocd/` -- Argo CD `Application` manifests pointing at this repo.
  Populated in **Phase 4**.
- `platform/` -- values files for the upstream charts/operators this
  project depends on but doesn't own: Qdrant, the RabbitMQ Cluster
  Operator, Ollama, kube-prometheus-stack. Also where the Grafana
  dashboard JSON lands in **Phase 5**.
