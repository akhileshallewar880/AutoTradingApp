#!/usr/bin/env python3
"""
Migration runner for VanTrade database schema updates.

Usage:
    python3 run_migration.py              # Run all pending migrations
    python3 run_migration.py rollback     # Rollback last migration
    python3 run_migration.py fix_analysis_id_schema  # Run specific migration
"""

import sys
import os

# Add project root to path
sys.path.insert(0, os.path.dirname(__file__))

# Simple logger that doesn't require app config (avoids needing OPENAI_API_KEY, ENCRYPTION_KEY)
class SimpleLogger:
    def info(self, msg):
        print(f"ℹ️  {msg}")
    def warning(self, msg):
        print(f"⚠️  {msg}")
    def error(self, msg, exc_info=False):
        print(f"❌ {msg}")
        if exc_info:
            import traceback
            traceback.print_exc()

logger = SimpleLogger()

# Import all available migrations
try:
    from app.migrations.make_analysis_user_optional import (
        run_migration as run_optional,
        rollback_migration as rollback_optional,
    )
except ImportError:
    run_optional = None
    rollback_optional = None

try:
    from app.migrations.make_analysis_user_required import (
        run_migration as run_required,
        rollback_migration as rollback_required,
    )
except ImportError:
    run_required = None
    rollback_required = None

try:
    from app.migrations.admin_schema import (
        apply as apply_admin,
        rollback as rollback_admin,
    )
except ImportError:
    apply_admin = None
    rollback_admin = None

try:
    from app.migrations.fix_analysis_id_schema import (
        migrate_up as migrate_analysis_id_up,
        migrate_down as migrate_analysis_id_down,
    )
except ImportError:
    migrate_analysis_id_up = None
    migrate_analysis_id_down = None

try:
    from app.migrations.fix_execution_schema import (
        migrate_up as migrate_execution_up,
        migrate_down as migrate_execution_down,
    )
except ImportError:
    migrate_execution_up = None
    migrate_execution_down = None

try:
    from app.migrations.add_daily_pnl_records import apply as apply_daily_pnl
except ImportError:
    apply_daily_pnl = None

try:
    from app.migrations.swing_expiry_trigger import run as run_swing_expiry
except ImportError:
    run_swing_expiry = None


def main():
    """Run or rollback migrations based on command line arguments."""
    # Get migration name from args
    migration_name = sys.argv[1] if len(sys.argv) > 1 else None
    action = sys.argv[2] if len(sys.argv) > 2 else None

    # Handle specific migration
    if migration_name and migration_name != "rollback":
        logger.info("=" * 70)
        logger.info(f"🚀 RUNNING MIGRATION: {migration_name}")
        logger.info("=" * 70)
        try:
            if migration_name == "admin_schema":
                from app.core.database import engine
                if apply_admin:
                    apply_admin(engine)
                    logger.info("=" * 70)
                    logger.info("✅ ADMIN SCHEMA MIGRATION SUCCESSFUL")
                    logger.info("=" * 70)
                else:
                    logger.error("❌ admin_schema migration not found")
                    sys.exit(1)
            elif migration_name == "fix_analysis_id_schema":
                if migrate_analysis_id_up:
                    migrate_analysis_id_up()
                    logger.info("=" * 70)
                    logger.info("✅ ANALYSIS_ID SCHEMA MIGRATION SUCCESSFUL")
                    logger.info("=" * 70)
                else:
                    logger.error("❌ fix_analysis_id_schema migration not found")
                    sys.exit(1)
            elif migration_name == "fix_execution_schema":
                if migrate_execution_up:
                    migrate_execution_up()
                    logger.info("=" * 70)
                    logger.info("✅ EXECUTION SCHEMA MIGRATION SUCCESSFUL")
                    logger.info("=" * 70)
                else:
                    logger.error("❌ fix_execution_schema migration not found")
                    sys.exit(1)
            elif migration_name == "add_daily_pnl_records":
                from app.core.database import engine
                if apply_daily_pnl:
                    apply_daily_pnl(engine)
                    logger.info("=" * 70)
                    logger.info("✅ DAILY PNL RECORDS MIGRATION SUCCESSFUL")
                    logger.info("=" * 70)
                else:
                    logger.error("❌ add_daily_pnl_records migration not found")
                    sys.exit(1)
            elif migration_name == "swing_expiry_trigger":
                if run_swing_expiry:
                    success = run_swing_expiry()
                    if success:
                        logger.info("=" * 70)
                        logger.info("✅ SWING EXPIRY TRIGGER MIGRATION SUCCESSFUL")
                        logger.info("=" * 70)
                    else:
                        logger.error("❌ swing_expiry_trigger migration failed")
                        sys.exit(1)
                else:
                    logger.error("❌ swing_expiry_trigger migration not found")
                    sys.exit(1)
            else:
                logger.error(f"❌ Unknown migration: {migration_name}")
                sys.exit(1)
        except Exception as e:
            logger.error(f"❌ MIGRATION FAILED: {e}", exc_info=True)
            sys.exit(1)

    # Handle rollback for specific migration
    elif migration_name == "rollback" and action:
        logger.info("=" * 70)
        logger.info(f"🔄 ROLLING BACK: {action}")
        logger.info("=" * 70)
        try:
            if action == "admin_schema":
                from app.core.database import engine
                if rollback_admin:
                    rollback_admin(engine)
                    logger.info("=" * 70)
                    logger.info("✅ ADMIN SCHEMA ROLLBACK SUCCESSFUL")
                    logger.info("=" * 70)
                else:
                    logger.error("❌ admin_schema rollback not found")
                    sys.exit(1)
            elif action == "fix_analysis_id_schema":
                if migrate_analysis_id_down:
                    migrate_analysis_id_down()
                    logger.info("=" * 70)
                    logger.info("✅ ANALYSIS_ID SCHEMA ROLLBACK SUCCESSFUL")
                    logger.info("=" * 70)
                else:
                    logger.error("❌ fix_analysis_id_schema rollback not found")
                    sys.exit(1)
            elif action == "fix_execution_schema":
                if migrate_execution_down:
                    migrate_execution_down()
                    logger.info("=" * 70)
                    logger.info("✅ EXECUTION SCHEMA ROLLBACK SUCCESSFUL")
                    logger.info("=" * 70)
                else:
                    logger.error("❌ fix_execution_schema rollback not found")
                    sys.exit(1)
            else:
                logger.error(f"❌ Unknown migration: {action}")
                sys.exit(1)
        except Exception as e:
            logger.error(f"❌ ROLLBACK FAILED: {e}", exc_info=True)
            sys.exit(1)

    # Handle default (run all old migrations)
    else:
        logger.info("=" * 70)
        logger.info("🚀 RUNNING DEFAULT MIGRATIONS")
        logger.info("=" * 70)
        try:
            if run_optional:
                logger.info("\n📋 Migration 1/2: Make analysis.user_id optional")
                run_optional()
            if run_required:
                logger.info("\n📋 Migration 2/2: Restore analysis.user_id as required")
                run_required()
            logger.info("=" * 70)
            logger.info("✅ MIGRATIONS SUCCESSFUL")
            logger.info("=" * 70)
        except Exception as e:
            logger.error(f"❌ MIGRATIONS FAILED: {e}", exc_info=True)
            sys.exit(1)


if __name__ == "__main__":
    main()
