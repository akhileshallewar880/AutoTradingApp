from pydantic_settings import BaseSettings, SettingsConfigDict
from functools import lru_cache
from typing import Optional

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
    DB_SERVER: str = "localhost"
    DB_USER: str = "sa"
    DB_PASSWORD: str
    DB_NAME: str = "VanTradeDB"
    DB_DRIVER: str = "ODBC Driver 17 for SQL Server"
    DB_POOL_SIZE: int = 20
    DB_MAX_OVERFLOW: int = 10
    ENCRYPTION_KEY: str  # Fernet key for credential encryption

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

@lru_cache()
def get_settings():
    return Settings()
