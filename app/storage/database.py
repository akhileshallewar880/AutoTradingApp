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
            self._ensure_swing_positions_table()
            self._ready = True

    def _ensure_swing_positions_table(self):
        """Create vantrade_swing_positions and its MS SQL trigger (idempotent)."""
        if not self._engine:
            return
        try:
            from sqlalchemy import text
            with self._engine.connect() as conn:
                # Table
                conn.execute(text("""
                    IF NOT EXISTS (
                        SELECT * FROM sys.tables WHERE name = 'vantrade_swing_positions'
                    )
                    CREATE TABLE vantrade_swing_positions (
                        id                 INT IDENTITY(1,1) PRIMARY KEY,
                        user_id            VARCHAR(50)       NOT NULL,
                        analysis_id        VARCHAR(50)       NOT NULL,
                        stock_symbol       VARCHAR(20)       NOT NULL,
                        action             VARCHAR(10)       NOT NULL,
                        quantity           INT               NOT NULL,
                        entry_price        DECIMAL(10,2)     NOT NULL,
                        stop_loss          DECIMAL(10,2)     NULL,
                        target_price       DECIMAL(10,2)     NULL,
                        fill_price         DECIMAL(10,2)     NULL,
                        gtt_id             VARCHAR(50)       NULL,
                        entry_order_id     VARCHAR(50)       NULL,
                        hold_duration_days INT               NOT NULL DEFAULT 0,
                        expiry_date        DATE              NULL,
                        status             VARCHAR(20)       NOT NULL DEFAULT 'OPEN',
                        exit_order_id      VARCHAR(50)       NULL,
                        exit_price         DECIMAL(10,2)     NULL,
                        pnl                DECIMAL(12,2)     NULL,
                        api_key            NVARCHAR(MAX)     NULL,
                        access_token       NVARCHAR(MAX)     NULL,
                        error_message      NVARCHAR(MAX)     NULL,
                        created_at         DATETIMEOFFSET    NOT NULL DEFAULT GETUTCDATE(),
                        closed_at          DATETIMEOFFSET    NULL,
                        INDEX idx_swing_status  (status),
                        INDEX idx_swing_expiry  (expiry_date, status),
                        INDEX idx_swing_user    (user_id, status),
                        INDEX idx_swing_symbol  (stock_symbol, status)
                    );
                """))
                conn.commit()

                # MS SQL Trigger: auto-compute expiry_date on INSERT
                conn.execute(text("""
                    IF NOT EXISTS (
                        SELECT * FROM sys.triggers
                        WHERE name = 'trg_set_swing_expiry'
                    )
                    EXEC('
                        CREATE TRIGGER trg_set_swing_expiry
                        ON vantrade_swing_positions
                        AFTER INSERT
                        AS
                        BEGIN
                            SET NOCOUNT ON;
                            UPDATE vantrade_swing_positions
                            SET expiry_date = CAST(
                                DATEADD(day, i.hold_duration_days,
                                        CAST(i.created_at AS DATE)) AS DATE)
                            FROM vantrade_swing_positions sp
                            INNER JOIN inserted i ON sp.id = i.id
                            WHERE i.hold_duration_days > 0;
                        END
                    ');
                """))
                conn.commit()

                # MS SQL Trigger: recompute expiry_date on UPDATE of hold_duration_days
                conn.execute(text("""
                    IF NOT EXISTS (
                        SELECT * FROM sys.triggers
                        WHERE name = 'trg_update_swing_expiry'
                    )
                    EXEC('
                        CREATE TRIGGER trg_update_swing_expiry
                        ON vantrade_swing_positions
                        AFTER UPDATE
                        AS
                        BEGIN
                            SET NOCOUNT ON;
                            IF UPDATE(hold_duration_days)
                            BEGIN
                                UPDATE vantrade_swing_positions
                                SET expiry_date = CAST(
                                    DATEADD(day, i.hold_duration_days,
                                            CAST(sp.created_at AS DATE)) AS DATE)
                                FROM vantrade_swing_positions sp
                                INNER JOIN inserted i ON sp.id = i.id
                                WHERE i.hold_duration_days > 0;
                            END
                        END
                    ');
                """))
                conn.commit()
                logger.info("[DB] vantrade_swing_positions table + triggers ready")
        except Exception as e:
            logger.warning(f"[DB] Could not ensure swing positions table: {e}")

    # ── Swing positions ─────────────────────────────────────────────────────

    def _sync_save_swing_position(self, data: dict):
        from sqlalchemy import text
        sql = text("""
            INSERT INTO vantrade_swing_positions
              (user_id, analysis_id, stock_symbol, action, quantity,
               entry_price, stop_loss, target_price, fill_price, gtt_id,
               entry_order_id, hold_duration_days, api_key, access_token)
            VALUES
              (:user_id, :analysis_id, :stock_symbol, :action, :quantity,
               :entry_price, :stop_loss, :target_price, :fill_price, :gtt_id,
               :entry_order_id, :hold_duration_days, :api_key, :access_token)
        """)
        with self._engine.connect() as conn:
            conn.execute(sql, data)
            conn.commit()

    async def save_swing_position(self, data: dict):
        """Persist a new swing position after fill + GTT placed."""
        self._ensure_engine()
        if not self._ready:
            return
        try:
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, self._sync_save_swing_position, data)
            logger.info(
                f"[DB] swing position saved: {data.get('stock_symbol')} "
                f"hold={data.get('hold_duration_days')}d"
            )
        except Exception as e:
            logger.error(f"[DB] save_swing_position failed: {e}")

    def _sync_get_expired_swing_positions(self) -> list:
        from sqlalchemy import text
        sql = text("""
            SELECT id, user_id, analysis_id, stock_symbol, action, quantity,
                   entry_price, fill_price, gtt_id, entry_order_id,
                   hold_duration_days, expiry_date, api_key, access_token
              FROM vantrade_swing_positions
             WHERE status      = 'OPEN'
               AND expiry_date <= CAST(GETDATE() AS DATE)
        """)
        with self._engine.connect() as conn:
            rows = conn.execute(sql).fetchall()
        keys = ["id","user_id","analysis_id","stock_symbol","action","quantity",
                "entry_price","fill_price","gtt_id","entry_order_id",
                "hold_duration_days","expiry_date","api_key","access_token"]
        return [dict(zip(keys, r)) for r in rows]

    async def get_expired_swing_positions(self) -> list:
        """Return all open swing positions whose hold period has elapsed."""
        self._ensure_engine()
        if not self._ready:
            return []
        try:
            loop = asyncio.get_event_loop()
            return await loop.run_in_executor(None, self._sync_get_expired_swing_positions)
        except Exception as e:
            logger.error(f"[DB] get_expired_swing_positions failed: {e}")
            return []

    def _sync_update_swing_position_status(self, position_id: int, status: str,
                                            exit_order_id: str = None,
                                            error_message: str = None):
        from sqlalchemy import text
        sql = text("""
            UPDATE vantrade_swing_positions
               SET status        = :status,
                   exit_order_id = COALESCE(:exit_order_id, exit_order_id),
                   error_message = COALESCE(:error_message, error_message),
                   closed_at     = CASE WHEN :status IN ('EXPIRED','CLOSED','ERROR')
                                        THEN GETUTCDATE() ELSE closed_at END
             WHERE id = :id
        """)
        with self._engine.connect() as conn:
            conn.execute(sql, {
                "id": position_id, "status": status,
                "exit_order_id": exit_order_id, "error_message": error_message,
            })
            conn.commit()

    async def mark_swing_position_exiting(self, position_id: int):
        self._ensure_engine()
        if not self._ready:
            return
        try:
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(
                None, self._sync_update_swing_position_status, position_id, "EXITING"
            )
        except Exception as e:
            logger.error(f"[DB] mark_swing_position_exiting failed: {e}")

    async def mark_swing_position_expired(self, position_id: int, exit_order_id: str = None):
        self._ensure_engine()
        if not self._ready:
            return
        try:
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(
                None, self._sync_update_swing_position_status,
                position_id, "EXPIRED", exit_order_id, None
            )
            logger.info(f"[DB] swing position {position_id} marked EXPIRED, exit={exit_order_id}")
        except Exception as e:
            logger.error(f"[DB] mark_swing_position_expired failed: {e}")

    async def mark_swing_position_error(self, position_id: int, error: str):
        self._ensure_engine()
        if not self._ready:
            return
        try:
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(
                None, self._sync_update_swing_position_status,
                position_id, "ERROR", None, error
            )
        except Exception as e:
            logger.error(f"[DB] mark_swing_position_error failed: {e}")

    def _sync_get_open_swing_positions_by_api_key(self, api_key: str) -> list:
        from sqlalchemy import text
        sql = text("""
            SELECT stock_symbol, action, stop_loss, target_price, gtt_id
              FROM vantrade_swing_positions
             WHERE api_key = :api_key
               AND status  IN ('OPEN', 'AMO_PENDING')
        """)
        with self._engine.connect() as conn:
            rows = conn.execute(sql, {"api_key": api_key}).fetchall()
        keys = ["stock_symbol", "action", "stop_loss", "target_price", "gtt_id"]
        return [dict(zip(keys, r)) for r in rows]

    async def get_open_swing_positions_by_api_key(self, api_key: str) -> list:
        """Return OPEN swing positions for a given api_key (for GTT fallback in holdings)."""
        self._ensure_engine()
        if not self._ready:
            return []
        try:
            loop = asyncio.get_event_loop()
            return await loop.run_in_executor(
                None, self._sync_get_open_swing_positions_by_api_key, api_key
            )
        except Exception as e:
            logger.error(f"[DB] get_open_swing_positions_by_api_key failed: {e}")
            return []

    def _sync_get_swing_expiry_by_api_key(self, api_key: str) -> dict:
        """Return {stock_symbol: {days_left, expiry_date, hold_duration_days}} for open positions."""
        from sqlalchemy import text
        from datetime import date
        sql = text("""
            SELECT stock_symbol, hold_duration_days, expiry_date, created_at
              FROM vantrade_swing_positions
             WHERE api_key = :api_key
               AND status  IN ('OPEN', 'AMO_PENDING')
        """)
        result = {}
        with self._engine.connect() as conn:
            rows = conn.execute(sql, {"api_key": api_key}).fetchall()
        for row in rows:
            sym, hold_days, expiry, created = row[0], row[1], row[2], row[3]
            days_left = None
            expiry_str = None
            if expiry:
                if hasattr(expiry, "date"):
                    expiry = expiry.date()
                today = date.today()
                days_left = (expiry - today).days
                expiry_str = expiry.isoformat()
            result[sym] = {
                "hold_duration_days": hold_days,
                "days_left": days_left,
                "expiry_date": expiry_str,
            }
        return result

    async def get_swing_expiry_by_api_key(self, api_key: str) -> dict:
        """Return {symbol: countdown_info} for all open swing positions of this api_key."""
        self._ensure_engine()
        if not self._ready:
            return {}
        try:
            loop = asyncio.get_event_loop()
            return await loop.run_in_executor(
                None, self._sync_get_swing_expiry_by_api_key, api_key
            )
        except Exception as e:
            logger.error(f"[DB] get_swing_expiry_by_api_key failed: {e}")
            return {}

    def _sync_get_closed_swing_positions_for_month(self, api_key: str, year: int, month: int) -> list:
        from sqlalchemy import text
        month_prefix = f"{year:04d}-{month:02d}"
        sql = text("""
            SELECT stock_symbol, action, quantity, entry_price, fill_price,
                   exit_price, pnl, closed_at
              FROM vantrade_swing_positions
             WHERE api_key = :api_key
               AND status  IN ('EXPIRED', 'CLOSED')
               AND CONVERT(VARCHAR(7), closed_at, 120) = :month_prefix
        """)
        with self._engine.connect() as conn:
            rows = conn.execute(sql, {"api_key": api_key, "month_prefix": month_prefix}).fetchall()
        keys = ["stock_symbol", "action", "quantity", "entry_price", "fill_price",
                "exit_price", "pnl", "closed_at"]
        return [dict(zip(keys, r)) for r in rows]

    async def get_closed_swing_positions_for_month(self, api_key: str, year: int, month: int) -> list:
        self._ensure_engine()
        if not self._ready:
            return []
        try:
            loop = asyncio.get_event_loop()
            return await loop.run_in_executor(
                None, self._sync_get_closed_swing_positions_for_month, api_key, year, month
            )
        except Exception as e:
            logger.error(f"[DB] get_closed_swing_positions_for_month failed: {e}")
            return []

    def _sync_get_closed_swing_positions_for_year(self, api_key: str, year: int) -> list:
        from sqlalchemy import text
        year_str = f"{year:04d}"
        sql = text("""
            SELECT stock_symbol, action, quantity, entry_price, fill_price,
                   exit_price, pnl, closed_at
              FROM vantrade_swing_positions
             WHERE api_key = :api_key
               AND status  IN ('EXPIRED', 'CLOSED')
               AND CONVERT(VARCHAR(4), closed_at, 120) = :year_str
        """)
        with self._engine.connect() as conn:
            rows = conn.execute(sql, {"api_key": api_key, "year_str": year_str}).fetchall()
        keys = ["stock_symbol", "action", "quantity", "entry_price", "fill_price",
                "exit_price", "pnl", "closed_at"]
        return [dict(zip(keys, r)) for r in rows]

    async def get_closed_swing_positions_for_year(self, api_key: str, year: int) -> list:
        self._ensure_engine()
        if not self._ready:
            return []
        try:
            loop = asyncio.get_event_loop()
            return await loop.run_in_executor(
                None, self._sync_get_closed_swing_positions_for_year, api_key, year
            )
        except Exception as e:
            logger.error(f"[DB] get_closed_swing_positions_for_year failed: {e}")
            return []

    def _sync_get_monthly_pnl_history(self, api_key: str, months: int = 12) -> list:
        """Return per-month aggregated P&L for the last N months (oldest → newest)."""
        from sqlalchemy import text
        sql = text("""
            SELECT
                YEAR(closed_at)  AS yr,
                MONTH(closed_at) AS mo,
                SUM(
                    CASE
                        WHEN pnl IS NOT NULL AND pnl <> 0 THEN pnl
                        WHEN action = 'BUY'
                             AND exit_price IS NOT NULL AND entry_price IS NOT NULL
                             THEN (exit_price - entry_price) * quantity
                        WHEN action = 'SELL'
                             AND exit_price IS NOT NULL AND entry_price IS NOT NULL
                             THEN (entry_price - exit_price) * quantity
                        ELSE 0
                    END
                )                              AS total_pnl,
                COUNT(*)                       AS total_trades,
                SUM(CASE WHEN pnl > 0 THEN 1 ELSE 0 END) AS winning_trades
              FROM vantrade_swing_positions
             WHERE api_key = :api_key
               AND status   IN ('EXPIRED', 'CLOSED')
               AND closed_at >= DATEADD(month, :neg_months, GETDATE())
             GROUP BY YEAR(closed_at), MONTH(closed_at)
             ORDER BY YEAR(closed_at), MONTH(closed_at)
        """)
        with self._engine.connect() as conn:
            rows = conn.execute(sql, {"api_key": api_key, "neg_months": -months}).fetchall()
        return [
            {"year": int(r[0]), "month": int(r[1]),
             "total_pnl": float(r[2] or 0),
             "total_trades": int(r[3] or 0),
             "winning_trades": int(r[4] or 0)}
            for r in rows
        ]

    async def get_monthly_pnl_history(self, api_key: str, months: int = 12) -> list:
        """Async wrapper — returns [{year, month, total_pnl, total_trades, winning_trades}]."""
        self._ensure_engine()
        if not self._ready:
            return []
        try:
            loop = asyncio.get_event_loop()
            return await loop.run_in_executor(
                None, self._sync_get_monthly_pnl_history, api_key, months
            )
        except Exception as e:
            logger.error(f"[DB] get_monthly_pnl_history failed: {e}")
            return []

    def _sync_get_amo_pending_positions(self) -> list:
        from sqlalchemy import text
        sql = text("""
            SELECT id, user_id, analysis_id, stock_symbol, action, quantity,
                   entry_price, stop_loss, target_price, entry_order_id,
                   hold_duration_days, api_key, access_token
              FROM vantrade_swing_positions
             WHERE status = 'AMO_PENDING'
        """)
        with self._engine.connect() as conn:
            rows = conn.execute(sql).fetchall()
        keys = ["id", "user_id", "analysis_id", "stock_symbol", "action", "quantity",
                "entry_price", "stop_loss", "target_price", "entry_order_id",
                "hold_duration_days", "api_key", "access_token"]
        return [dict(zip(keys, r)) for r in rows]

    async def get_amo_pending_positions(self) -> list:
        """Return all swing positions still waiting for AMO fill confirmation."""
        self._ensure_engine()
        if not self._ready:
            return []
        try:
            loop = asyncio.get_event_loop()
            return await loop.run_in_executor(None, self._sync_get_amo_pending_positions)
        except Exception as e:
            logger.error(f"[DB] get_amo_pending_positions failed: {e}")
            return []

    def _sync_mark_swing_position_active(self, position_id: int, fill_price: float, gtt_id: str):
        from sqlalchemy import text
        sql = text("""
            UPDATE vantrade_swing_positions
               SET status     = 'OPEN',
                   fill_price = :fill_price,
                   gtt_id     = :gtt_id
             WHERE id = :id
        """)
        with self._engine.connect() as conn:
            conn.execute(sql, {"id": position_id, "fill_price": fill_price, "gtt_id": gtt_id})
            conn.commit()

    async def mark_swing_position_active(self, position_id: int, fill_price: float, gtt_id: str):
        """Mark an AMO_PENDING position as OPEN after fill + GTT placement."""
        self._ensure_engine()
        if not self._ready:
            return
        try:
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(
                None, self._sync_mark_swing_position_active, position_id, fill_price, gtt_id
            )
            logger.info(f"[DB] swing position {position_id} activated: fill={fill_price}, gtt={gtt_id}")
        except Exception as e:
            logger.error(f"[DB] mark_swing_position_active failed: {e}")

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

    # ── Phone Auth ────────────────────────────────────────────────────────────

    def _sync_upsert_user_by_firebase_uid(
        self,
        firebase_uid: str,
        phone_number: str,
        phone_verified_at: str,
    ) -> dict:
        from sqlalchemy import text
        import uuid as _uuid

        sql_lookup = text(
            "SELECT vt_user_id FROM vantrade_users WHERE firebase_uid = :fuid"
        )
        sql_insert = text("""
            INSERT INTO vantrade_users
              (vt_user_id, firebase_uid, phone_number, phone_verified_at,
               full_name, is_active, user_type, created_at, updated_at)
            VALUES
              (:vt_user_id, :fuid, :phone, :verified_at,
               '', 1, 'USER', GETUTCDATE(), GETUTCDATE())
        """)
        sql_update = text("""
            UPDATE vantrade_users
               SET phone_number      = :phone,
                   phone_verified_at = :verified_at,
                   updated_at        = GETUTCDATE()
             WHERE firebase_uid = :fuid
        """)

        with self._engine.connect() as conn:
            row = conn.execute(sql_lookup, {"fuid": firebase_uid}).fetchone()
            if row and row[0]:
                conn.execute(sql_update, {
                    "phone": phone_number,
                    "verified_at": phone_verified_at,
                    "fuid": firebase_uid,
                })
                conn.commit()
                return {"vt_user_id": row[0], "is_new_user": False}
            else:
                new_id = str(_uuid.uuid4())
                conn.execute(sql_insert, {
                    "vt_user_id": new_id,
                    "fuid": firebase_uid,
                    "phone": phone_number,
                    "verified_at": phone_verified_at,
                })
                conn.commit()
                return {"vt_user_id": new_id, "is_new_user": True}

    async def upsert_user_by_firebase_uid(
        self,
        firebase_uid: str,
        phone_number: str,
        phone_verified_at: str,
    ) -> dict:
        """Insert or update a user record by Firebase UID. Returns vt_user_id + is_new_user."""
        self._ensure_engine()
        if not self._ready:
            import uuid as _uuid
            return {"vt_user_id": str(_uuid.uuid4()), "is_new_user": True}
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            None,
            self._sync_upsert_user_by_firebase_uid,
            firebase_uid,
            phone_number,
            phone_verified_at,
        )


db = Database()
