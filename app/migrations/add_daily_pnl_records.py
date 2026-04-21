"""
Migration: Add vantrade_daily_pnl_records table.
Stores per-day realized P&L snapshots per user so monthly performance
data survives re-logins (Zerodha only returns today's trade history).
"""

from sqlalchemy import text


def _get_engine():
    """Build a SQLAlchemy engine from app config, or return None if not configured."""
    try:
        from app.storage.database import _build_conn_str, _get_engine as _db_get_engine
        return _db_get_engine()
    except Exception:
        pass
    try:
        from app.core.database import engine
        return engine
    except Exception:
        return None


def apply(engine=None):
    """Apply migration to add daily P&L records table."""
    if engine is None:
        engine = _get_engine()
    if engine is None:
        raise RuntimeError(
            "No database engine available — ensure DB_SERVER, DB_NAME, DB_USER, "
            "DB_PASSWORD environment variables are set."
        )
    with engine.connect() as conn:
        conn.execute(text("""
            IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'vantrade_daily_pnl_records')
            CREATE TABLE vantrade_daily_pnl_records (
                record_id       INT IDENTITY(1,1) PRIMARY KEY,
                user_id         INT NOT NULL REFERENCES vantrade_users(user_id),
                trade_date      VARCHAR(10) NOT NULL,   -- YYYY-MM-DD
                realized_pnl    DECIMAL(12,2) NOT NULL DEFAULT 0,
                gross_profit    DECIMAL(12,2) NOT NULL DEFAULT 0,
                gross_loss      DECIMAL(12,2) NOT NULL DEFAULT 0,
                total_charges   DECIMAL(12,2) NOT NULL DEFAULT 0,
                total_trades    INT NOT NULL DEFAULT 0,
                winning_positions INT NOT NULL DEFAULT 0,
                losing_positions  INT NOT NULL DEFAULT 0,
                updated_at      DATETIMEOFFSET DEFAULT GETUTCDATE(),
                INDEX idx_daily_pnl_user_date (user_id, trade_date)
            );
        """))
        conn.commit()
        print("✓ Created vantrade_daily_pnl_records table")
