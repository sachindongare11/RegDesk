"""Runtime configuration for mcp-tools, loaded from environment variables."""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="MCP_TOOLS_", env_file=".env", extra="ignore")

    # Network
    host: str = "0.0.0.0"
    port: int = 8000

    # Qdrant
    qdrant_url: str = "http://localhost:6333"
    qdrant_collection: str = "regdesk_regulations"

    # Ollama (dense embeddings must match the model used by ingest-worker)
    ollama_base_url: str = "http://localhost:11434"
    ollama_embed_model: str = "nomic-embed-text"
    dense_vector_size: int = 768

    # Search
    default_top_k: int = 5
    max_top_k: int = 20

    # FastEmbed's BM25 model cache. Must be an explicit cache_dir (see
    # embeddings.py) -- FastEmbed ignores HF_HOME and otherwise defaults to
    # tempfile.gettempdir(), which under Kubernetes is a fresh emptyDir on
    # every pod start, not the path the Dockerfile pre-baked the model into.
    fastembed_cache_dir: str = "/opt/hf-cache"


settings = Settings()
