"""ingest-worker entrypoint.

Consumes doc_id messages from RabbitMQ, loads the matching text file and
its citation metadata from the corpus, chunks it by article, embeds each
new chunk (skipping ones already stored -- see app.idempotency), and
upserts into Qdrant.
"""
import asyncio
import json
import logging
from pathlib import Path

from app.chunker import chunk_document
from app.config import settings
from app.embedder import embed_dense, embed_sparse
from app.idempotency import chunk_id
from app.qdrant_writer import QdrantWriter
from app.rabbitmq_client import IngestQueueConsumer

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("ingest-worker")


def load_sources(corpus_dir: str) -> dict[str, dict]:
    """Read sources.json into a doc_id -> {title, source_url, file} map."""
    sources_path = Path(corpus_dir) / "sources.json"
    raw = json.loads(sources_path.read_text(encoding="utf-8"))
    return {doc["doc_id"]: doc for doc in raw["documents"]}


async def ingest_document(doc_id: str, writer: QdrantWriter, sources: dict[str, dict]) -> None:
    source = sources.get(doc_id)
    if source is None:
        logger.error("Unknown doc_id '%s': not present in sources.json, skipping", doc_id)
        return

    file_path = Path(settings.corpus_dir) / source["file"]
    raw_text = file_path.read_text(encoding="utf-8")
    chunks = chunk_document(raw_text, max_chars=settings.max_chunk_chars)
    logger.info("Ingesting '%s': %d chunks found", doc_id, len(chunks))

    written, skipped = 0, 0
    for chunk in chunks:
        point_id = chunk_id(doc_id, chunk.article, chunk.chunk_index, chunk.text)

        if await writer.chunk_exists(point_id):
            skipped += 1
            continue

        dense_vector = await embed_dense(chunk.text)
        sparse_vector = embed_sparse(chunk.text)
        payload = {
            "doc_id": doc_id,
            "doc_title": source["title"],
            "article": chunk.article,
            "chunk_index": chunk.chunk_index,
            "text": chunk.text,
            "source_url": source["source_url"],
        }
        await writer.upsert_chunk(point_id, dense_vector, sparse_vector, payload)
        written += 1

    logger.info("Finished '%s': %d written, %d already present (skipped)", doc_id, written, skipped)


async def run() -> None:
    writer = QdrantWriter()
    await writer.ensure_collection()
    sources = load_sources(settings.corpus_dir)

    consumer = IngestQueueConsumer()
    await consumer.connect()
    logger.info(
        "ingest-worker ready: queue='%s', collection='%s', %d known documents",
        settings.queue_name,
        settings.qdrant_collection,
        len(sources),
    )

    async def handler(doc_id: str) -> None:
        await ingest_document(doc_id, writer, sources)

    await consumer.consume(handler)
    await asyncio.Event().wait()  # consume() just registers a callback; block here forever


if __name__ == "__main__":
    asyncio.run(run())
