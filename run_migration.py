#!/usr/bin/env python3
"""
Migration runner for VanTrade database schema updates.

Usage:
    python3 run_migration.py              # Run all pending migrations
    python3 run_migration.py rollback     # Rollback last migration
"""

import sys
import os

# Add project root to path
sys.path.insert(0, os.path.dirname(__file__))

from app.core.logging import logger
from app.migrations.make_analysis_user_optional import run_migration, rollback_migration


def main():
    """Run or rollback migrations based on command line arguments."""
    if len(sys.argv) > 1 and sys.argv[1] == "rollback":
        logger.info("=" * 70)
        logger.info("🔄 ROLLING BACK DATABASE MIGRATIONS")
        logger.info("=" * 70)
        try:
            rollback_migration()
            logger.info("=" * 70)
            logger.info("✅ ROLLBACK SUCCESSFUL")
            logger.info("=" * 70)
        except Exception as e:
            logger.error(f"❌ ROLLBACK FAILED: {e}")
            sys.exit(1)
    else:
        logger.info("=" * 70)
        logger.info("🚀 RUNNING DATABASE MIGRATIONS")
        logger.info("=" * 70)
        try:
            run_migration()
            logger.info("=" * 70)
            logger.info("✅ MIGRATIONS SUCCESSFUL")
            logger.info("=" * 70)
        except Exception as e:
            logger.error(f"❌ MIGRATIONS FAILED: {e}")
            sys.exit(1)


if __name__ == "__main__":
    main()
