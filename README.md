# RegDesk

A regulatory Q&A agent for Irish financial services -- ask things like *"What
does DORA require for ICT incident reporting?"* and get a cited answer drawn
from DORA, the EU AI Act, and the Central Bank of Ireland Consumer
Protection Code. Target deployment is Azure Kubernetes Service, provisioned
with Terraform, delivered with Helm + Argo CD, and fully observable
(OpenTelemetry, Prometheus, Grafana). See [docs/architecture.md](docs/architecture.md)
for the full design and the "Decisions" table below for the short version.

**Status: Phase 1 complete.** The three services run locally via Docker
Compose with no cloud dependency. Phases 2-8 (Kubernetes, Terraform, GitOps,
observability, security, chaos drills, optional AWS) are tracked in the
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

## Repo layout

```
regdesk/
  services/
    agent-api/      FastAPI + LangGraph agent: POST /ask, GET /healthz, GET /readyz
    mcp-tools/       MCP server: search_regulation, get_article
    ingest-worker/   consumes RabbitMQ, chunks, embeds, writes to Qdrant
  infra/             Terraform for AKS/ACR/Key Vault (Phase 3)
  deploy/            Helm chart + Argo CD Applications (Phase 2 onward)
  .github/workflows/ CI: test, lint, scan, build, push, bump image tag (Phase 4)
  docs/
    architecture.md  full design, current + target state
    slo.md           SLOs and alerting (Phase 5)
    runbook.md        rollback / scaling / credential rotation (Phase 7)
    security.md       OWASP LLM Top 10 control mapping (Phase 6)
    incidents/         chaos-drill postmortems (Phase 7)
  data/regulations/  sample regulation corpus + source citations
  scripts/            ingest_corpus.py: publish doc_ids onto the queue
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

## Build phases

1. **Three services running locally** -- done (this state).
2. Kubernetes on a local `kind` cluster.
3. Azure infrastructure in Terraform.
4. CI/CD and GitOps (GitHub Actions + Argo CD).
5. Observability and SLOs (OpenTelemetry, Prometheus, Grafana).
6. Security and identity (Entra ID OAuth/OIDC, Gateway API, Key Vault).
7. Chaos drills, postmortem, runbook.
8. Optional: the same Helm chart on AWS EKS.

## Corpus

`data/regulations/` ships a small, clearly-labelled sample corpus so the
full pipeline runs end to end without downloading anything. See
[data/README.md](data/README.md) for how to swap in the full official texts.
