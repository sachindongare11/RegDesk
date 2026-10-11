# deploy/argocd/

Argo CD `Application` manifests. One Application here: `regdesk`,
pointing at `deploy/charts/regdesk` with automated sync and self-heal.

## Install Argo CD (once, by hand)

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --set configs.params."server\.insecure"=true  # dev convenience: no TLS cert to manage for the UI/API behind kubectl port-forward
```

## Hand off from the manual deploy to GitOps (once)

If `scripts/deploy_azure.sh` was ever run by hand against this cluster,
there's an existing Helm release (`regdesk`, in namespace `regdesk`)
that Argo CD doesn't know about. Remove it first so there's exactly one
system managing these resources going forward, not two:

```bash
helm uninstall regdesk -n regdesk
```

(This only deletes the Helm release *metadata* and the resources it
created -- Qdrant/RabbitMQ/Ollama in `deploy/platform/`, installed
separately, are untouched.)

## Apply the Application

```bash
kubectl apply -f deploy/argocd/application.yaml
```

Argo CD takes it from here: it renders the chart with
`values-dev.yaml`, applies the result, and re-applies it automatically
on every change to `main` (including the `image.tag` edits
`.github/workflows/deploy.yml` commits on every merge) and on any drift
from a manual `kubectl` change (`selfHeal: true`).

## Watching it work

```bash
# Via the CLI (no port-forward needed for this):
kubectl -n argocd get application regdesk

# Via the UI:
kubectl -n argocd port-forward svc/argocd-server 8080:443
# https://localhost:8080 -- username "admin", password from:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## Testing self-heal

```bash
kubectl -n regdesk delete deployment agent-api
# watch Argo CD notice the drift and recreate it, typically within ~3
# minutes (its default reconciliation interval) or near-instantly if
# you trigger a manual sync:
kubectl -n argocd get application regdesk -w
```
