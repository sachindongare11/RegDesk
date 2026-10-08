"""Owns the Qdrant collection: schema creation and idempotent upserts.

ingest-worker is the only service that writes to Qdrant, so collection
creation lives here rather than in mcp-tools (which only reads).
"""
from qdrant_client import AsyncQdrantClient
from qdrant_client.models import Distance, PointStruct, SparseVectorParams, VectorParams

from app.config import settings


class QdrantWriter:
    def __init__(self) -> None:
        self._client = AsyncQdrantClient(url=settings.qdrant_url)

    async def close(self) -> None:
        await self._client.close()

    async def ensure_collection(self) -> None:
        """Create the collection with named dense + sparse vectors if it
        doesn't already exist. Safe to call on every worker startup."""
        if await self._client.collection_exists(settings.qdrant_collection):
            return

        await self._client.create_collection(
            collection_name=settings.qdrant_collection,
            vectors_config={
                "dense": VectorParams(size=settings.dense_vector_size, distance=Distance.COSINE),
            },
            sparse_vectors_config={
                "bm25": SparseVectorParams(),
            },
        )

    async def chunk_exists(self, point_id: str) -> bool:
        points = await self._client.retrieve(collection_name=settings.qdrant_collection, ids=[point_id])
        return len(points) > 0

    async def upsert_chunk(self, point_id: str, dense_vector: list[float], sparse_vector, payload: dict) -> None:
        await self._client.upsert(
            collection_name=settings.qdrant_collection,
            points=[
                PointStruct(
                    id=point_id,
                    vector={"dense": dense_vector, "bm25": sparse_vector},
                    payload=payload,
                )
            ],
        )
