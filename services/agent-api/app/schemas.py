"""Request/response shapes for the public /ask API."""
from pydantic import BaseModel, Field

from app.config import settings


class AskRequest(BaseModel):
    question: str = Field(min_length=1, max_length=settings.max_question_length)
    top_k: int = Field(default=settings.default_top_k, ge=1, le=20)


class Citation(BaseModel):
    doc_id: str
    article: str
    source_url: str


class AskResponse(BaseModel):
    answer: str
    citations: list[Citation]
    verifier_rejected_count: int = Field(
        description="Citations the model produced that didn't match any retrieved "
        "passage and were stripped before returning the answer."
    )
