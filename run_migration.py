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
from app.migrations.make_analysis_user_optional import (
    run_migration as run_optional,
    rollback_migration as rollback_optional,
)
from app.migrations.make_analysis_user_required import (
    run_migration as run_required,
    rollback_migration as rollback_required,
)


def main():
    """Run or rollback migrations based on command line arguments."""
    if len(sys.argv) > 1 and sys.argv[1] == "rollback":
        logger.info("=" * 70)
        logger.info("🔄 ROLLING BACK DATABASE MIGRATIONS")
        logger.info("=" * 70)
        try:
            # Rollback in reverse order
            rollback_required()
            rollback_optional()
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
            # Run migrations in order
            logger.info("\n📋 Migration 1/2: Make analysis.user_id optional")
            run_optional()
            logger.info("\n📋 Migration 2/2: Restore analysis.user_id as required")
            run_required()
            logger.info("=" * 70)
            logger.info("✅ MIGRATIONS SUCCESSFUL")
            logger.info("=" * 70)
        except Exception as e:
            logger.error(f"❌ MIGRATIONS FAILED: {e}")
            sys.exit(1)


if __name__ == "__main__":
    main()
