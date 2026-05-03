"""
Migration: Add phone authentication columns to vantrade_users.

Changes:
  - Add phone_number   VARCHAR(20)  NULL  (unique, filtered index)
  - Add firebase_uid   VARCHAR(128) NULL  (unique, filtered index)
  - Add phone_verified_at DATETIMEOFFSET NULL
  - Add vt_user_id     VARCHAR(36)  NULL  (unique, filtered index — stable UUID)
  - Make zerodha_user_id nullable  (phone-only users won't have Zerodha)
  - Make email         nullable    (phone-only users may not have email)

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
    """Add phone auth columns and make identity columns nullable."""
    if engine is None:
        engine = _get_engine()
    if engine is None:
        raise RuntimeError(
            "No database engine — set DB_SERVER, DB_NAME, DB_USER, DB_PASSWORD."
        )

    with engine.connect() as conn:

        # ── 1. Add phone_number ───────────────────────────────────────────────
        conn.execute(text("""
            IF NOT EXISTS (
                SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                 WHERE TABLE_NAME = 'vantrade_users'
                   AND COLUMN_NAME = 'phone_number'
            )
                ALTER TABLE vantrade_users ADD phone_number VARCHAR(20) NULL;
        """))

        conn.execute(text("""
            IF NOT EXISTS (
                SELECT 1 FROM sys.indexes
                 WHERE object_id = OBJECT_ID('vantrade_users')
                   AND name = 'uq_vantrade_users_phone'
            )
                CREATE UNIQUE INDEX uq_vantrade_users_phone
                    ON vantrade_users(phone_number)
                 WHERE phone_number IS NOT NULL;
        """))

        # ── 2. Add firebase_uid ───────────────────────────────────────────────
        conn.execute(text("""
            IF NOT EXISTS (
                SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                 WHERE TABLE_NAME = 'vantrade_users'
                   AND COLUMN_NAME = 'firebase_uid'
            )
                ALTER TABLE vantrade_users ADD firebase_uid VARCHAR(128) NULL;
        """))

        conn.execute(text("""
            IF NOT EXISTS (
                SELECT 1 FROM sys.indexes
                 WHERE object_id = OBJECT_ID('vantrade_users')
                   AND name = 'uq_vantrade_users_firebase_uid'
            )
                CREATE UNIQUE INDEX uq_vantrade_users_firebase_uid
                    ON vantrade_users(firebase_uid)
                 WHERE firebase_uid IS NOT NULL;
        """))

        # ── 3. Add phone_verified_at ──────────────────────────────────────────
        conn.execute(text("""
            IF NOT EXISTS (
                SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                 WHERE TABLE_NAME = 'vantrade_users'
                   AND COLUMN_NAME = 'phone_verified_at'
            )
                ALTER TABLE vantrade_users ADD phone_verified_at DATETIMEOFFSET NULL;
        """))

        # ── 4. Add vt_user_id ─────────────────────────────────────────────────
        conn.execute(text("""
            IF NOT EXISTS (
                SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                 WHERE TABLE_NAME = 'vantrade_users'
                   AND COLUMN_NAME = 'vt_user_id'
            )
                ALTER TABLE vantrade_users ADD vt_user_id VARCHAR(36) NULL;
        """))

        conn.execute(text("""
            IF NOT EXISTS (
                SELECT 1 FROM sys.indexes
                 WHERE object_id = OBJECT_ID('vantrade_users')
                   AND name = 'uq_vantrade_users_vt_user_id'
            )
                CREATE UNIQUE INDEX uq_vantrade_users_vt_user_id
                    ON vantrade_users(vt_user_id)
                 WHERE vt_user_id IS NOT NULL;
        """))

        # ── 5. Make zerodha_user_id nullable ─────────────────────────────────
        # Must drop any existing inline unique constraint before altering column.
        # Zerodha users keep their value; phone-only users will have NULL.
        conn.execute(text("""
            DECLARE @con_name NVARCHAR(256);
            SELECT @con_name = dc.name
              FROM sys.default_constraints dc
              JOIN sys.columns c
                ON c.default_object_id = dc.object_id
             WHERE OBJECT_NAME(dc.parent_object_id) = 'vantrade_users'
               AND c.name = 'zerodha_user_id';
            IF @con_name IS NOT NULL
                EXEC('ALTER TABLE vantrade_users DROP CONSTRAINT [' + @con_name + ']');
        """))

        # Check if already nullable before altering (idempotent)
        conn.execute(text("""
            IF EXISTS (
                SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                 WHERE TABLE_NAME  = 'vantrade_users'
                   AND COLUMN_NAME = 'zerodha_user_id'
                   AND IS_NULLABLE = 'NO'
            )
                ALTER TABLE vantrade_users ALTER COLUMN zerodha_user_id VARCHAR(255) NULL;
        """))

        # Recreate as filtered unique index (NULLs allowed)
        conn.execute(text("""
            IF NOT EXISTS (
                SELECT 1 FROM sys.indexes
                 WHERE object_id = OBJECT_ID('vantrade_users')
                   AND name = 'uq_vantrade_users_zerodha_id'
            )
                CREATE UNIQUE INDEX uq_vantrade_users_zerodha_id
                    ON vantrade_users(zerodha_user_id)
                 WHERE zerodha_user_id IS NOT NULL;
        """))

        # ── 6. Make email nullable ────────────────────────────────────────────
        conn.execute(text("""
            DECLARE @con_email NVARCHAR(256);
            SELECT @con_email = dc.name
              FROM sys.default_constraints dc
              JOIN sys.columns c
                ON c.default_object_id = dc.object_id
             WHERE OBJECT_NAME(dc.parent_object_id) = 'vantrade_users'
               AND c.name = 'email';
            IF @con_email IS NOT NULL
                EXEC('ALTER TABLE vantrade_users DROP CONSTRAINT [' + @con_email + ']');
        """))

        conn.execute(text("""
            IF EXISTS (
                SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                 WHERE TABLE_NAME  = 'vantrade_users'
                   AND COLUMN_NAME = 'email'
                   AND IS_NULLABLE = 'NO'
            )
                ALTER TABLE vantrade_users ALTER COLUMN email VARCHAR(255) NULL;
        """))

        conn.execute(text("""
            IF NOT EXISTS (
                SELECT 1 FROM sys.indexes
                 WHERE object_id = OBJECT_ID('vantrade_users')
                   AND name = 'uq_vantrade_users_email'
            )
                CREATE UNIQUE INDEX uq_vantrade_users_email
                    ON vantrade_users(email)
                 WHERE email IS NOT NULL;
        """))

        conn.commit()
        print("✅ add_phone_auth migration applied successfully")
    return True


def rollback(engine=None):
    """Reverse the phone auth migration — drops new columns, restores NOT NULL on identity cols."""
    if engine is None:
        engine = _get_engine()
    if engine is None:
        raise RuntimeError("No database engine available.")

    with engine.connect() as conn:
        # Drop filtered indexes first
        for idx in [
            "uq_vantrade_users_phone",
            "uq_vantrade_users_firebase_uid",
            "uq_vantrade_users_vt_user_id",
            "uq_vantrade_users_zerodha_id",
            "uq_vantrade_users_email",
        ]:
            conn.execute(text(f"""
                IF EXISTS (
                    SELECT 1 FROM sys.indexes
                     WHERE object_id = OBJECT_ID('vantrade_users')
                       AND name = '{idx}'
                )
                    DROP INDEX [{idx}] ON vantrade_users;
            """))

        # Drop new columns
        for col in ["phone_number", "firebase_uid", "phone_verified_at", "vt_user_id"]:
            conn.execute(text(f"""
                IF EXISTS (
                    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                     WHERE TABLE_NAME = 'vantrade_users'
                       AND COLUMN_NAME = '{col}'
                )
                    ALTER TABLE vantrade_users DROP COLUMN {col};
            """))

        conn.commit()
        print("✅ add_phone_auth rollback complete")
    return True
