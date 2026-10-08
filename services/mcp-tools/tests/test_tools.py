"""Unit tests for tool logic, with QdrantStore mocked out.

No live Qdrant or Ollama needed: these exercise the capping, serialisation
and not-found behaviour that sits in front of the store.
"""
import pytest

from app import tools
from app.schemas import Article, SearchHit


class FakeStore:
    """Minimal stand-in for QdrantStore, records call args for assertions."""

    def __init__(self, search_results=None, article=None):
        self._search_results = search_results or []
        self._article = article
        self.last_search_top_k = None

    async def hybrid_search(self, query: str, top_k: int):
        self.last_search_top_k = top_k
        return self._search_results

    async def get_article(self, doc_id: str, article: str):
        return self._article


@pytest.mark.asyncio
async def test_search_regulation_caps_top_k_and_serialises_hits():
    hit = SearchHit(
        doc_id="dora",
        doc_title="DORA",
        article="19",
        text="Reporting of major ICT-related incidents...",
        source_url="https://eur-lex.europa.eu/eli/reg/2022/2554/oj",
        score=0.87,
    )
    store = FakeStore(search_results=[hit])

    results = await tools.search_regulation(store, query="ICT incident reporting", top_k=50, max_top_k=5)

    assert store.last_search_top_k == 5  # requested 50 but capped at max_top_k
    assert results == [hit.model_dump()]


@pytest.mark.asyncio
async def test_search_regulation_respects_top_k_under_the_cap():
    store = FakeStore(search_results=[])

    await tools.search_regulation(store, query="anything", top_k=2, max_top_k=5)

    assert store.last_search_top_k == 2


@pytest.mark.asyncio
async def test_get_article_returns_serialised_article_when_found():
    article = Article(
        doc_id="eu-ai-act",
        doc_title="EU AI Act",
        article="9",
        text="Providers of high-risk AI systems shall establish...",
        source_url="https://eur-lex.europa.eu/eli/reg/2024/1689/oj",
    )
    store = FakeStore(article=article)

    result = await tools.get_article(store, doc_id="eu-ai-act", article="9")

    assert result == article.model_dump()


@pytest.mark.asyncio
async def test_get_article_raises_value_error_when_not_found():
    store = FakeStore(article=None)

    with pytest.raises(ValueError, match="No article 'missing' found in document 'dora'"):
        await tools.get_article(store, doc_id="dora", article="missing")
