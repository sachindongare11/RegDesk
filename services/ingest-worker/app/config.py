"""Runtime configuration for ingest-worker, loaded from environment variables."""
from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="INGEST_WORKER_", env_file=".env", extra="ignore")

    # RabbitMQ: set rabbitmq_url directly (docker-compose, local dev), OR set
    # rabbitmq_host/user/password and let the validator below compose the
    # URL. The split form exists for Kubernetes: the RabbitMQ Cluster
    # Operator hands out credentials as discrete Secret keys
    # (username/password), not a ready-made connection string, so the Helm
    # chart wires those keys to the _host/_user/_password env vars instead
    # of trying to template one into a single URL at the YAML layer.
    rabbitmq_url: str = "amqp://guest:guest@localhost:5672/"
    rabbitmq_host: str | None = None
    rabbitmq_port: int = 5672
    rabbitmq_user: str | None = None
    rabbitmq_password: str | None = None
    queue_name: str = "regdesk.ingest"
    prefetch_count: int = 4

    @model_validator(mode="after")
    def _compose_rabbitmq_url_from_parts(self) -> "Settings":
        if self.rabbitmq_host is not None:
            user = self.rabbitmq_user or "guest"
            password = self.rabbitmq_password or "guest"
            self.rabbitmq_url = f"amqp://{user}:{password}@{self.rabbitmq_host}:{self.rabbitmq_port}/"
        return self

    # Qdrant (dense vector size must match ollama_embed_model's output)
    qdrant_url: str = "http://localhost:6333"
    qdrant_collection: str = "regdesk_regulations"
    dense_vector_size: int = 768

    # Ollama
    ollama_base_url: str = "http://localhost:11434"
    ollama_embed_model: str = "nomic-embed-text"

    # Corpus location: sources.json plus the document text files it references
    corpus_dir: str = "/data/regulations"
    max_chunk_chars: int = 800

    # FastEmbed's BM25 model cache. Must be an explicit cache_dir (see
    # embedder.py) -- FastEmbed ignores HF_HOME and otherwise defaults to
    # tempfile.gettempdir(), which under Kubernetes is a fresh emptyDir on
    # every pod start, not the path the Dockerfile pre-baked the model into.
    fastembed_cache_dir: str = "/opt/hf-cache"


settings = Settings()
