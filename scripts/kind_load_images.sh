#!/usr/bin/env bash
# Build the three service images and load them into the kind cluster's
# node, so the regdesk chart's pullPolicy: Never (see values.yaml) can find
# them without a registry. Run this after scripts/kind_up.sh and before
# `helm install`/`helm upgrade` -- re-run it any time service code changes,
# since `pullPolicy: Never` means the cluster never checks anywhere else.
set -euo pipefail

CLUSTER_NAME="regdesk"
TAG="local"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SERVICES=(mcp-tools agent-api ingest-worker)

for svc in "${SERVICES[@]}"; do
  image="regdesk/${svc}:${TAG}"
  echo "Building ${image} from services/${svc}..."
  docker build -t "${image}" "${REPO_ROOT}/services/${svc}"
done

for svc in "${SERVICES[@]}"; do
  image="regdesk/${svc}:${TAG}"
  echo "Loading ${image} into kind cluster '${CLUSTER_NAME}'..."
  kind load docker-image "${image}" --name "${CLUSTER_NAME}"
done

echo "Done. Images loaded (tag ${TAG}):"
for svc in "${SERVICES[@]}"; do
  echo "  - regdesk/${svc}:${TAG}"
done
