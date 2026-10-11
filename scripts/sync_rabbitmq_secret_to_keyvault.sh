#!/usr/bin/env bash
# Copies the RabbitMQ Cluster Operator's generated credentials
# (Secret rabbitmq-default-user, created only after the RabbitmqCluster
# is up -- see deploy/platform/rabbitmq.yaml) into Key Vault, so
# ingest-worker can read them from there instead of referencing that
# Secret directly (see deploy/charts/regdesk/templates/ingest-worker/
# secretproviderclass.yaml).
#
# One-time, explicit, not automated into platform_up_azure.sh's own flow
# silently -- see deploy/platform/README.md for why this has to be a
# separate step at all (the Operator generates the password at
# RabbitmqCluster creation time; Terraform can't know it upfront).
#
# Usage: scripts/sync_rabbitmq_secret_to_keyvault.sh <key-vault-name>
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <key-vault-name>" >&2
  echo "  (infra/envs/dev's key_vault_name output)" >&2
  exit 1
fi

VAULT_NAME="$1"
NAMESPACE="regdesk"
SECRET_NAME="rabbitmq-default-user"

echo "Reading '${SECRET_NAME}' from namespace '${NAMESPACE}'..."
USERNAME=$(kubectl -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.username}' | base64 -d)
PASSWORD=$(kubectl -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.password}' | base64 -d)

echo "Writing 'rabbitmq-username' and 'rabbitmq-password' into Key Vault '${VAULT_NAME}'..."
az keyvault secret set --vault-name "${VAULT_NAME}" --name rabbitmq-username --value "${USERNAME}" --output none
az keyvault secret set --vault-name "${VAULT_NAME}" --name rabbitmq-password --value "${PASSWORD}" --output none

echo "Done. ingest-worker's SecretProviderClass (keyvaultName: ${VAULT_NAME}) can now resolve both secrets."
