from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import field_validator, model_validator
from functools import lru_cache
from typing import Optional, List
from pathlib import Path

_ENV_FILE = Path(__file__).resolve().parent.parent.parent / ".env"

_INSECURE_DEFAULTS = {
    "your-secret-key-change-in-production",
    "change-me-in-production-vt-jwt-secret",
    "changeme",
    "secret",
    "",
}


class Settings(BaseSettings):
    # App Config
    APP_NAME: str = "Agentic AI Trading Backend"
    DEBUG: bool = False

    # Zerodha Kite Connect Config
    ZERODHA_API_KEY: Optional[str] = None
    ZERODHA_API_SECRET: Optional[str] = None
    ZERODHA_ACCESS_TOKEN: Optional[str] = None

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

    # CORS — comma-separated list of allowed origins
    ALLOWED_ORIGINS: str = "https://vantrade.in"

    # Frontend URL for OAuth redirects
    FRONTEND_URL: str = "https://vantrade.in"

    @field_validator("FRONTEND_URL", mode="before")
    @classmethod
    def _nonempty_frontend_url(cls, v: str) -> str:
        return v if v else "https://vantrade.in"

    # Admin Dashboard Config
    ADMIN_JWT_SECRET: Optional[str] = None
    ADMIN_JWT_ALGORITHM: str = "HS256"
    ADMIN_JWT_EXPIRATION_MINUTES: int = 480

    # Firebase Phone Auth
    FIREBASE_PROJECT_ID: Optional[str] = None
    FIREBASE_SERVICE_ACCOUNT: Optional[str] = None
    # VanTrade JWT
    VT_JWT_SECRET: Optional[str] = None
    VT_JWT_EXPIRY_HOURS: int = 720  # 30 days

    @model_validator(mode="after")
    def _reject_insecure_secrets(self) -> "Settings":
        """Reject weak values if secrets are explicitly set; defer None-check to startup."""
        if self.ADMIN_JWT_SECRET is not None:
            if self.ADMIN_JWT_SECRET in _INSECURE_DEFAULTS or len(self.ADMIN_JWT_SECRET) < 32:
                raise ValueError(
                    "ADMIN_JWT_SECRET is insecure. "
                    "Set a strong random value (≥32 chars) in your environment."
                )
        if self.VT_JWT_SECRET is not None:
            if self.VT_JWT_SECRET in _INSECURE_DEFAULTS or len(self.VT_JWT_SECRET) < 32:
                raise ValueError(
                    "VT_JWT_SECRET is insecure. "
                    "Set a strong random value (≥32 chars) in your environment."
                )
        return self

    def validate_production_secrets(self) -> None:
        """Call at app startup to enforce that secrets are present and strong."""
        if not self.ADMIN_JWT_SECRET or self.ADMIN_JWT_SECRET in _INSECURE_DEFAULTS or len(self.ADMIN_JWT_SECRET) < 32:
            raise RuntimeError(
                "ADMIN_JWT_SECRET is missing or insecure. "
                "Set a strong random value (≥32 chars) in your environment."
            )
        if not self.VT_JWT_SECRET or self.VT_JWT_SECRET in _INSECURE_DEFAULTS or len(self.VT_JWT_SECRET) < 32:
            raise RuntimeError(
                "VT_JWT_SECRET is missing or insecure. "
                "Set a strong random value (≥32 chars) in your environment."
            )

    @property
    def allowed_origins_list(self) -> List[str]:
        return [o.strip() for o in self.ALLOWED_ORIGINS.split(",") if o.strip()]

    model_config = SettingsConfigDict(env_file=str(_ENV_FILE), env_file_encoding="utf-8", extra="ignore")


@lru_cache()
def get_settings():
    return Settings()
