"""Thin async client for calling mcp-tools over streamable-HTTP MCP.

Opens one MCP session per call. That's extra round-trip overhead compared
to a pooled/persistent session, but it keeps this client stateless and
simple to reason about -- worth revisiting only if request volume makes
session setup a measured bottleneck.
"""
import json
from typing import Any

from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client


class McpToolClient:
    def __init__(self, base_url: str) -> None:
        self._base_url = base_url

    async def _call_tool(self, name: str, arguments: dict[str, Any]) -> Any:
        async with (
            streamable_http_client(self._base_url) as (read, write),
            ClientSession(read, write) as session,
        ):
            await session.initialize()
            result = await session.call_tool(name, arguments)

        if result.is_error:
            [text_block] = [c for c in result.content if c.type == "text"]
            raise RuntimeError(f"mcp-tools error calling '{name}': {text_block.text}")

        if result.structured_content is not None:
            # List-returning tools get wrapped as {"result": [...]} by the
            # MCP structured-output envelope; dict-returning tools don't get
            # structured_content populated at all (no declared output schema),
            # so we fall back to parsing the JSON text block for those.
            return result.structured_content.get("result", result.structured_content)

        [text_block] = [c for c in result.content if c.type == "text"]
        return json.loads(text_block.text)

    async def search_regulation(self, query: str, top_k: int) -> list[dict]:
        return await self._call_tool("search_regulation", {"query": query, "top_k": top_k})

    async def get_article(self, doc_id: str, article: str) -> dict:
        return await self._call_tool("get_article", {"doc_id": doc_id, "article": article})
