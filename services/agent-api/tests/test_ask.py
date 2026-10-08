"""/ask endpoint tests with the compiled graph swapped for a fake.

A live Ollama + mcp-tools stack isn't needed here: app.main.graph is a
module-level object, so monkeypatching it is enough to test request
validation and response shaping in isolation.
"""
from fastapi.testclient import TestClient

from app import main


class FakeGraph:
    def __init__(self, result: dict):
        self._result = result

    async def ainvoke(self, _state: dict) -> dict:
        return self._result


def test_ask_returns_answer_and_citations(monkeypatch):
    fake_result = {
        "answer": "DORA requires initial notification within 4 hours of classification [dora:19].",
        "citations": [
            {"doc_id": "dora", "article": "19", "source_url": "https://eur-lex.europa.eu/eli/reg/2022/2554/oj"}
        ],
        "verifier_rejected_count": 0,
    }
    monkeypatch.setattr(main, "graph", FakeGraph(fake_result))
    client = TestClient(main.app)

    response = client.post("/ask", json={"question": "What does DORA require for ICT incident reporting?"})

    assert response.status_code == 200
    body = response.json()
    assert body["answer"] == fake_result["answer"]
    assert body["citations"] == fake_result["citations"]
    assert body["verifier_rejected_count"] == 0


def test_ask_rejects_empty_question():
    client = TestClient(main.app)

    response = client.post("/ask", json={"question": ""})

    assert response.status_code == 422


def test_ask_rejects_top_k_out_of_range():
    client = TestClient(main.app)

    response = client.post("/ask", json={"question": "valid question", "top_k": 100})

    assert response.status_code == 422
