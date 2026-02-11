# app/core/config.py
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field
from functools import lru_cache

class Settings(BaseSettings):
    # App
    app_name: str = "EchoSift API"
    environment: str = "production"

    # OpenAI
    # Use validation_alias to map the uppercase .env key to the lowercase attribute
    openai_api_key: str = Field(..., validation_alias="OPENAI_API_KEY")

    # Redis
    redis_host: str = Field(default="redis")
    redis_port: int = Field(default=6379)
    redis_db: int = Field(default=0)
    redis_session_ttl_seconds: int = Field(default=600)

    # CORS
    cors_allow_origins: list[str] = ["*"]
    cors_allow_methods: list[str] = ["*"]
    cors_allow_headers: list[str] = ["*"]

    # Pydantic V2 Configuration
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        # This is the "Magic Fix" for the errors you saw:
        extra="ignore",         # Don't crash if extra variables are in .env
        case_sensitive=False    # Map OPENAI_API_KEY to openai_api_key automatically
    )

@lru_cache
def get_settings() -> Settings:
    return Settings()