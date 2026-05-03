from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import field_validator
from functools import lru_cache
from typing import Optional
from pathlib import Path

# Resolve .env relative to the project root (3 levels up from app/core/config.py)
# This works regardless of the working directory uvicorn is started from
_ENV_FILE = Path(__file__).resolve().parent.parent.parent / ".env"

class Settings(BaseSettings):
    # App Config
    APP_NAME: str = "Agentic AI Trading Backend"
    DEBUG: bool = False

    # Zerodha Kite Connect Config
    # Note: ZERODHA_API_KEY and ZERODHA_API_SECRET should come from user's own Kite Connect app
    # Users provide their credentials during app setup; these are optional for server startup
    ZERODHA_API_KEY: Optional[str] = None
    ZERODHA_API_SECRET: Optional[str] = None
    ZERODHA_ACCESS_TOKEN: Optional[str] = None # Can be set manually or via login flow (not fully implemented here)

    # OpenAI Config
    OPENAI_API_KEY: str
    OPENAI_MODEL: str = "gpt-4o"

    # Trading Config
    DEFAULT_TIMEFRAME: str = "day"
    DEFAULT_RISK_PERCENT: float = 1.0

    # Database Config
    DB_SERVER: Optional[str] = None
    DB_NAME: Optional[str] = None
    DB_USER: Optional[str] = None
    DB_PASSWORD: Optional[str] = None
    DB_DRIVER: str = "ODBC Driver 18 for SQL Server"
    DB_POOL_SIZE: int = 5
    DB_MAX_OVERFLOW: int = 10

    # Frontend URL for OAuth redirects
    FRONTEND_URL: str = "https://vantrade.in"

    @field_validator("FRONTEND_URL", mode="before")
    @classmethod
    def _nonempty_frontend_url(cls, v: str) -> str:
        return v if v else "https://vantrade.in"

    # Admin Dashboard Config
    ADMIN_JWT_SECRET: str = "your-secret-key-change-in-production"
    ADMIN_JWT_ALGORITHM: str = "HS256"
    ADMIN_JWT_EXPIRATION_MINUTES: int = 480

    # Firebase Phone Auth
    FIREBASE_PROJECT_ID: Optional[str] = None
    FIREBASE_SERVICE_ACCOUNT: Optional[str] = None  # base64-encoded service account JSON
    VT_JWT_SECRET: str = "change-me-in-production-vt-jwt-secret"
    VT_JWT_EXPIRY_HOURS: int = 720  # 30 days

    model_config = SettingsConfigDict(env_file=str(_ENV_FILE), env_file_encoding="utf-8", extra="ignore")

@lru_cache()
def get_settings():
    return Settings()
