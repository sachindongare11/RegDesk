#!/usr/bin/env bash
# Azure variant of platform_up.sh -- same platform pieces, same install
# order, two differences: deploy/platform/azure/ollama.yaml instead of
# the base file (nodeSelector/toleration for the dedicated Ollama node
# pool -- see that file's comment), and a sync of RabbitMQ's generated
# credentials into Key Vault once the RabbitmqCluster is up (see
# scripts/sync_rabbitmq_secret_to_keyvault.sh and deploy/platform/README.md).
#
# Run this against infra/envs/dev's AKS cluster (after `terraform apply`
# there and `az aks get-credentials` -- see that env's README) before
# `helm upgrade --install` on the chart (scripts/deploy_azure.sh does both).
#
# Usage: scripts/platform_up_azure.sh <key-vault-name>
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <key-vault-name>" >&2
  echo "  (infra/envs/dev's key_vault_name output)" >&2
  exit 1
fi

VAULT_NAME="$1"
CERT_MANAGER_VERSION="v1.21.2"
KEDA_VERSION="v2.21.0"
RABBITMQ_OPERATOR_VERSION="v2.23.0"
NAMESPACE="regdesk"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "Installing cert-manager ${CERT_MANAGER_VERSION}..."
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

echo "Waiting for cert-manager to come up..."
kubectl -n cert-manager rollout status deployment/cert-manager --timeout=180s
kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=180s
kubectl -n cert-manager rollout status deployment/cert-manager-cainjector --timeout=180s

echo "Installing the RabbitMQ Cluster Operator ${RABBITMQ_OPERATOR_VERSION}..."
for attempt in 1 2 3 4 5; do
  if kubectl apply -f "https://github.com/rabbitmq/cluster-operator/releases/download/${RABBITMQ_OPERATOR_VERSION}/cluster-operator.yml"; then
    break
  fi
  echo "Retrying RabbitMQ Cluster Operator apply (attempt ${attempt})..."
  sleep 10
done

echo "Installing KEDA ${KEDA_VERSION}..."
# --force-conflicts: AKS's Azure Policy add-on (azure_policy_enabled, see
# infra/modules/aks) runs its own "admissionsenforcer" controller, which
# patches KEDA's ValidatingWebhookConfiguration namespaceSelectors after
# the first apply (exempting Azure's own system namespaces) -- a
# benign field-ownership tug-of-war, but it means a second identical
# apply (e.g. re-running this script) hits a server-side-apply conflict
# without this flag. kind has no Azure Policy add-on, so
# scripts/platform_up.sh never needs it.
kubectl apply --server-side --force-conflicts -f "https://github.com/kedacore/keda/releases/download/${KEDA_VERSION}/keda-${KEDA_VERSION#v}.yaml"

echo "Waiting for the RabbitMQ Cluster Operator to come up..."
kubectl -n rabbitmq-system rollout status deployment/rabbitmq-cluster-operator --timeout=180s

echo "Waiting for KEDA's operator and metrics-apiserver to come up..."
kubectl -n keda rollout status deployment/keda-operator --timeout=180s
kubectl -n keda rollout status deployment/keda-metrics-apiserver --timeout=180s

echo "Applying Qdrant, the RabbitmqCluster CR, and the Azure variant of Ollama into '${NAMESPACE}'..."
kubectl apply -f "${REPO_ROOT}/deploy/platform/qdrant.yaml"
kubectl apply -f "${REPO_ROOT}/deploy/platform/rabbitmq.yaml"
kubectl apply -f "${REPO_ROOT}/deploy/platform/azure/ollama.yaml"

echo "Applying NetworkPolicies..."
kubectl apply -f "${REPO_ROOT}/deploy/platform/networkpolicies.yaml"

echo "Waiting for Qdrant and Ollama to roll out..."
kubectl -n "${NAMESPACE}" rollout status deployment/qdrant --timeout=180s
kubectl -n "${NAMESPACE}" rollout status deployment/ollama --timeout=180s

echo "Waiting for the RabbitmqCluster to report ready..."
kubectl -n "${NAMESPACE}" wait --for=condition=ClusterAvailable rabbitmqcluster/rabbitmq --timeout=300s

echo "Syncing RabbitMQ's generated credentials into Key Vault '${VAULT_NAME}'..."
"${SCRIPT_DIR}/sync_rabbitmq_secret_to_keyvault.sh" "${VAULT_NAME}"

echo "Pulling Ollama models (qwen2.5:3b, nomic-embed-text) -- real internet access here, not a sandboxed laptop, so this should be fast..."
kubectl -n "${NAMESPACE}" delete job ollama-pull-models --ignore-not-found
kubectl apply -f "${REPO_ROOT}/deploy/platform/ollama-pull-models-job.yaml"
kubectl -n "${NAMESPACE}" wait --for=condition=complete job/ollama-pull-models --timeout=600s

echo "Done. Platform pieces are up in namespace '${NAMESPACE}' on AKS."
