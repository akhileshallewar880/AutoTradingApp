"""
Migration: Add admin users and token usage tracking
Adds three tables: vantrade_token_usage, vantrade_admin_users
Alters vantrade_users to add user_type column
"""

from sqlalchemy import text

def apply(engine):
    """Apply migration to add admin schema"""
    with engine.connect() as conn:
        # Create vantrade_token_usage table
        conn.execute(text("""
            IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'vantrade_token_usage')
            CREATE TABLE vantrade_token_usage (
                id INT IDENTITY(1,1) PRIMARY KEY,
                user_id INT NULL REFERENCES vantrade_users(user_id),
                analysis_id VARCHAR(50) NULL,
                model VARCHAR(50) NOT NULL DEFAULT 'gpt-5.4',
                prompt_tokens INT NOT NULL DEFAULT 0,
                completion_tokens INT NOT NULL DEFAULT 0,
                total_tokens INT NOT NULL DEFAULT 0,
                estimated_cost_usd DECIMAL(10,6) DEFAULT 0,
                created_at DATETIMEOFFSET DEFAULT GETUTCDATE(),
                INDEX idx_user_id (user_id),
                INDEX idx_created_at (created_at)
            );
        """))
        print("✓ Created vantrade_token_usage table")

        # Create vantrade_admin_users table
        conn.execute(text("""
            IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'vantrade_admin_users')
            CREATE TABLE vantrade_admin_users (
                id INT IDENTITY(1,1) PRIMARY KEY,
                username VARCHAR(50) UNIQUE NOT NULL,
                email VARCHAR(255) UNIQUE NOT NULL,
                password_hash VARCHAR(255) NOT NULL,
                is_active BIT NOT NULL DEFAULT 1,
                created_at DATETIMEOFFSET DEFAULT GETUTCDATE(),
                last_login DATETIMEOFFSET NULL
            );
        """))
        print("✓ Created vantrade_admin_users table")

        # Add user_type column to vantrade_users if it doesn't exist
        conn.execute(text("""
            IF NOT EXISTS (
                SELECT * FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'vantrade_users' AND COLUMN_NAME = 'user_type'
            )
            ALTER TABLE vantrade_users ADD user_type VARCHAR(10) NOT NULL DEFAULT 'USER';
        """))
        print("✓ Added user_type column to vantrade_users")

        conn.commit()
        print("✓ Admin schema migration completed successfully")


def rollback(engine):
    """Rollback migration by dropping new tables and column"""
    with engine.connect() as conn:
        # Drop tables if they exist
        conn.execute(text("""
            IF EXISTS (SELECT * FROM sys.tables WHERE name = 'vantrade_token_usage')
            DROP TABLE vantrade_token_usage;
        """))
        print("✓ Dropped vantrade_token_usage table")

        conn.execute(text("""
            IF EXISTS (SELECT * FROM sys.tables WHERE name = 'vantrade_admin_users')
            DROP TABLE vantrade_admin_users;
        """))
        print("✓ Dropped vantrade_admin_users table")

        # Drop user_type column from vantrade_users if it exists
        conn.execute(text("""
            IF EXISTS (
                SELECT * FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'vantrade_users' AND COLUMN_NAME = 'user_type'
            )
            ALTER TABLE vantrade_users DROP COLUMN user_type;
        """))
        print("✓ Dropped user_type column from vantrade_users")

        conn.commit()
        print("✓ Admin schema migration rolled back successfully")
