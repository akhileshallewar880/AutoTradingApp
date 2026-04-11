"""
Database — Azure SQL (pyodbc / SQLAlchemy) implementation.

If DB_SERVER is configured in .env → connects to Azure SQL and persists all trade data.
If DB_SERVER is missing → falls back to the no-op stub so the app still runs locally.

All public methods are async-safe: heavy I/O runs via loop.run_in_executor so the
FastAPI event loop is never blocked.
"""
from __future__ import annotations

import asyncio
from datetime import datetime, date
from decimal import Decimal
from typing import List, Optional, Any
import json

from app.core.config import get_settings
from app.core.logging import logger

settings = get_settings()


def _build_conn_str() -> Optional[str]:
    """Build pyodbc connection string from settings. Returns None if DB not configured."""
    s = settings
    if not all([s.DB_SERVER, s.DB_NAME, s.DB_USER, s.DB_PASSWORD]):
        return None

    # Detect available ODBC driver
    try:
        import pyodbc
        drivers = pyodbc.drivers()
    except ImportError:
        logger.warning("[DB] pyodbc not installed — running in no-op mode")
        return None

    driver = None
    for candidate in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server"):
        if candidate in drivers:
            driver = candidate
            break

    if not driver:
        logger.warning(f"[DB] No SQL Server ODBC driver found (available: {drivers})")
        return None

    encrypt = "yes" if "18" in driver else "no"
    return (
        f"DRIVER={{{driver}}};"
        f"SERVER={s.DB_SERVER};"
        f"DATABASE={s.DB_NAME};"
        f"UID={s.DB_USER};"
        f"PWD={s.DB_PASSWORD};"
        f"Encrypt={encrypt};"
        f"TrustServerCertificate=yes;"
        f"Connection Timeout=30;"
    )


def _get_engine():
    """Create SQLAlchemy engine (sync). Cached after first call."""
    conn_str = _build_conn_str()
    if not conn_str:
        return None
    try:
        from sqlalchemy import create_engine
        import urllib.parse
        params = urllib.parse.quote_plus(conn_str)
        engine = create_engine(
            f"mssql+pyodbc:///?odbc_connect={params}",
            pool_pre_ping=True,
            pool_size=settings.DB_POOL_SIZE,
            max_overflow=settings.DB_MAX_OVERFLOW,
            echo=False,
        )
        # Smoke test
        with engine.connect() as c:
            c.execute(__import__("sqlalchemy").text("SELECT 1"))
        logger.info("[DB] Azure SQL connection established")
        return engine
    except Exception as e:
        logger.warning(f"[DB] Could not connect to Azure SQL: {e}. Running in no-op mode.")
        return None


