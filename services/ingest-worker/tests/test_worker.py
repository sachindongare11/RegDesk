"""ingest_document() orchestration tests, with QdrantWriter and the
embedding functions faked out so no live Qdrant/Ollama is needed."""
import json
from pathlib import Path

import pytest

from app import worker


class FakeWriter:
    def __init__(self):
        self.stored: dict[str, dict] = {}

    async def chunk_exists(self, point_id: str) -> bool:
        return point_id in self.stored

    async def upsert_chunk(self, point_id, dense_vector, sparse_vector, payload):
        self.stored[point_id] = payload


@pytest.fixture
def corpus_dir(tmp_path: Path, monkeypatch) -> Path:
    (tmp_path / "dora.txt").write_text(
        "ARTICLE 19: Reporting\nReport major incidents within 4 hours.\n",
        encoding="utf-8",
    )
    sources = {
        "documents": [
            {
                "doc_id": "dora",
                "title": "DORA",
                "source_url": "https://eur-lex.europa.eu/eli/reg/2022/2554/oj",
                "file": "dora.txt",
            }
        ]
    }
    (tmp_path / "sources.json").write_text(json.dumps(sources), encoding="utf-8")
    monkeypatch.setattr(worker.settings, "corpus_dir", str(tmp_path))
    return tmp_path


async def _fake_embed_dense(_text: str) -> list[float]:
    return [0.1, 0.2, 0.3]


def _fake_embed_sparse(_text: str):
    return {"indices": [1], "values": [1.0]}


async def test_ingest_document_writes_new_chunks(corpus_dir, monkeypatch):
    monkeypatch.setattr(worker, "embed_dense", _fake_embed_dense)
    monkeypatch.setattr(worker, "embed_sparse", _fake_embed_sparse)
    writer = FakeWriter()
    sources = worker.load_sources(str(corpus_dir))

    await worker.ingest_document("dora", writer, sources)

    assert len(writer.stored) == 1
    [payload] = writer.stored.values()
    assert payload["doc_id"] == "dora"
    assert payload["article"] == "19"
    assert payload["source_url"] == "https://eur-lex.europa.eu/eli/reg/2022/2554/oj"


async def test_ingest_document_is_idempotent_on_second_run(corpus_dir, monkeypatch):
    monkeypatch.setattr(worker, "embed_dense", _fake_embed_dense)
    monkeypatch.setattr(worker, "embed_sparse", _fake_embed_sparse)
    writer = FakeWriter()
    sources = worker.load_sources(str(corpus_dir))

    await worker.ingest_document("dora", writer, sources)
    await worker.ingest_document("dora", writer, sources)  # simulate RabbitMQ redelivery

    assert len(writer.stored) == 1  # no duplicate chunk was written


async def test_ingest_document_skips_unknown_doc_id(corpus_dir, caplog):
    writer = FakeWriter()
    sources = worker.load_sources(str(corpus_dir))

    await worker.ingest_document("not-a-real-doc", writer, sources)

    assert writer.stored == {}
