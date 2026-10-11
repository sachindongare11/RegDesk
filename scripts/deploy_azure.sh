#!/usr/bin/env bash
# Manual/local equivalent of what .github/workflows/deploy.yml does on
# every merge to main: build and push the three service images to ACR,
# then helm upgrade --install with values-dev.yaml.
#
# Since Phase 4, values-dev.yaml carries the ACR repository paths, Key
# Vault name/tenant, and ingest-worker's client ID as plain static
# values (committed to git, since Argo CD's sync is fully declarative
# and can't take --set flags) -- this script only needs to override the
# image tag for an ad-hoc local build, matching whatever the CI workflow
# would otherwise write there.
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

echo "Deploying the chart with tag '${TAG}'..."
helm upgrade --install regdesk "${REPO_ROOT}/deploy/charts/regdesk" \
  --namespace regdesk --create-namespace \
  -f "${REPO_ROOT}/deploy/charts/regdesk/values-dev.yaml" \
  --set mcpTools.image.tag="${TAG}" \
  --set agentApi.image.tag="${TAG}" \
  --set ingestWorker.image.tag="${TAG}"

echo "Done. 'helm -n regdesk list' to check the release; 'kubectl -n regdesk get pods' for pod status."
