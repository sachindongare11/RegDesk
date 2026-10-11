#!/usr/bin/env bash
# Builds and pushes the three service images to ACR, then
# helm upgrade --install's the chart against infra/envs/dev's AKS
# cluster with values-azure.yaml plus the handful of values only known
# after `terraform apply` (ACR login server, Key Vault name/tenant,
# ingest-worker's workload identity client ID) pulled live from
# `terraform output`.
#
# Run scripts/platform_up_azure.sh first -- this assumes Qdrant,
# RabbitMQ, Ollama, and KEDA already exist, same dependency order as
# Phase 2's kind flow.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TAG="${1:-latest}"
SERVICES=(mcp-tools agent-api ingest-worker)

echo "Reading infra/envs/dev's Terraform outputs..."
cd "${REPO_ROOT}/infra/envs/dev"
ACR_LOGIN_SERVER="$(terraform output -raw acr_login_server)"
KEY_VAULT_NAME="$(terraform output -raw key_vault_name)"
INGEST_WORKER_CLIENT_ID="$(terraform output -raw ingest_worker_identity_client_id)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
cd "${REPO_ROOT}"

echo "Logging into ACR '${ACR_LOGIN_SERVER}'..."
az acr login --name "${ACR_LOGIN_SERVER%%.*}"

for svc in "${SERVICES[@]}"; do
  image="${ACR_LOGIN_SERVER}/${svc}:${TAG}"
  echo "Building and pushing ${image} (linux/amd64)..."
  # --platform linux/amd64, explicitly: AKS's Standard_Dsv4-series nodes
  # are x86-64, but a plain `docker build` on an Apple Silicon Mac
  # produces an arm64 image by default -- the kubelet's pull then fails
  # with "no match for platform in manifest" (discovered the hard way: it
  # otherwise looks exactly like a registry auth error). --push builds and
  # pushes in one step; buildx doesn't load cross-platform images into the
  # local Docker daemon the way `docker build` does.
  docker buildx build --platform linux/amd64 --push -t "${image}" "${REPO_ROOT}/services/${svc}"
done

echo "Deploying the chart..."
helm upgrade --install regdesk "${REPO_ROOT}/deploy/charts/regdesk" \
  --namespace regdesk --create-namespace \
  -f "${REPO_ROOT}/deploy/charts/regdesk/values-azure.yaml" \
  --set mcpTools.image.repository="${ACR_LOGIN_SERVER}/mcp-tools" \
  --set mcpTools.image.tag="${TAG}" \
  --set agentApi.image.repository="${ACR_LOGIN_SERVER}/agent-api" \
  --set agentApi.image.tag="${TAG}" \
  --set ingestWorker.image.repository="${ACR_LOGIN_SERVER}/ingest-worker" \
  --set ingestWorker.image.tag="${TAG}" \
  --set ingestWorker.azureKeyVault.vaultName="${KEY_VAULT_NAME}" \
  --set ingestWorker.azureKeyVault.tenantId="${TENANT_ID}" \
  --set ingestWorker.azureKeyVault.clientId="${INGEST_WORKER_CLIENT_ID}"

echo "Done. 'helm -n regdesk list' to check the release; 'kubectl -n regdesk get pods' for pod status."
