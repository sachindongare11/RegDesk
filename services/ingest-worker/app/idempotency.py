"""Content-hashing so re-ingesting a document never duplicates chunks.

Each chunk's Qdrant point ID is a deterministic UUID derived from
(doc_id, article, chunk_index, text). Upserting the same chunk twice
overwrites the same point instead of creating a duplicate, so replaying a
RabbitMQ message after a crash mid-ingest -- or re-running the whole
corpus -- is always safe.
"""
import uuid

# Any fixed namespace works; what matters is that it's constant across runs
# so the same (doc_id, article, chunk_index, text) always maps to the same ID.
_NAMESPACE = uuid.NAMESPACE_URL


def chunk_id(doc_id: str, article: str, chunk_index: int, text: str) -> str:
    """Return a stable UUID5 string -- Qdrant point IDs must be an int or a UUID."""
    name = f"{doc_id}:{article}:{chunk_index}:{text}"
    return str(uuid.uuid5(_NAMESPACE, name))
