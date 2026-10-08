#!/usr/bin/env bash
# Create (or reuse) the RegDesk kind cluster and install Calico as its CNI.
#
# kind's bundled CNI (kindnet) accepts NetworkPolicy objects but never
# enforces them -- every pod can reach every other pod regardless of what
# the policies say. Phase 2 relies on real enforcement (default-deny +
# explicit allow-lists), so this script disables kindnet at cluster-create
# time (see deploy/kind-cluster.yaml) and installs Calico in its place.
set -euo pipefail

CALICO_VERSION="v3.33.0"
CLUSTER_NAME="regdesk"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "kind cluster '${CLUSTER_NAME}' already exists, reusing it."
else
  echo "Creating kind cluster '${CLUSTER_NAME}' (CNI disabled)..."
  kind create cluster --config "${REPO_ROOT}/deploy/kind-cluster.yaml"
fi

kubectl config use-context "kind-${CLUSTER_NAME}"

echo "Installing Calico ${CALICO_VERSION}..."
kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"

echo "Waiting for Calico to report Ready (this can take a minute or two)..."
kubectl -n kube-system rollout status daemonset/calico-node --timeout=180s
kubectl -n kube-system rollout status deployment/calico-kube-controllers --timeout=180s

echo "Waiting for all node(s) to go Ready now that a CNI is installed..."
kubectl wait --for=condition=Ready nodes --all --timeout=180s

echo "Creating the 'regdesk' namespace..."
kubectl create namespace regdesk --dry-run=client -o yaml | kubectl apply -f -

echo "Installing metrics-server (required for the agent-api HPA)..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# kind's kubelets serve a self-signed cert metrics-server won't trust by
# default; --kubelet-insecure-tls is the standard kind workaround (fine for
# a local dev cluster, never do this against a real cluster).
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl -n kube-system rollout status deployment/metrics-server --timeout=120s

echo "Done. Cluster '${CLUSTER_NAME}' is up with Calico enforcing NetworkPolicies."
echo "Context: kind-${CLUSTER_NAME}  Namespace: regdesk"
