from app.chunker import chunk_document

SAMPLE = """ARTICLE 1: First
Paragraph one.

Paragraph two.

ARTICLE 2: Second
Only paragraph.
"""


def test_chunk_document_splits_by_article():
    chunks = chunk_document(SAMPLE, max_chars=1000)

    assert [c.article for c in chunks] == ["1", "2"]
    assert chunks[0].article_title == "First"
    assert "Paragraph one." in chunks[0].text
    assert "Paragraph two." in chunks[0].text
    assert chunks[1].article_title == "Second"


def test_chunk_document_assigns_sequential_chunk_index_per_article():
    long_body = "\n\n".join(f"Paragraph {i} " + "x" * 50 for i in range(10))
    text = f"ARTICLE 9: Long\n{long_body}\n"

    chunks = chunk_document(text, max_chars=200)

    assert len(chunks) > 1
    assert all(c.article == "9" for c in chunks)
    assert [c.chunk_index for c in chunks] == list(range(len(chunks)))

    reconstructed = "\n\n".join(c.text for c in chunks)
    for i in range(10):
        assert f"Paragraph {i} " in reconstructed


def test_chunk_document_keeps_an_oversized_single_paragraph_intact():
    text = "ARTICLE 1: Big\n" + ("x" * 500) + "\n"

    chunks = chunk_document(text, max_chars=100)

    assert len(chunks) == 1
    assert len(chunks[0].text) == 500


def test_chunk_document_returns_empty_list_for_text_with_no_articles():
    assert chunk_document("no article headers here", max_chars=800) == []
