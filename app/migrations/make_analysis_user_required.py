"""
Migration: Restore user_id as required (NOT NULL) and add foreign key constraint.

This migration restores the foreign key constraint on analysis.user_id now that:
1. Users are created in vantrade_users table on login
2. Analysis requests include user_id from the authenticated user
3. All analyses will have a valid user_id

SQL Server syntax for Azure SQL Database.
"""

from sqlalchemy import text
from app.core.database import engine
from app.core.logging import logger


def run_migration():
    """Execute the migration."""
    with engine.begin() as conn:
        try:
            logger.info("🔄 Starting migration: restore analysis.user_id as required...")

            # Step 1: Check if any NULL user_id values exist
            logger.info("Step 1: Checking for NULL user_id values...")
            result = conn.execute(text("""
                SELECT COUNT(*) as null_count FROM [dbo].[vantrade_analyses]
                WHERE [user_id] IS NULL
            """))
            null_count = result.fetchone()[0]

            if null_count > 0:
                logger.warning(
                    f"⚠️  Found {null_count} analyses with NULL user_id. "
                    f"These records will be deleted during migration."
                )
                # Delete analyses with NULL user_id
                conn.execute(text("""
                    DELETE FROM [dbo].[vantrade_stock_recommendations]
                    WHERE [analysis_id] IN (
                        SELECT [analysis_id] FROM [dbo].[vantrade_analyses]
                        WHERE [user_id] IS NULL
                    )
                """))
                conn.execute(text("""
                    DELETE FROM [dbo].[vantrade_analyses]
                    WHERE [user_id] IS NULL
                """))
                logger.info(f"✅ Deleted {null_count} analyses with NULL user_id")

            # Step 2: Alter column to NOT NULL
            logger.info("Step 2: Altering user_id column to NOT NULL...")
            conn.execute(text("""
                ALTER TABLE [dbo].[vantrade_analyses]
                ALTER COLUMN [user_id] INT NOT NULL
            """))
            logger.info("✅ Column altered to NOT NULL")

            # Step 3: Add foreign key constraint
            logger.info("Step 3: Adding foreign key constraint...")
            conn.execute(text("""
                ALTER TABLE [dbo].[vantrade_analyses]
                ADD CONSTRAINT FK_analyses_users
                FOREIGN KEY ([user_id]) REFERENCES [dbo].[vantrade_users]([user_id])
            """))
            logger.info("✅ Foreign key constraint added")

            # Step 4: Verify the change
            logger.info("Step 4: Verifying schema change...")
            result = conn.execute(text("""
                SELECT COLUMN_NAME, IS_NULLABLE, DATA_TYPE
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'vantrade_analyses' AND COLUMN_NAME = 'user_id'
            """))
            row = result.fetchone()
            if row:
                logger.info(f"✅ Column info: {row[0]} - Nullable: {row[1]} - Type: {row[2]}")

            # Step 5: Verify foreign key
            result = conn.execute(text("""
                SELECT COUNT(*) as fk_count
                FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
                WHERE TABLE_NAME = 'vantrade_analyses'
                AND CONSTRAINT_TYPE = 'FOREIGN KEY'
            """))
            fk_count = result.fetchone()[0]
            logger.info(f"✅ Foreign key constraints: {fk_count}")

            logger.info("✅ Migration complete!")
            return True

        except Exception as e:
            logger.error(f"❌ Migration failed: {e}", exc_info=True)
            raise


def rollback_migration():
    """Rollback the migration."""
    with engine.begin() as conn:
        try:
            logger.info("🔄 Rolling back migration...")

            # Drop foreign key
            conn.execute(text("""
                ALTER TABLE [dbo].[vantrade_analyses]
                DROP CONSTRAINT FK_analyses_users
            """))

            # Set column to nullable
            conn.execute(text("""
                ALTER TABLE [dbo].[vantrade_analyses]
                ALTER COLUMN [user_id] INT NULL
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
