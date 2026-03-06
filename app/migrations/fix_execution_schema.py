"""
Migration: Fix execution schema
- Add quantity column to vantrade_stock_recommendations
- Replace update_details JSON with message/order_id/status/timestamp columns
  in vantrade_execution_updates
- Fix analysis_id type (int → varchar(36)) in child tables if not already done
"""

import pyodbc
import os

db_server = os.getenv("DB_SERVER") or os.getenv("DB_SERVER_PRODUCTION", "")
db_name = os.getenv("DB_NAME") or os.getenv("DB_NAME_PRODUCTION", "")
db_user = os.getenv("DB_USER") or os.getenv("DB_USER_PRODUCTION", "")
db_password = os.getenv("DB_PASSWORD") or os.getenv("DB_PASSWORD_PRODUCTION", "")


def _get_connection():
    if not all([db_server, db_name, db_user, db_password]):
        raise RuntimeError(
            "Missing database credentials. Set DB_SERVER, DB_NAME, DB_USER, DB_PASSWORD."
        )

    available_drivers = pyodbc.drivers()
    if "ODBC Driver 18 for SQL Server" in available_drivers:
        driver = "ODBC Driver 18 for SQL Server"
    elif "ODBC Driver 17 for SQL Server" in available_drivers:
        driver = "ODBC Driver 17 for SQL Server"
    else:
        raise RuntimeError(f"No SQL Server ODBC driver found. Available: {available_drivers}")

    conn_str = (
        f"DRIVER={{{driver}}};"
        f"SERVER={db_server};"
        f"DATABASE={db_name};"
        f"UID={db_user};"
        f"PWD={db_password};"
        "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
    )
    return pyodbc.connect(conn_str)


def migrate_up():
    """Apply schema fixes for execution pipeline."""
    conn = _get_connection()
    cursor = conn.cursor()

    try:
        # ── 1. Add quantity to vantrade_stock_recommendations ──────────────
        cursor.execute("""
            IF NOT EXISTS (
                SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'vantrade_stock_recommendations'
                  AND COLUMN_NAME = 'quantity'
            )
            ALTER TABLE vantrade_stock_recommendations
            ADD quantity INT NOT NULL DEFAULT 1
        """)
        print("✅ Added quantity column to vantrade_stock_recommendations")

        # ── 2. Fix vantrade_execution_updates ──────────────────────────────
        # Add message column
        cursor.execute("""
            IF NOT EXISTS (
                SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'vantrade_execution_updates'
                  AND COLUMN_NAME = 'message'
            )
            ALTER TABLE vantrade_execution_updates
            ADD message NVARCHAR(MAX) NULL
        """)

        # Add order_id column
        cursor.execute("""
            IF NOT EXISTS (
                SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'vantrade_execution_updates'
                  AND COLUMN_NAME = 'order_id'
            )
            ALTER TABLE vantrade_execution_updates
            ADD order_id NVARCHAR(255) NULL
        """)

        # Add status column
        cursor.execute("""
            IF NOT EXISTS (
                SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'vantrade_execution_updates'
                  AND COLUMN_NAME = 'status'
            )
            ALTER TABLE vantrade_execution_updates
            ADD status NVARCHAR(50) NULL
        """)

        # Add timestamp column
        cursor.execute("""
            IF NOT EXISTS (
                SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'vantrade_execution_updates'
                  AND COLUMN_NAME = 'timestamp'
            )
            ALTER TABLE vantrade_execution_updates
            ADD timestamp DATETIME2 NULL
        """)

        # Change update_type to NVARCHAR if it was an enum-restricted column
        # (Safe to run: only changes type, not data)
        cursor.execute("""
            IF EXISTS (
                SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'vantrade_execution_updates'
                  AND COLUMN_NAME = 'update_type'
                  AND DATA_TYPE NOT IN ('nvarchar', 'varchar')
            )
            ALTER TABLE vantrade_execution_updates
            ALTER COLUMN update_type NVARCHAR(100) NOT NULL
        """)

        print("✅ Updated vantrade_execution_updates schema")

        # ── 3. Fix analysis_id type in child tables (if still int) ─────────
        for table, col in [
            ("vantrade_stock_recommendations", "analysis_id"),
            ("vantrade_execution_updates", "analysis_id"),
            ("vantrade_orders", "analysis_id"),
        ]:
            cursor.execute(f"""
                IF EXISTS (
                    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                    WHERE TABLE_NAME = '{table}'
                      AND COLUMN_NAME = '{col}'
                      AND DATA_TYPE = 'int'
                )
                BEGIN
                    ALTER TABLE {table} ALTER COLUMN {col} NVARCHAR(36) NOT NULL
                    PRINT 'Fixed {table}.{col} int->varchar(36)'
                END
            """)

        print("✅ Verified analysis_id column types in child tables")

        conn.commit()
        print("✅ Migration fix_execution_schema applied successfully")

    except Exception as e:
        conn.rollback()
        print(f"❌ Migration failed: {e}")
        raise
    finally:
        cursor.close()
        conn.close()


def migrate_down():
    """Rollback: remove added columns (data will be lost)."""
    conn = _get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("""
            IF EXISTS (
                SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'vantrade_stock_recommendations' AND COLUMN_NAME = 'quantity'
            )
            ALTER TABLE vantrade_stock_recommendations DROP COLUMN quantity
        """)
        for col in ("message", "order_id", "status", "timestamp"):
            cursor.execute(f"""
                IF EXISTS (
                    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                    WHERE TABLE_NAME = 'vantrade_execution_updates' AND COLUMN_NAME = '{col}'
                )
                ALTER TABLE vantrade_execution_updates DROP COLUMN {col}
            """)
        conn.commit()
        print("✅ Rollback complete")
    except Exception as e:
        conn.rollback()
        raise
    finally:
        cursor.close()
        conn.close()
