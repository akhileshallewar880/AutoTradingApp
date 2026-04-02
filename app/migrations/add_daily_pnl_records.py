"""
Migration: Add vantrade_daily_pnl_records table.
Stores per-day realized P&L snapshots per user so monthly performance
data survives re-logins (Zerodha only returns today's trade history).
"""

from sqlalchemy import text


def apply(engine):
    """Apply migration to add daily P&L records table."""
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
