# Architecture

## Target state

Three Python services in one namespace, reached only through Git and
Argo CD once deployed to AKS:

```
                         watches Git
Terraform --provisions--> AKS cluster <--deploys-- Argo CD <--Git-- GitHub Actions
                               |                                          ^
                               v                                          |
                 +--------------------------------+                      |
                 |  Gateway -> agent-api -> mcp-tools -> Qdrant  |  builds/scans/pushes
                 |                |                               |
                 |              Ollama <---- ingest-worker <---- RabbitMQ
                 +--------------------------------+
```

A question enters through the Gateway, `agent-api` runs the LangGraph
flow, calls `mcp-tools` to search Qdrant, and asks Ollama for the answer.
New documents go onto the RabbitMQ queue, and KEDA scales `ingest-worker`
from zero to process them. Platform details (AKS, Terraform, GitOps,
observability, security) land in Phases 2-6; see the repo root README for
the phase plan.

## Phase 1 state (current)

Everything below runs with `docker compose up`, no cloud dependency:

| Service | Role | Entry point |
|---|---|---|
| `mcp-tools` | MCP server over streamable HTTP. Exposes `search_regulation` (hybrid BM25 + dense vector search in Qdrant, fused with RRF) and `get_article` (full-text lookup by doc_id + article). | [services/mcp-tools/app/server.py](../services/mcp-tools/app/server.py) |
| `agent-api` | FastAPI app exposing `POST /ask`. Runs a 3-node LangGraph flow: `retrieve` (call mcp-tools) -> `answer` (ask Ollama, grounded in retrieved passages) -> `verify` (keep only citations that match a retrieved passage). | [services/agent-api/app/graph.py](../services/agent-api/app/graph.py) |
| `ingest-worker` | Consumes `doc_id` messages from RabbitMQ, chunks the matching file by article, embeds each new chunk (dense via Ollama, sparse via FastEmbed BM25), and idempotently upserts into Qdrant. | [services/ingest-worker/app/worker.py](../services/ingest-worker/app/worker.py) |

### Data flow for one question

1. Client sends `POST /ask {"question": "..."}` to `agent-api`.
2. `retrieve` node calls `mcp-tools.search_regulation`, which embeds the
   query (dense + sparse) and runs a fused Qdrant query.
3. `answer` node builds a prompt that wraps every retrieved passage in
   `<retrieved_context>` tags (explicitly untrusted data, never
   instructions -- see the OWASP LLM01 note in
   [services/agent-api/app/graph.py](../services/agent-api/app/graph.py))
   and asks Ollama to answer with inline `[doc_id:article]` citations.
4. `verify` node strips any citation that doesn't match a passage that was
   actually retrieved, and falls back to a safe "not enough grounded
   information" message if no citation survives.

### Data flow for ingesting a document

1. `scripts/ingest_corpus.py` (or any producer) publishes a `doc_id` onto
   the `regdesk.ingest` queue.
2. `ingest-worker` looks up the `doc_id` in `data/regulations/sources.json`,
   reads the matching text file, and splits it into article-scoped chunks.
3. For each chunk, it computes a deterministic UUID from
   `(doc_id, article, chunk_index, text)`. If a point with that ID already
   exists in Qdrant, the chunk is skipped -- this is what makes ingestion
   safe to replay after a crash or a RabbitMQ redelivery.
4. New chunks are embedded (dense + sparse) and upserted with payload
   `{doc_id, doc_title, article, chunk_index, text, source_url}`.

### Why these choices (Phase 1 scope)

| Choice | Why |
|---|---|
| Ollama, 3B models | GPU-free, cheap to run locally and later on a single AKS node; answer quality isn't what this project is judged on. |
| Qdrant hybrid search | Dense vectors catch paraphrases; BM25 sparse vectors catch exact regulatory terms (e.g. "ICT-related incident"); RRF fusion combines both without hand-tuned weights. |
| Citation allow-listing in `verify_node` | Doubles as the grounding check and the primary OWASP LLM01 defence -- a model that's tricked into citing an unretrieved/attacker-chosen source can never have that citation surface to the user. |
| UUID5 chunk IDs | Makes `ingest-worker` idempotent without a separate dedup table -- the ID *is* the dedup key. |
