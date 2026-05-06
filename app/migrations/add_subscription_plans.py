"""
Migration: Add subscription plans, user subscriptions, and usage tracking tables.

Creates:
  - vantrade_plans          : plan definitions (Free / Pro / Elite)
  - vantrade_subscriptions  : one active subscription per user
  - vantrade_usage_records  : monthly analysis + execution counts per user

Safe to run multiple times — all statements are guarded with IF NOT EXISTS.
"""

from sqlalchemy import text


def _get_engine():
    try:
        from app.storage.database import _get_engine as _db_get_engine
        return _db_get_engine()
    except Exception:
        pass
    try:
        from app.core.database import engine
        return engine
    except Exception:
        return None


def apply(engine=None):
    if engine is None:
        engine = _get_engine()
    if engine is None:
        raise RuntimeError("No database engine — set DB_SERVER, DB_NAME, DB_USER, DB_PASSWORD.")

    with engine.connect() as conn:

        # ── 1. Plans ─────────────────────────────────────────────────────────
        conn.execute(text("""
            IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'vantrade_plans')
            CREATE TABLE vantrade_plans (
                plan_id              VARCHAR(20)    NOT NULL PRIMARY KEY,
                name                 VARCHAR(50)    NOT NULL,
                price_monthly        DECIMAL(8,2)   NOT NULL DEFAULT 0,
                analyses_per_month   INT            NULL,   -- NULL = unlimited
                executions_per_month INT            NULL,   -- NULL = unlimited
                features             NVARCHAR(MAX)  NULL,   -- JSON array of feature strings
                is_active            BIT            NOT NULL DEFAULT 1,
                created_at           DATETIMEOFFSET NOT NULL DEFAULT GETUTCDATE()
            );
        """))
        conn.commit()

        # Seed default plans (upsert so re-running is safe)
        conn.execute(text("""
            MERGE vantrade_plans AS target
            USING (VALUES
                ('free',  'Free',  0.00,   10,   5,    '["10 analyses/month","5 executions/month","Basic support"]', 1),
                ('pro',   'Pro',   499.00, 30,   50,   '["30 analyses/month","50 executions/month","Priority support","Advanced indicators"]', 1),
                ('elite', 'Elite', 999.00, NULL, NULL, '["Unlimited analyses","Unlimited executions","Dedicated support","All features"]', 1)
            ) AS src (plan_id, name, price_monthly, analyses_per_month, executions_per_month, features, is_active)
            ON target.plan_id = src.plan_id
            WHEN MATCHED THEN
                UPDATE SET name=src.name, price_monthly=src.price_monthly,
                           analyses_per_month=src.analyses_per_month,
                           executions_per_month=src.executions_per_month,
                           features=src.features, is_active=src.is_active
            WHEN NOT MATCHED THEN
                INSERT (plan_id, name, price_monthly, analyses_per_month, executions_per_month, features, is_active)
                VALUES (src.plan_id, src.name, src.price_monthly, src.analyses_per_month, src.executions_per_month, src.features, src.is_active);
        """))
        conn.commit()

        # ── 2. Subscriptions ─────────────────────────────────────────────────
        conn.execute(text("""
            IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'vantrade_subscriptions')
            CREATE TABLE vantrade_subscriptions (
                subscription_id   VARCHAR(36)    NOT NULL PRIMARY KEY,
                vt_user_id        VARCHAR(36)    NOT NULL,
                plan_id           VARCHAR(20)    NOT NULL DEFAULT 'free',
                status            VARCHAR(20)    NOT NULL DEFAULT 'active',  -- active/cancelled/expired
                started_at        DATETIMEOFFSET NOT NULL DEFAULT GETUTCDATE(),
                expires_at        DATETIMEOFFSET NULL,
                payment_provider  VARCHAR(50)    NULL,   -- razorpay/stripe
                payment_id        VARCHAR(200)   NULL,   -- provider's payment/subscription ID
                amount_paid       DECIMAL(8,2)   NULL,
                created_at        DATETIMEOFFSET NOT NULL DEFAULT GETUTCDATE(),
                updated_at        DATETIMEOFFSET NOT NULL DEFAULT GETUTCDATE()
            );
        """))
        conn.execute(text("""
            IF NOT EXISTS (
                SELECT 1 FROM sys.indexes
                 WHERE object_id = OBJECT_ID('vantrade_subscriptions')
                   AND name = 'idx_sub_user'
            )
                CREATE INDEX idx_sub_user ON vantrade_subscriptions(vt_user_id, status);
        """))
        conn.commit()

        # ── 3. Usage records ─────────────────────────────────────────────────
        conn.execute(text("""
            IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'vantrade_usage_records')
            CREATE TABLE vantrade_usage_records (
                record_id          VARCHAR(36)    NOT NULL PRIMARY KEY,
                vt_user_id         VARCHAR(36)    NOT NULL,
                period_month       VARCHAR(7)     NOT NULL,  -- 'YYYY-MM'
                analyses_count     INT            NOT NULL DEFAULT 0,
                executions_count   INT            NOT NULL DEFAULT 0,
                last_analysis_at   DATETIMEOFFSET NULL,
                last_execution_at  DATETIMEOFFSET NULL,
                created_at         DATETIMEOFFSET NOT NULL DEFAULT GETUTCDATE(),
                updated_at         DATETIMEOFFSET NOT NULL DEFAULT GETUTCDATE()
            );
        """))
        conn.execute(text("""
            IF NOT EXISTS (
                SELECT 1 FROM sys.indexes
                 WHERE object_id = OBJECT_ID('vantrade_usage_records')
                   AND name = 'uq_usage_user_month'
            )
                CREATE UNIQUE INDEX uq_usage_user_month
                    ON vantrade_usage_records(vt_user_id, period_month);
        """))
        conn.commit()

        print("✅ add_subscription_plans migration applied successfully")
    return True


def rollback(engine=None):
    if engine is None:
        engine = _get_engine()
    if engine is None:
        raise RuntimeError("No database engine available.")

    with engine.connect() as conn:
        for tbl in ["vantrade_usage_records", "vantrade_subscriptions", "vantrade_plans"]:
            conn.execute(text(f"""
                IF EXISTS (SELECT 1 FROM sys.tables WHERE name = '{tbl}')
                    DROP TABLE {tbl};
            """))
        conn.commit()
        print("✅ add_subscription_plans rollback complete")
    return True
