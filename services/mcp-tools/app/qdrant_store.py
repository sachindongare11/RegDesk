"""Read-only Qdrant access for the two MCP tools.

Collection creation and writes are owned by ingest-worker; this module only
queries, so a misbehaving mcp-tools deployment can never corrupt the index.
"""
from qdrant_client import AsyncQdrantClient
from qdrant_client.models import (
    FieldCondition,
    Filter,
    FusionQuery,
    Fusion,
    MatchValue,
    Prefetch,
)

from app.config import settings
from app.embeddings import embed_dense, embed_sparse
from app.schemas import Article, SearchHit

# Over-fetch each leg of the hybrid query before fusion, so RRF has enough
# candidates to re-rank even if one of the two signals is weak for a given
# query (e.g. a query with no exact keyword overlap relies on dense recall).
_PREFETCH_MULTIPLIER = 4


class QdrantStore:
    def __init__(self) -> None:
        self._client = AsyncQdrantClient(url=settings.qdrant_url)

    async def close(self) -> None:
        await self._client.close()

    async def hybrid_search(self, query: str, top_k: int) -> list[SearchHit]:
        """Fuse dense (semantic) and sparse (BM25) search with RRF."""
        dense_vector = await embed_dense(query)
        sparse_vector = embed_sparse(query)
        prefetch_limit = top_k * _PREFETCH_MULTIPLIER

        result = await self._client.query_points(
            collection_name=settings.qdrant_collection,
            prefetch=[
                Prefetch(query=dense_vector, using="dense", limit=prefetch_limit),
                Prefetch(query=sparse_vector, using="bm25", limit=prefetch_limit),
            ],
            query=FusionQuery(fusion=Fusion.RRF),
            limit=top_k,
            with_payload=True,
        )

        return [
            SearchHit(
                doc_id=point.payload["doc_id"],
                doc_title=point.payload["doc_title"],
                article=point.payload["article"],
                text=point.payload["text"],
                source_url=point.payload["source_url"],
                score=point.score,
            )
            for point in result.points
        ]

    async def get_article(self, doc_id: str, article: str) -> Article | None:
        """Reconstruct one article by joining its chunks back together in order."""
        points, _next_offset = await self._client.scroll(
            collection_name=settings.qdrant_collection,
            scroll_filter=Filter(
                must=[
                    FieldCondition(key="doc_id", match=MatchValue(value=doc_id)),
                    FieldCondition(key="article", match=MatchValue(value=article)),
                ]
            ),
            with_payload=True,
            limit=1000,
        )
        if not points:
            return None

        ordered = sorted(points, key=lambda p: p.payload["chunk_index"])
        first = ordered[0].payload
        return Article(
            doc_id=first["doc_id"],
            doc_title=first["doc_title"],
            article=first["article"],
            source_url=first["source_url"],
            text="\n\n".join(p.payload["text"] for p in ordered),
        )
