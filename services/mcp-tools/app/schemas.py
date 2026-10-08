"""Response shapes returned by the MCP tools.

Keeping these as plain pydantic models (rather than returning raw Qdrant
payloads) means the wire format is explicit and stays stable even if the
underlying point payload schema changes.
"""
from pydantic import BaseModel, Field


class SearchHit(BaseModel):
    doc_id: str = Field(description="Identifier of the source regulation, e.g. 'dora'")
    doc_title: str = Field(description="Human-readable title of the source regulation")
    article: str = Field(description="Article or section identifier within the document")
    text: str = Field(description="The chunk text that matched the query")
    source_url: str = Field(description="Canonical public URL to cite")
    score: float = Field(description="Fused relevance score (higher is more relevant)")


class Article(BaseModel):
    doc_id: str
    doc_title: str
    article: str
    text: str = Field(description="Full reconstructed text of the article, chunks joined in order")
    source_url: str
