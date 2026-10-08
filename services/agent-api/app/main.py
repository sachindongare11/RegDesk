"""FastAPI entrypoint for agent-api: POST /ask, GET /healthz, GET /readyz."""
import logging

from fastapi import FastAPI, HTTPException

from app.config import settings
from app.graph import build_graph
from app.llm_client import OllamaClient
from app.mcp_client import McpToolClient
from app.schemas import AskRequest, AskResponse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("agent-api")

app = FastAPI(title="RegDesk agent-api")

mcp_client = McpToolClient(settings.mcp_tools_url)
llm_client = OllamaClient()
graph = build_graph(mcp_client, llm_client)


@app.get("/healthz")
async def healthz() -> dict:
    """Liveness probe: the process is up and the event loop is responsive."""
    return {"status": "ok"}


@app.get("/readyz")
async def readyz() -> dict:
    """Readiness probe: mcp-tools (and transitively Qdrant) must be reachable."""
    try:
        await mcp_client.search_regulation("readiness check", top_k=1)
    except Exception as exc:  # noqa: BLE001 - readiness must surface any downstream failure
        logger.warning("Readiness check failed: %s", exc)
        raise HTTPException(status_code=503, detail="mcp-tools unavailable") from exc
    return {"status": "ready"}


@app.post("/ask", response_model=AskResponse)
async def ask(request: AskRequest) -> AskResponse:
    result = await graph.ainvoke(
        {
            "question": request.question,
            "top_k": request.top_k,
            "retrieved": [],
            "draft_answer": "",
            "answer": "",
            "citations": [],
            "verifier_rejected_count": 0,
        }
    )
    return AskResponse(
        answer=result["answer"],
        citations=result["citations"],
        verifier_rejected_count=result["verifier_rejected_count"],
    )
