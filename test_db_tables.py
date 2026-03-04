#!/usr/bin/env python3
"""
Quick test script to verify database tables exist and can be accessed.
"""

import sys
from sqlalchemy import inspect, text
from app.core.database import engine
from app.core.logging import logger

def check_tables():
    """Check if all required tables exist in the database."""
    try:
        inspector = inspect(engine)
        tables = inspector.get_table_names()

        logger.info("=" * 70)
        logger.info("🔍 DATABASE TABLE CHECK")
        logger.info("=" * 70)

        required_tables = [
            'vantrade_users',
            'vantrade_analyses',
            'vantrade_stock_recommendations',
            'vantrade_orders',
        ]

        logger.info(f"\n📋 Total tables found: {len(tables)}")
        logger.info(f"Tables: {sorted(tables)}\n")

        for table in required_tables:
            if table in tables:
                # Get row count
                with engine.connect() as conn:
                    result = conn.execute(text(f"SELECT COUNT(*) FROM [{table}]"))
                    count = result.scalar()
                logger.info(f"✅ {table}: EXISTS ({count} rows)")
            else:
                logger.info(f"❌ {table}: MISSING")

        logger.info("\n" + "=" * 70)

        # Try to insert a test user
        logger.info("Testing user creation...")
        from sqlmodel import Session, select
        from app.models.db_models import User

        with Session(engine) as session:
            # Check if test user already exists
            stmt = select(User).where(User.zerodha_user_id == "TEST_USER_12345")
            existing = session.exec(stmt).first()

            if not existing:
                test_user = User(
                    zerodha_user_id="TEST_USER_12345",
                    email="test@example.com",
                    full_name="Test User",
                    is_active=True
                )
                session.add(test_user)
                session.commit()
                session.refresh(test_user)
                logger.info(f"✅ Test user created: ID={test_user.user_id}")
            else:
                logger.info(f"ℹ️  Test user already exists: ID={existing.user_id}")

        logger.info("=" * 70)
        logger.info("✅ DATABASE CONNECTION & TABLES OK")
        logger.info("=" * 70)

    except Exception as e:
        logger.error("=" * 70)
        logger.error("❌ DATABASE ERROR")
        logger.error("=" * 70)
        logger.error(f"Error: {e}", exc_info=True)
        sys.exit(1)

if __name__ == "__main__":
    check_tables()
