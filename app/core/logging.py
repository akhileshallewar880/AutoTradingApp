import logging
import sys
import os
from logging.handlers import RotatingFileHandler
from app.core.config import get_settings

settings = get_settings()

def setup_logging():
    """Configures structured logging — stdout + rotating file."""
    root = logging.getLogger()
    root.setLevel(logging.DEBUG if settings.DEBUG else logging.INFO)

    fmt = logging.Formatter(
        "%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # ── Console handler ──────────────────────────────────────────────────────
    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(fmt)

    # ── Rotating file handler (10 MB × 5 files = 50 MB max) ─────────────────
    log_dir = os.path.join(os.path.dirname(__file__), "..", "..", "logs")
    os.makedirs(log_dir, exist_ok=True)
    log_path = os.path.join(log_dir, "agent.log")
    file_handler = RotatingFileHandler(
        log_path, maxBytes=10 * 1024 * 1024, backupCount=5, encoding="utf-8"
    )
    file_handler.setFormatter(fmt)

    if not root.handlers:
        root.addHandler(console)
        root.addHandler(file_handler)

    # Suppress noise from third-party libs
    for noisy in ("urllib3", "httpx", "websocket", "kiteconnect"):
        logging.getLogger(noisy).setLevel(logging.WARNING)

    return root

logger = setup_logging()
