"""MCP tool server for RegDesk.

Exposes two tools over streamable HTTP for agent-api's LangGraph agent:
  - search_regulation: hybrid BM25 + vector search across the ingested corpus
  - get_article: fetch one article's full text by doc_id + article id

Run directly with `python -m app.server`, or via the Dockerfile's uvicorn
entrypoint for production.
"""
import logging

from mcp.server.mcpserver import MCPServer
from starlette.requests import Request
from starlette.responses import JSONResponse

from app.config import settings
from app.qdrant_store import QdrantStore
from app import tools

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("mcp-tools")

mcp = MCPServer(name="regdesk-mcp-tools")
store = QdrantStore()


@mcp.tool()
async def search_regulation(query: str, top_k: int = settings.default_top_k) -> list[dict]:
    """Search the ingested regulation corpus for passages relevant to a query.

    Combines dense vector similarity with BM25 keyword matching (hybrid
    search, fused with Reciprocal Rank Fusion), so both paraphrased and
    exact-term queries retrieve well.

    Args:
        query: Natural-language question or keyword query.
        top_k: Number of passages to return (capped at MCP_TOOLS_MAX_TOP_K).

    Returns:
        A list of hits, each with doc_id, doc_title, article, text,
        source_url and a relevance score, ordered most relevant first.
    """
    return await tools.search_regulation(store, query, top_k, settings.max_top_k)


@mcp.tool()
async def get_article(doc_id: str, article: str) -> dict:
    """Fetch the full text of one specific article from the corpus.

    Use this after search_regulation to pull complete context for a
    citation the search only returned a partial chunk for.

    Args:
        doc_id: Document identifier, e.g. 'dora', 'eu-ai-act', 'cbi-cpc'.
        article: Article or section identifier within that document.

    Returns:
        The article's doc_id, doc_title, article, full text and source_url.

    Raises:
        ValueError: If no article matches doc_id + article.
    """
    return await tools.get_article(store, doc_id, article)


@mcp.custom_route("/healthz", methods=["GET"])
async def healthz(_request: Request) -> JSONResponse:
    """Liveness probe: process is up and serving requests."""
    return JSONResponse({"status": "ok"})


if __name__ == "__main__":
    logger.info(
        "Starting mcp-tools on %s:%s, collection=%s",
        settings.host,
        settings.port,
        settings.qdrant_collection,
    )
    mcp.run(transport="streamable-http", host=settings.host, port=settings.port)
