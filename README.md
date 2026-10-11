# RegDesk

[![CI](https://github.com/sachindongare11/RegDesk/actions/workflows/ci.yml/badge.svg)](https://github.com/sachindongare11/RegDesk/actions/workflows/ci.yml)
[![Build, scan, push, deploy](https://github.com/sachindongare11/RegDesk/actions/workflows/deploy.yml/badge.svg)](https://github.com/sachindongare11/RegDesk/actions/workflows/deploy.yml)

A regulatory Q&A agent for Irish financial services -- ask things like *"What
does DORA require for ICT incident reporting?"* and get a cited answer drawn
from DORA, the EU AI Act, and the Central Bank of Ireland Consumer
Protection Code. Deployed on Azure Kubernetes Service, provisioned with
Terraform, delivered through GitHub Actions + Argo CD GitOps. See
[docs/architecture.md](docs/architecture.md) for the full design and the
"Decisions" table below for the short version.

**Status: Phases 1-4 complete and validated live** -- the three services run
locally via Docker Compose (Phase 1), on a local `kind` cluster with
Calico-enforced NetworkPolicies and KEDA autoscaling (Phase 2), on a real AKS
cluster provisioned by Terraform with workload identity and zero stored
secrets (Phase 3), and merging a one-line change to `main` reaches that
cluster through CI (test, scan, build, push) and Argo CD's GitOps sync with
no manual `kubectl` (Phase 4, including a live self-heal test: deleting a
Deployment by hand, Argo CD puts it back). Phases 5-8 (observability,
security/identity, chaos drills, optional AWS) are tracked in the
[Build phases](#build-phases) section.

## Run it locally

```bash
git clone <this-repo> && cd regdesk
make up             # builds and starts qdrant, rabbitmq, ollama, and all 3 services
make pull-models     # one-time: pulls qwen2.5:3b and nomic-embed-text into Ollama
make ingest          # publishes the sample corpus onto the RabbitMQ ingest queue
make ask             # curl's /ask with a sample question once ingestion finishes
```

`make ask` runs:

```bash
curl -s -X POST localhost:8080/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "What does DORA require for ICT incident reporting?"}'
```

## Run it on Kubernetes

**Locally, on `kind`** (no cloud, no cost):

```bash
scripts/kind_up.sh              # creates the cluster, installs Calico
scripts/platform_up.sh          # cert-manager, RabbitMQ Operator, KEDA, Qdrant, RabbitMQ, Ollama
scripts/kind_load_images.sh     # builds the 3 service images, loads them into kind
helm install regdesk deploy/charts/regdesk -n regdesk --create-namespace
```

**On Azure (AKS)**, provisioned by Terraform in `infra/` -- see
[infra/README.md](infra/README.md) and [infra/envs/dev/README.md](infra/envs/dev/README.md)
for the full apply/destroy flow, and [deploy/argocd/README.md](deploy/argocd/README.md)
for the GitOps handoff. Short version once the cluster exists:

```bash
scripts/platform_up_azure.sh <key-vault-name>   # same platform pieces, Azure-specific Ollama taint
scripts/deploy_azure.sh                          # one-off manual deploy, or:
kubectl apply -f deploy/argocd/application.yaml  # hand it to Argo CD instead (recommended)
```

From there, `main` is the only way anything reaches the cluster: every merge
runs through [.github/workflows/deploy.yml](.github/workflows/deploy.yml)
(build, Trivy scan, push to ACR tagged with the git SHA, commit that tag into
`deploy/charts/regdesk/values-dev.yaml`), and Argo CD syncs the result --
including reverting any manual `kubectl` change back to what's in Git
(`selfHeal: true`).

## Repo layout

```
regdesk/
  services/
    agent-api/      FastAPI + LangGraph agent: POST /ask, GET /healthz, GET /readyz
    mcp-tools/       MCP server: search_regulation, get_article
    ingest-worker/   consumes RabbitMQ, chunks, embeds, writes to Qdrant
  infra/             Terraform for Azure (Phase 3)
    bootstrap/         resource group + storage account for remote state, applied once by hand
    modules/           aks, acr, keyvault, github-oidc -- reusable building blocks
    envs/dev/          the dev environment: wires the modules together
  deploy/            Everything that reaches a cluster (Phase 2 onward)
    charts/regdesk/    the Helm chart: all 3 services, HPA, KEDA, NetworkPolicies
    platform/          Qdrant/RabbitMQ/Ollama -- upstream pieces the chart depends on
    argocd/            the Argo CD Application GitOps syncs from (Phase 4)
  .github/workflows/ CI/CD (Phase 4): PR checks (ruff, pytest, terraform fmt/tflint/checkov),
                      and on merge to main: build, Trivy scan, push to ACR, commit the new
                      tag into deploy/charts/regdesk/values-dev.yaml
  docs/
    architecture.md  full design, current + target state
    slo.md           SLOs and alerting (Phase 5)
    runbook.md        rollback / scaling / credential rotation (Phase 7)
    security.md       OWASP LLM Top 10 control mapping (Phase 6)
    incidents/         chaos-drill postmortems (Phase 7)
  data/regulations/  sample regulation corpus + source citations
  scripts/            kind_up.sh, platform_up.sh / platform_up_azure.sh,
                      kind_load_images.sh / deploy_azure.sh, ingest_corpus.py
  docker-compose.yml  full local stack, no cloud needed
  Makefile            make up / make test / make ingest / make ask
```

## Testing

```bash
make test                 # unit tests for all three services (no live stack needed)
pytest tests/integration  # end-to-end: requires `make up && make pull-models && make ingest` first
```

Each service's test suite runs independently against fakes/mocks for its
downstream dependencies (Qdrant, Ollama, RabbitMQ) -- no Docker required.
`agent-api` additionally carries three OWASP LLM01 prompt-injection
regression tests in
[services/agent-api/tests/test_prompt_injection.py](services/agent-api/tests/test_prompt_injection.py).

## Decisions

- **Azure AKS first** -- the target platform for Phase 3 onward; Phase 8 adds an optional EKS deployment of the identical Helm chart.
- **Ollama with small (3B) local models** -- GPU-free, keeps the cluster cheap, and local-only inference keeps all regulatory data on-cluster.
- **Qdrant hybrid search** -- dense vectors for semantic recall, BM25 sparse vectors for exact regulatory terms, fused with Reciprocal Rank Fusion.
- **RabbitMQ + KEDA** (from Phase 2) -- lighter than Kafka for this scale, and scale-to-zero on queue depth is a clean event-driven demo.
- **Citation allow-listing as the grounding + prompt-injection defence** -- see [docs/architecture.md](docs/architecture.md#why-these-choices-phase-1-scope).
- **Calico for real NetworkPolicy enforcement** (Phase 2) -- kind's default CNI accepts policy objects but never enforces them; Calico does, on both `kind` and AKS, so the same manifests work unchanged on either.
- **Workload identity everywhere, zero stored secrets** (Phase 3-4) -- `ingest-worker` reads RabbitMQ's credentials from Key Vault via its federated identity, not a mounted Secret with a password in it; GitHub Actions authenticates to Azure the same way, via OIDC federation, not a stored client secret.
- **Git as the only path to the cluster** (Phase 4) -- Argo CD's automated sync + `selfHeal` means a manual `kubectl` change gets reverted automatically; the only way to change what's running is a merge to `main`.

## Build phases

1. **Three services running locally** -- done.
2. **Kubernetes on a local `kind` cluster** -- done: Calico-enforced NetworkPolicies, HPA, KEDA autoscaling, PodDisruptionBudgets, pod security hardening.
3. **Azure infrastructure in Terraform** -- done: AKS (workload identity, a dedicated tainted node pool for Ollama), ACR, Key Vault, applied and destroyed cleanly against a live subscription.
4. **CI/CD and GitOps (GitHub Actions + Argo CD)** -- done: PR checks, build/scan/push/GitOps-commit on merge, Argo CD sync + self-heal, validated live end to end (a one-line change merged to `main` reaches AKS with no `kubectl`).
5. Observability and SLOs (OpenTelemetry, Prometheus, Grafana).
6. Security and identity (Entra ID OAuth/OIDC, Gateway API, Key Vault).
7. Chaos drills, postmortem, runbook.
8. Optional: the same Helm chart on AWS EKS.

## Corpus

`data/regulations/` ships a small, clearly-labelled sample corpus so the
full pipeline runs end to end without downloading anything. See
[data/README.md](data/README.md) for how to swap in the full official texts.
