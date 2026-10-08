"""Runtime configuration for agent-api, loaded from environment variables."""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="AGENT_API_", env_file=".env", extra="ignore")

    # Network
    host: str = "0.0.0.0"
    port: int = 8080

    # Downstream services
    mcp_tools_url: str = "http://localhost:8000/mcp"
    ollama_base_url: str = "http://localhost:11434"
    ollama_model: str = "qwen2.5:3b"

    # Request defaults / limits
    default_top_k: int = 5
    max_question_length: int = 2000


settings = Settings()
