"""
Migration: Make analysis.user_id optional (nullable) and remove foreign key constraint.

This migration allows analyses to be saved without requiring a user record in the database.
Preserves all existing analysis data.

SQL Server syntax for Azure SQL Database.
"""

from sqlalchemy import text, inspect
from app.core.database import engine
from app.core.logging import logger


def get_foreign_key_name(table_name: str, column_name: str) -> str:
    """Get the name of the foreign key constraint for a column."""
    with engine.connect() as conn:
        inspector = inspect(engine)
        fks = inspector.get_foreign_keys(table_name)
        for fk in fks:
            if column_name in fk.get('constrained_columns', []):
                return fk.get('name', '')
    return None


def run_migration():
    """Execute the migration."""
    with engine.begin() as conn:
        try:
            logger.info("🔄 Starting migration: make analysis.user_id optional...")

            # Step 1: Drop the foreign key constraint if it exists
            logger.info("Step 1: Dropping foreign key constraint FK__vantrade___user___2F2FFC0C...")
            try:
                conn.execute(text("""
                    ALTER TABLE [dbo].[vantrade_analyses]
                    DROP CONSTRAINT [FK__vantrade___user___2F2FFC0C]
                """))
                logger.info("✅ Foreign key constraint dropped")
            except Exception as e:
                logger.warning(f"⚠️  Foreign key might not exist or different name: {e}")
                # Try alternative constraint name
                try:
                    conn.execute(text("""
                        SELECT CONSTRAINT_NAME
                        FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
                        WHERE TABLE_NAME = 'vantrade_analyses' AND COLUMN_NAME = 'user_id'
                        AND REFERENCED_TABLE_NAME = 'vantrade_users'
                    """))
                except:
                    pass

            # Step 2: Alter the user_id column to allow NULL
            logger.info("Step 2: Altering user_id column to allow NULL...")
            conn.execute(text("""
                ALTER TABLE [dbo].[vantrade_analyses]
                ALTER COLUMN [user_id] INT NULL
            """))
            logger.info("✅ Column altered successfully")

            # Step 3: Verify the change
            logger.info("Step 3: Verifying schema change...")
            result = conn.execute(text("""
                SELECT COLUMN_NAME, IS_NULLABLE, DATA_TYPE
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'vantrade_analyses' AND COLUMN_NAME = 'user_id'
            """))
            row = result.fetchone()
            if row:
                logger.info(f"✅ Column info: {row[0]} - Nullable: {row[1]} - Type: {row[2]}")

            # Step 4: Log summary
            result = conn.execute(text("""
                SELECT COUNT(*) as analysis_count FROM [dbo].[vantrade_analyses]
            """))
            count = result.fetchone()[0]
            logger.info(f"✅ Migration complete! Preserved {count} analysis records")

            return True

        except Exception as e:
            logger.error(f"❌ Migration failed: {e}", exc_info=True)
            raise


def rollback_migration():
    """Rollback the migration (restore foreign key constraint)."""
    with engine.begin() as conn:
        try:
            logger.info("🔄 Rolling back migration...")

            # Set user_id to NOT NULL (or set default value for existing NULLs first)
            conn.execute(text("""
                UPDATE [dbo].[vantrade_analyses]
                SET [user_id] = 1
                WHERE [user_id] IS NULL
            """))

            conn.execute(text("""
                ALTER TABLE [dbo].[vantrade_analyses]
                ALTER COLUMN [user_id] INT NOT NULL
            """))

            # Recreate foreign key
            conn.execute(text("""
                ALTER TABLE [dbo].[vantrade_analyses]
                ADD CONSTRAINT FK__vantrade___user___2F2FFC0C
                FOREIGN KEY ([user_id]) REFERENCES [dbo].[vantrade_users]([user_id])
            """))

            logger.info("✅ Rollback complete")
            return True

        except Exception as e:
            logger.error(f"❌ Rollback failed: {e}", exc_info=True)
            raise


if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1 and sys.argv[1] == "rollback":
        logger.info("Rolling back migration...")
        rollback_migration()
    else:
        logger.info("Running migration...")
        run_migration()
