"""Query-time embedding generation for hybrid search.

Dense vectors come from Ollama (must use the same model the ingest-worker
used to embed chunks, or the vector space won't line up). Sparse vectors
come from FastEmbed's BM25 implementation, which needs no GPU and no
network access once its tiny term-weighting model is cached locally.
"""
import httpx
from fastembed import SparseTextEmbedding
from qdrant_client.models import SparseVector

from app.config import settings

# Built lazily (not at import time) so importing this module -- e.g. in unit
# tests that never call embed_sparse -- never triggers FastEmbed's model
# download. Once built, the instance is reused across requests.
_sparse_model: SparseTextEmbedding | None = None


def _get_sparse_model() -> SparseTextEmbedding:
    global _sparse_model
    if _sparse_model is None:
        _sparse_model = SparseTextEmbedding(model_name="Qdrant/bm25")
    return _sparse_model


async def embed_dense(text: str) -> list[float]:
    """Call Ollama's embeddings endpoint for a single dense query vector."""
    async with httpx.AsyncClient(base_url=settings.ollama_base_url, timeout=30.0) as client:
        response = await client.post(
            "/api/embeddings",
            json={"model": settings.ollama_embed_model, "prompt": text},
        )
        response.raise_for_status()
        embedding = response.json()["embedding"]

    if len(embedding) != settings.dense_vector_size:
        raise ValueError(
            f"Ollama returned a {len(embedding)}-dim embedding, expected "
            f"{settings.dense_vector_size}. Check MCP_TOOLS_DENSE_VECTOR_SIZE "
            f"matches MCP_TOOLS_OLLAMA_EMBED_MODEL."
        )
    return embedding


def embed_sparse(text: str) -> SparseVector:
    """Build a BM25-weighted sparse vector for a single query string."""
    [sparse_embedding] = list(_get_sparse_model().embed([text]))
    return SparseVector(
        indices=sparse_embedding.indices.tolist(),
        values=sparse_embedding.values.tolist(),
    )