class Database:
    """
    Async wrapper around Azure SQL.

    Pattern: every method does `await loop.run_in_executor(None, _sync_fn)` so
    the FastAPI event loop is never blocked by pyodbc I/O.
    """

    def __init__(self):
        self._engine = None
        self._ready = False
        self._init_attempted = False

    def _ensure_engine(self):
        if self._init_attempted:
            return
        self._init_attempted = True
        self._engine = _get_engine()
        if self._engine:
            self._ensure_options_trade_table()
            self._ready = True

    def _ensure_options_trade_table(self):
        """Create vantrade_options_trades if it doesn't exist (idempotent)."""
        if not self._engine:
            return
        try:
            from sqlalchemy import text
            with self._engine.connect() as conn:
                conn.execute(text("""
                    IF NOT EXISTS (
                        SELECT * FROM sys.tables WHERE name = 'vantrade_options_trades'
                    )
                    CREATE TABLE vantrade_options_trades (
                        id              INT IDENTITY(1,1) PRIMARY KEY,
                        analysis_id     VARCHAR(50)  NOT NULL,
                        index_name      VARCHAR(20)  NOT NULL,
                        option_symbol   VARCHAR(50)  NOT NULL,
                        option_type     VARCHAR(5)   NOT NULL,
                        strike          DECIMAL(10,2) NULL,
                        expiry_date     DATE          NULL,
                        lots            INT           NOT NULL DEFAULT 1,
                        quantity        INT           NOT NULL,
                        entry_premium   DECIMAL(10,2) NULL,
                        sl_premium      DECIMAL(10,2) NULL,
                        target_premium  DECIMAL(10,2) NULL,
                        fill_price      DECIMAL(10,2) NULL,
                        sl_order_id     VARCHAR(50)   NULL,
                        target_order_id VARCHAR(50)   NULL,
                        regime          VARCHAR(30)   NULL,
                        confidence      DECIMAL(5,2)  NULL,
                        status          VARCHAR(20)   NOT NULL DEFAULT 'ACTIVE',
                        exit_reason     VARCHAR(50)   NULL,
                        exit_premium    DECIMAL(10,2) NULL,
                        pnl             DECIMAL(12,2) NULL,
                        partial_pnl     DECIMAL(12,2) NULL,
                        signal_reasons  NVARCHAR(MAX) NULL,
                        failed_filters  NVARCHAR(MAX) NULL,
                        created_at      DATETIMEOFFSET NOT NULL DEFAULT GETUTCDATE(),
                        closed_at       DATETIMEOFFSET NULL,
                        INDEX idx_options_analysis_id (analysis_id),
                        INDEX idx_options_created_at  (created_at),
                        INDEX idx_options_status      (status)
                    );
                """))
                conn.commit()
                logger.info("[DB] vantrade_options_trades table ready")
        except Exception as e:
            logger.warning(f"[DB] Could not ensure options table: {e}")

    # ── Options trades ──────────────────────────────────────────────────────

    def _sync_save_options_trade(self, data: dict):
        from sqlalchemy import text
        sql = text("""
            INSERT INTO vantrade_options_trades
              (analysis_id, index_name, option_symbol, option_type, strike,
               expiry_date, lots, quantity, entry_premium, sl_premium,
               target_premium, fill_price, sl_order_id, target_order_id,
               regime, confidence, status, signal_reasons, failed_filters)
            VALUES
              (:analysis_id, :index_name, :option_symbol, :option_type, :strike,
               :expiry_date, :lots, :quantity, :entry_premium, :sl_premium,
               :target_premium, :fill_price, :sl_order_id, :target_order_id,
               :regime, :confidence, 'ACTIVE', :signal_reasons, :failed_filters)
        """)
        with self._engine.connect() as conn:
            conn.execute(sql, data)
            conn.commit()

    async def save_options_trade(self, data: dict):
        """Persist a new options trade immediately after execution fill."""
        self._ensure_engine()
        if not self._ready:
            return
        try:
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, self._sync_save_options_trade, data)
            logger.info(f"[DB] options trade saved: {data.get('analysis_id')}")
        except Exception as e:
            logger.error(f"[DB] save_options_trade failed: {e}")

    def _sync_close_options_trade(self, analysis_id: str, exit_reason: str,
                                   exit_premium: float, pnl: float, partial_pnl: float):
        from sqlalchemy import text
        sql = text("""
            UPDATE vantrade_options_trades
               SET status       = 'CLOSED',
                   exit_reason  = :exit_reason,
                   exit_premium = :exit_premium,
                   pnl          = :pnl,
                   partial_pnl  = :partial_pnl,
                   closed_at    = GETUTCDATE()
             WHERE analysis_id  = :analysis_id
               AND status       = 'ACTIVE'
        """)
        with self._engine.connect() as conn:
            conn.execute(sql, {
                "analysis_id":  analysis_id,
                "exit_reason":  exit_reason,
                "exit_premium": exit_premium,
                "pnl":          pnl,
                "partial_pnl":  partial_pnl,
            })
            conn.commit()

    async def close_options_trade(
        self,
        analysis_id: str,
        exit_reason: str,
        exit_premium: float,
        pnl: float,
        partial_pnl: float = 0.0,
    ):
        """Update the options trade row to CLOSED with final P&L."""
        self._ensure_engine()
        if not self._ready:
            return
        try:
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(
                None,
                self._sync_close_options_trade,
                analysis_id, exit_reason, exit_premium, pnl, partial_pnl,
            )
            logger.info(
                f"[DB] options trade closed: {analysis_id} "
                f"reason={exit_reason} pnl=₹{pnl:+.0f}"
            )
        except Exception as e:
            logger.error(f"[DB] close_options_trade failed: {e}")

    def load_todays_options_trades_sync(self) -> list:
        """
        Return today's options trade rows as a list of dicts.
        Used at startup to restore the anti-overtrading guard state.
        Returns [] when DB is not configured (local dev).
        """
        self._ensure_engine()
        if not self._ready:
            return []
        try:
            from sqlalchemy import text
            with self._engine.connect() as conn:
                rows = conn.execute(text("""
                    SELECT index_name, status, exit_reason, pnl,
                           CAST(created_at AS DATE) AS trade_date
                      FROM vantrade_options_trades
                     WHERE CAST(created_at AS DATE) = CAST(GETUTCDATE() AS DATE)
                """)).fetchall()
            from datetime import date as _date
            return [
                {
                    "index_name":  r[0],
                    "status":      r[1],
                    "exit_reason": r[2],
                    "pnl":         float(r[3]) if r[3] is not None else None,
                    "trade_date":  _date.today(),   # already filtered to today
                }
                for r in rows
            ]
        except Exception as e:
            logger.warning(f"[DB] load_todays_options_trades failed: {e}")
            return []

    # ── Existing stubs (kept for backward-compat with rest of app) ──────────

    async def save_analysis(self, analysis):
        pass

    async def get_analysis(self, analysis_id: str) -> Optional[dict]:
        return None

    async def update_analysis_status(self, analysis_id: str, status: str):
        pass

    async def save_execution_update(self, update):
        pass

    async def get_execution_updates(self, analysis_id: str) -> List:
        return []

    async def get_all_analyses(self, limit: int = 50) -> List[dict]:
        return []

    async def save_trade(self, trade):
        pass

    async def get_all_trades(self) -> List:
        return []

    async def get_monthly_trades(self, month: int, year: int) -> List:
        return []

    async def save_token_usage(self, *args, **kwargs):
        pass


db = Database()
