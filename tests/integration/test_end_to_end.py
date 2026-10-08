"""End-to-end check against a running `docker compose up` stack: wait for
agent-api to be ready, then ask a question and verify a cited answer comes
back from the real pipeline (mcp-tools -> Qdrant -> Ollama).

Skipped automatically if agent-api isn't reachable, so a plain `pytest` run
from the repo root doesn't fail when the stack isn't up. Run explicitly:

    make up && make pull-models && make ingest
    pytest tests/integration
"""
import os
import time

import httpx
import pytest

AGENT_API_URL = os.environ.get("AGENT_API_URL", "http://localhost:8080")


def _agent_api_reachable() -> bool:
    try:
        return httpx.get(f"{AGENT_API_URL}/healthz", timeout=2.0).status_code == 200
    except httpx.HTTPError:
        return False


pytestmark = pytest.mark.skipif(
    not _agent_api_reachable(),
    reason="agent-api not reachable; run `make up && make pull-models && make ingest` first",
)


def _wait_until_ready(timeout_seconds: float = 60.0) -> None:
    """Poll /readyz until mcp-tools (and transitively Qdrant) answers, or give up."""
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        try:
            if httpx.get(f"{AGENT_API_URL}/readyz", timeout=2.0).status_code == 200:
                return
        except httpx.HTTPError:
            pass
        time.sleep(2.0)
    raise TimeoutError("agent-api never became ready (mcp-tools/Qdrant unreachable)")


def test_ask_returns_a_grounded_cited_answer():
    _wait_until_ready()

    response = httpx.post(
        f"{AGENT_API_URL}/ask",
        json={"question": "What does DORA require for ICT incident reporting?"},
        timeout=60.0,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["answer"]
    assert len(body["citations"]) > 0
    for citation in body["citations"]:
        assert citation["source_url"].startswith("https://")


def test_ask_rejects_malformed_request():
    response = httpx.post(f"{AGENT_API_URL}/ask", json={"question": ""}, timeout=10.0)
    assert response.status_code == 422
