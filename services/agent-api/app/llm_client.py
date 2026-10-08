"""Ollama chat client used for answer generation."""
import httpx

from app.config import settings


class OllamaClient:
    def __init__(self, base_url: str | None = None, model: str | None = None) -> None:
        self._base_url = base_url or settings.ollama_base_url
        self._model = model or settings.ollama_model

    async def generate_answer(self, system_prompt: str, user_prompt: str) -> str:
        """Single non-streaming chat completion; small models answer fast enough
        that streaming isn't needed for this project's demo scope."""
        async with httpx.AsyncClient(base_url=self._base_url, timeout=60.0) as client:
            response = await client.post(
                "/api/chat",
                json={
                    "model": self._model,
                    "messages": [
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt},
                    ],
                    "stream": False,
                },
            )
            response.raise_for_status()
            return response.json()["message"]["content"]
