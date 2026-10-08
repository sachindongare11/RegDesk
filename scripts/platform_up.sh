#!/usr/bin/env bash
# Install the platform dependencies the regdesk Helm chart assumes already
# exist: cert-manager, the RabbitMQ Cluster Operator + a RabbitmqCluster,
# KEDA, Qdrant, and Ollama (plus a one-shot pull of the two models the
# services need).
#
# Run this against the kind cluster (scripts/kind_up.sh) before
# `helm install regdesk deploy/charts/regdesk -n regdesk`.
set -euo pipefail

CERT_MANAGER_VERSION="v1.21.2"
KEDA_VERSION="v2.21.0"
RABBITMQ_OPERATOR_VERSION="v2.23.0"
NAMESPACE="regdesk"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Installing cert-manager ${CERT_MANAGER_VERSION} (the RabbitMQ Cluster Operator's webhook certs need its Certificate/Issuer CRDs)..."
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

echo "Waiting for cert-manager to come up (its webhook must be ready before Certificate/Issuer objects elsewhere can be admitted)..."
kubectl -n cert-manager rollout status deployment/cert-manager --timeout=180s
kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=180s
kubectl -n cert-manager rollout status deployment/cert-manager-cainjector --timeout=180s

echo "Installing the RabbitMQ Cluster Operator ${RABBITMQ_OPERATOR_VERSION} (cluster-scoped CRDs + controller)..."
# Retried: right after cert-manager's Deployments report Ready, its
# validating webhook can still reject the very first Certificate/Issuer
# apply for a few seconds while the webhook's own TLS serving cert finishes
# propagating -- a short retry loop is simpler than guessing a sleep.
for attempt in 1 2 3 4 5; do
  if kubectl apply -f "https://github.com/rabbitmq/cluster-operator/releases/download/${RABBITMQ_OPERATOR_VERSION}/cluster-operator.yml"; then
    break
  fi
  echo "Retrying RabbitMQ Cluster Operator apply (attempt ${attempt})..."
  sleep 10
done

echo "Installing KEDA ${KEDA_VERSION} (cluster-scoped CRDs + controller)..."
# Note the asset filename drops the leading "v" that the release tag has.
kubectl apply --server-side -f "https://github.com/kedacore/keda/releases/download/${KEDA_VERSION}/keda-${KEDA_VERSION#v}.yaml"

echo "Waiting for the RabbitMQ Cluster Operator to come up..."
kubectl -n rabbitmq-system rollout status deployment/rabbitmq-cluster-operator --timeout=180s

echo "Waiting for KEDA's operator and metrics-apiserver to come up..."
kubectl -n keda rollout status deployment/keda-operator --timeout=180s
kubectl -n keda rollout status deployment/keda-metrics-apiserver --timeout=180s

echo "Applying Qdrant, the RabbitmqCluster CR, and Ollama into '${NAMESPACE}'..."
kubectl apply -f "${REPO_ROOT}/deploy/platform/qdrant.yaml"
kubectl apply -f "${REPO_ROOT}/deploy/platform/rabbitmq.yaml"
kubectl apply -f "${REPO_ROOT}/deploy/platform/ollama.yaml"

echo "Applying NetworkPolicies so the regdesk workloads (and the model-pull Job below) can actually reach these pods -- deploy/charts/regdesk's own default-deny (templates/networkpolicy-default-deny.yaml) deliberately doesn't select pods outside the chart, so each platform piece needs its own ingress allow-list here instead..."
kubectl apply -f "${REPO_ROOT}/deploy/platform/networkpolicies.yaml"

echo "Waiting for Qdrant and Ollama to roll out..."
kubectl -n "${NAMESPACE}" rollout status deployment/qdrant --timeout=180s
kubectl -n "${NAMESPACE}" rollout status deployment/ollama --timeout=180s

echo "Waiting for the RabbitmqCluster to report ready (operator provisions the StatefulSet + default-user Secret)..."
kubectl -n "${NAMESPACE}" wait --for=condition=ClusterAvailable rabbitmqcluster/rabbitmq --timeout=300s

echo "Pulling Ollama models (qwen2.5:3b, nomic-embed-text) -- this can take a few minutes on first run..."
# Re-running this script re-applies the same Job; delete any previous
# completed/failed one first since Jobs are immutable once created.
kubectl -n "${NAMESPACE}" delete job ollama-pull-models --ignore-not-found
kubectl apply -f "${REPO_ROOT}/deploy/platform/ollama-pull-models-job.yaml"
kubectl -n "${NAMESPACE}" wait --for=condition=complete job/ollama-pull-models --timeout=600s

echo "Done. Platform pieces are up in namespace '${NAMESPACE}':"
echo "  - qdrant        (Deployment/Service, port 6333)"
echo "  - rabbitmq      (RabbitmqCluster, Secret rabbitmq-default-user)"
echo "  - ollama        (Deployment/Service, port 11434, models pulled)"
echo "  - KEDA and the RabbitMQ Cluster Operator (cluster-scoped, namespaces keda / rabbitmq-system)"
