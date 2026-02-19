from pydantic_settings import BaseSettings, SettingsConfigDict
from functools import lru_cache
from typing import Optional

class Settings(BaseSettings):
    # App Config
    APP_NAME: str = "Agentic AI Trading Backend"
    DEBUG: bool = False
    
    # Zerodha Kite Connect Config
    ZERODHA_API_KEY: str
    ZERODHA_API_SECRET: str
    ZERODHA_ACCESS_TOKEN: Optional[str] = None # Can be set manually or via login flow (not fully implemented here)
    
    # OpenAI Config
    OPENAI_API_KEY: str
    OPENAI_MODEL: str = "gpt-4o"

    # Trading Config
    DEFAULT_TIMEFRAME: str = "day"
    DEFAULT_RISK_PERCENT: float = 1.0
    
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

@lru_cache()
def get_settings():
    return Settings()
