"""
Migration: Swing Trade Expiry Infrastructure
=============================================
Creates the vantrade_swing_positions table and the two MS SQL Server triggers
that automatically compute expiry_date whenever a position is inserted or
its hold_duration_days is updated.

Run once:
    python run_migration.py swing_expiry_trigger

The migration is idempotent — safe to re-run.
"""
from app.core.logging import logger


def run():
    try:
        from app.storage.database import _get_engine
        from sqlalchemy import text
    except ImportError as e:
        logger.error(f"[Migration] Import error: {e}")
        return False

    engine = _get_engine()
    if engine is None:
        logger.error("[Migration] No database connection — check DB_SERVER / credentials")
        return False

    steps = [
        # ── 1. Create table ───────────────────────────────────────────────────
        (
            "Create vantrade_swing_positions",
            """
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
                closed_at          DATETIMEOFFSET    NULL
            );
            """,
        ),
        # ── 2. Indexes (created separately — IF NOT EXISTS for each) ──────────
        (
            "Index idx_swing_status",
            """
            IF NOT EXISTS (
                SELECT * FROM sys.indexes
                WHERE name = 'idx_swing_status'
                  AND object_id = OBJECT_ID('vantrade_swing_positions')
            )
            CREATE INDEX idx_swing_status ON vantrade_swing_positions (status);
            """,
        ),
        (
            "Index idx_swing_expiry",
            """
            IF NOT EXISTS (
                SELECT * FROM sys.indexes
                WHERE name = 'idx_swing_expiry'
                  AND object_id = OBJECT_ID('vantrade_swing_positions')
            )
            CREATE INDEX idx_swing_expiry ON vantrade_swing_positions (expiry_date, status);
            """,
        ),
        (
            "Index idx_swing_user",
            """
            IF NOT EXISTS (
                SELECT * FROM sys.indexes
                WHERE name = 'idx_swing_user'
                  AND object_id = OBJECT_ID('vantrade_swing_positions')
            )
            CREATE INDEX idx_swing_user ON vantrade_swing_positions (user_id, status);
            """,
        ),
        (
            "Index idx_swing_symbol",
            """
            IF NOT EXISTS (
                SELECT * FROM sys.indexes
                WHERE name = 'idx_swing_symbol'
                  AND object_id = OBJECT_ID('vantrade_swing_positions')
            )
            CREATE INDEX idx_swing_symbol ON vantrade_swing_positions (stock_symbol, status);
            """,
        ),
        # ── 3. INSERT trigger: set expiry_date when row is created ────────────
        (
            "Trigger trg_set_swing_expiry (INSERT)",
            """
            IF EXISTS (
                SELECT * FROM sys.triggers WHERE name = 'trg_set_swing_expiry'
            )
            DROP TRIGGER trg_set_swing_expiry;
            """,
        ),
        (
            "Create trg_set_swing_expiry",
            """
            EXEC('
                CREATE TRIGGER trg_set_swing_expiry
                ON vantrade_swing_positions
                AFTER INSERT
                AS
                BEGIN
                    SET NOCOUNT ON;
                    -- Compute expiry_date = created_at date + hold_duration_days
                    UPDATE vantrade_swing_positions
                    SET expiry_date = CAST(
                            DATEADD(day, i.hold_duration_days,
                                    CAST(i.created_at AS DATE)) AS DATE)
                    FROM vantrade_swing_positions sp
                    INNER JOIN inserted i ON sp.id = i.id
                    WHERE i.hold_duration_days > 0;
                END
            ');
            """,
        ),
        # ── 4. UPDATE trigger: recompute if hold_duration_days changes ─────────
        (
            "Drop trg_update_swing_expiry if exists",
            """
            IF EXISTS (
                SELECT * FROM sys.triggers WHERE name = 'trg_update_swing_expiry'
            )
            DROP TRIGGER trg_update_swing_expiry;
            """,
        ),
        (
            "Create trg_update_swing_expiry",
            """
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
            """,
        ),
    ]

    with engine.connect() as conn:
        for step_name, sql in steps:
            try:
                conn.execute(text(sql))
                conn.commit()
                logger.info(f"[Migration] ✓ {step_name}")
            except Exception as e:
                logger.error(f"[Migration] ✗ {step_name}: {e}")
                return False

    logger.info("[Migration] swing_expiry_trigger complete")
    return True


if __name__ == "__main__":
    success = run()
    exit(0 if success else 1)
