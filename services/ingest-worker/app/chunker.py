"""Splits a regulation text file into article-scoped chunks.

Expects the `ARTICLE <id>: <title>` header format used under
data/regulations/. Long articles are further split on paragraph boundaries
so no single chunk grows unboundedly, which keeps embeddings focused and
each citation pointing at a specific, readable passage.
"""
import re
from dataclasses import dataclass

_ARTICLE_HEADER = re.compile(r"^ARTICLE\s+(?P<id>\S+):\s*(?P<title>.+)$", re.MULTILINE)


@dataclass(frozen=True)
class Chunk:
    article: str
    article_title: str
    chunk_index: int
    text: str


def chunk_document(raw_text: str, max_chars: int = 800) -> list[Chunk]:
    """Parse ARTICLE-delimited text into a flat, ordered list of chunks."""
    headers = list(_ARTICLE_HEADER.finditer(raw_text))
    chunks: list[Chunk] = []

    for position, match in enumerate(headers):
        article_id = match.group("id")
        article_title = match.group("title").strip()
        body_start = match.end()
        body_end = headers[position + 1].start() if position + 1 < len(headers) else len(raw_text)
        body = raw_text[body_start:body_end].strip()

        for chunk_index, piece in enumerate(_split_on_paragraphs(body, max_chars)):
            chunks.append(
                Chunk(article=article_id, article_title=article_title, chunk_index=chunk_index, text=piece)
            )

    return chunks


def _split_on_paragraphs(body: str, max_chars: int) -> list[str]:
    """Greedily pack whole paragraphs into chunks up to max_chars.

    A single paragraph longer than max_chars is kept intact rather than
    cut mid-sentence -- oversized but coherent beats undersized and broken.
    """
    paragraphs = [p.strip() for p in body.split("\n\n") if p.strip()]
    pieces: list[str] = []
    current = ""

    for paragraph in paragraphs:
        candidate = f"{current}\n\n{paragraph}".strip() if current else paragraph
        if len(candidate) > max_chars and current:
            pieces.append(current)
            current = paragraph
        else:
            current = candidate

    if current:
        pieces.append(current)

    return pieces or [body]
