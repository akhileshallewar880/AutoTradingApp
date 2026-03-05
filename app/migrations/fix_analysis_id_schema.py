"""
Migration: Fix Analysis.analysis_id schema
- Change analysis_id from INT to VARCHAR (UUID string)
- Make user_id nullable (analyses can exist without users)

This fixes the error: "Conversion failed when converting the varchar value
'fdf356a2-14e8-4dcc-b705-b30a0f31e790' to data type int"
"""

import pyodbc
from app.core.config import get_settings
from app.core.logging import logger

settings = get_settings()


def migrate_up():
    """Apply migration: Change analysis_id to VARCHAR, make user_id nullable."""
    conn_string = (
        f"Driver={{ODBC Driver 17 for SQL Server}};"
        f"Server={settings.DB_SERVER};"
        f"Database={settings.DB_NAME};"
        f"UID={settings.DB_USER};"
        f"PWD={settings.DB_PASSWORD};"
    )

    try:
        with pyodbc.connect(conn_string) as conn:
            cursor = conn.cursor()

            # Step 1: Drop foreign key constraint on user_id
            logger.info("Dropping foreign key constraint on user_id...")
            try:
                cursor.execute("""
                    ALTER TABLE vantrade_analyses
                    DROP CONSTRAINT FK_vantrade_analyses_user_id
                """)
                logger.info("✓ Foreign key dropped")
            except Exception as e:
                logger.warning(f"Could not drop FK (may not exist): {e}")

            # Step 2: Make user_id nullable (change column definition)
            logger.info("Making user_id nullable...")
            cursor.execute("""
                ALTER TABLE vantrade_analyses
                ALTER COLUMN user_id INT NULL
            """)
            logger.info("✓ user_id is now nullable")

            # Step 3: Recreate analysis_id as VARCHAR
            # This is complex in SQL Server, so we'll:
            # - Create temp column with data
            # - Drop old analysis_id
            # - Rename temp to analysis_id

            logger.info("Converting analysis_id from INT to VARCHAR...")

            # Add temp column as VARCHAR
            cursor.execute("""
                ALTER TABLE vantrade_analyses
                ADD analysis_id_temp VARCHAR(36) NULL
            """)
            logger.info("✓ Temp column created")

            # Copy existing INT IDs as strings (if any exist)
            cursor.execute("""
                UPDATE vantrade_analyses
                SET analysis_id_temp = CAST(analysis_id AS VARCHAR(36))
                WHERE analysis_id IS NOT NULL
            """)
            logger.info("✓ Data copied to temp column")

            # Drop primary key
            cursor.execute("""
                ALTER TABLE vantrade_analyses
                DROP CONSTRAINT PK_vantrade_analyses
            """)
            logger.info("✓ Primary key dropped")

            # Drop old analysis_id
            cursor.execute("""
                ALTER TABLE vantrade_analyses
                DROP COLUMN analysis_id
            """)
            logger.info("✓ Old analysis_id dropped")

            # Rename temp to analysis_id
            cursor.execute("""
                EXEC sp_rename 'vantrade_analyses.analysis_id_temp', 'analysis_id'
            """)
            logger.info("✓ Temp column renamed to analysis_id")

            # Set as primary key
            cursor.execute("""
                ALTER TABLE vantrade_analyses
                ADD PRIMARY KEY (analysis_id)
            """)
            logger.info("✓ Primary key added (analysis_id VARCHAR)")

            # Re-create foreign key on user_id
            logger.info("Recreating foreign key on user_id...")
            cursor.execute("""
                ALTER TABLE vantrade_analyses
                ADD CONSTRAINT FK_vantrade_analyses_user_id
                FOREIGN KEY (user_id) REFERENCES vantrade_users(user_id)
                ON DELETE SET NULL
            """)
            logger.info("✓ Foreign key recreated (with ON DELETE SET NULL)")

            conn.commit()
            logger.info("\n✅ Migration applied successfully!")
            logger.info("Summary:")
            logger.info("  • analysis_id: INT → VARCHAR(36)")
            logger.info("  • user_id: NOT NULL → NULL")

    except Exception as e:
        logger.error(f"❌ Migration failed: {e}")
        raise


def migrate_down():
    """Rollback migration (not recommended - data loss risk)."""
    logger.warning("⚠️  Rollback is not recommended (UUID → INT conversion loses data)")
    logger.warning("If you need to rollback, restore from backup and re-apply migrations")
    raise RuntimeError("Rollback not supported for this migration")


if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1 and sys.argv[1] == "rollback":
        migrate_down()
    else:
        migrate_up()
