# Regulation corpus

`regulations/` holds the documents RegDesk ingests and cites. Each document is
plain text with `ARTICLE <id>: <title>` headers so the ingest worker can chunk
by article and `mcp-tools.get_article` can fetch one article directly.
`sources.json` maps each `doc_id` to the canonical public URL cited in answers.

## Current state

The three `*_excerpt.txt` files are short, illustrative samples (a handful of
articles each) so the full pipeline -- ingest, embed, hybrid search, cite --
runs end to end on a laptop with no downloads. They are **not** the official
legal text.

## Building the real corpus (20-30 documents)

Before using RegDesk for anything beyond local development, replace the
excerpt files with the full official texts:

1. Digital Operational Resilience Act (DORA) -- consolidated text at the
   `source_url` in `sources.json` for `doc_id: dora`.
2. EU AI Act -- consolidated text at the `source_url` for `doc_id: eu-ai-act`.
3. Central Bank of Ireland Consumer Protection Code -- current edition at the
   `source_url` for `doc_id: cbi-cpc`.

For each document: download the PDF, convert to plain text preserving article
headers in the `ARTICLE <id>: <title>` format used here (or extend
`services/ingest-worker/app/chunker.py` to parse the source's native
structure), add an entry to `sources.json`, and drop the file in this
directory. Then run `make ingest` to publish it onto the RabbitMQ queue.
