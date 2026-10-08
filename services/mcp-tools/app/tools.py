"""Tool implementations, kept separate from app.server's MCP wiring.

Plain async functions over a QdrantStore are easier to unit test than
functions wrapped by the @mcp.tool() decorator, whose call semantics are
owned by the MCP SDK rather than us.
"""
from app.qdrant_store import QdrantStore
from app.schemas import Article, SearchHit


async def search_regulation(store: QdrantStore, query: str, top_k: int, max_top_k: int) -> list[dict]:
    """Hybrid-search the corpus and return JSON-serialisable hits."""
    capped_top_k = min(top_k, max_top_k)
    hits: list[SearchHit] = await store.hybrid_search(query, capped_top_k)
    return [hit.model_dump() for hit in hits]


async def get_article(store: QdrantStore, doc_id: str, article: str) -> dict:
    """Fetch one article's full text, raising ValueError if it doesn't exist."""
    result: Article | None = await store.get_article(doc_id, article)
    if result is None:
        raise ValueError(f"No article '{article}' found in document '{doc_id}'")
    return result.model_dump()
