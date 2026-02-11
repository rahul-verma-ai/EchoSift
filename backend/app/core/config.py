# backend/app/core/config.py
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field
from functools import lru_cache
from typing import Optional

class Settings(BaseSettings):
    # App
    app_name: str = "EchoSift API"
    environment: str = "production"

    # OpenAI
    openai_api_key: str = Field(..., validation_alias="OPENAI_API_KEY")

    # Redis
    # Priority is given to REDIS_URL if provided by the cloud host
    redis_url: Optional[str] = Field(default=None, validation_alias="REDIS_URL")
    redis_host: str = Field(default="localhost")
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
        extra="ignore",         
        case_sensitive=False    
    )

@lru_cache
def get_settings() -> Settings:
    return Settings()