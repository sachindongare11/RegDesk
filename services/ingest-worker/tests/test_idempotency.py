import uuid

from app.idempotency import chunk_id


def test_chunk_id_is_deterministic():
    a = chunk_id("dora", "19", 0, "some text")
    b = chunk_id("dora", "19", 0, "some text")
    assert a == b


def test_chunk_id_differs_when_any_input_changes():
    base = chunk_id("dora", "19", 0, "some text")

    assert chunk_id("eu-ai-act", "19", 0, "some text") != base
    assert chunk_id("dora", "20", 0, "some text") != base
    assert chunk_id("dora", "19", 1, "some text") != base
    assert chunk_id("dora", "19", 0, "different text") != base


def test_chunk_id_is_a_valid_uuid_accepted_by_qdrant_point_ids():
    value = chunk_id("dora", "19", 0, "some text")
    uuid.UUID(value)  # raises ValueError if not a valid UUID string
