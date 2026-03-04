"""
Test script to verify Azure SQL database connection and table creation.
Run this BEFORE testing the app to ensure database is properly configured.

Usage:
    python test_database_connection.py
"""

import asyncio
import sys
from datetime import datetime
from pathlib import Path

# Add app to path
sys.path.insert(0, str(Path(__file__).parent))

from app.core.config import get_settings
from app.core.database import engine
from app.models.db_models import SQLModel
from app.core.logging import logger


async def test_database_connection():
    """Test database connection and table creation."""

    print("\n" + "=" * 70)
    print("🧪 VanTrade Database Connection Test")
    print("=" * 70 + "\n")

    # Step 1: Check configuration
    print("📋 Step 1: Checking Configuration...")
    try:
        settings = get_settings()
        print(f"   ✅ DB_SERVER: {settings.DB_SERVER}")
        print(f"   ✅ DB_NAME: {settings.DB_NAME}")
        print(f"   ✅ DB_USER: {settings.DB_USER}")
        print(f"   ✅ DB_DRIVER: {settings.DB_DRIVER}")
        print()
    except Exception as e:
        print(f"   ❌ Configuration error: {e}")
        return False

    # Step 2: Test connection
    print("📡 Step 2: Testing Database Connection...")
    try:
        connection = engine.connect()
        connection.close()
        print("   ✅ Connected to Azure SQL successfully!")
        print()
    except Exception as e:
        print(f"   ❌ Connection failed: {e}")
        print("   💡 Make sure:")
        print("      1. .env file has correct Azure SQL credentials")
        print("      2. Azure SQL server is running")
        print("      3. Network connectivity to Azure is working")
        print("      4. ODBC driver 17 is installed")
        return False

    # Step 3: Create tables
    print("🏗️  Step 3: Creating Database Tables...")
    try:
        SQLModel.metadata.create_all(engine)
        print("   ✅ All database tables created/verified!")
        print()
    except Exception as e:
        print(f"   ❌ Failed to create tables: {e}")
        return False

    # Step 4: Test basic operations
    print("✍️  Step 4: Testing Basic Database Operations...")
    try:
        from sqlmodel import Session, select
        from app.models.db_models import Analysis, AnalysisStatusEnum, User
        from decimal import Decimal

        # Test write - Create a test user first
        test_user_id = None
        with Session(engine) as session:
            test_user = User(
                zerodha_user_id=f"TEST_{int(datetime.utcnow().timestamp())}",
                email=f"test_{int(datetime.utcnow().timestamp())}@test.com",
                full_name="Test User",
                is_active=True,
                created_at=datetime.utcnow(),
            )
            session.add(test_user)
            session.flush()
            test_user_id = test_user.user_id
            session.commit()
            print(f"   ✅ Created test user: {test_user_id}")

        # Now create test analysis with valid user_id
        with Session(engine) as session:
            test_analysis = Analysis(
                # Don't set analysis_id - let it auto-generate
                user_id=test_user_id,
                analysis_date=datetime.utcnow(),
                status=AnalysisStatusEnum.COMPLETED,
                num_stocks_screened=5,
                hold_duration_days=0,  # Required field
                total_investment=Decimal("100000.00"),  # Required field
                max_profit=Decimal("5000.00"),  # Required field
                max_loss=Decimal("2000.00"),  # Required field
                result_json={"test": "data"},
                created_at=datetime.utcnow(),
                completed_at=datetime.utcnow(),
            )
            session.add(test_analysis)
            session.flush()  # Get the auto-generated ID
            test_id = test_analysis.analysis_id
            session.commit()
            print(f"   ✅ Created test analysis: {test_id}")

        # Test read
        with Session(engine) as session:
            statement = select(Analysis).where(Analysis.analysis_id == test_id)
            retrieved = session.exec(statement).first()
            if retrieved:
                print(f"   ✅ Retrieved test analysis successfully")
            else:
                print(f"   ❌ Failed to retrieve test analysis")
                return False

        # Test delete
        with Session(engine) as session:
            statement = select(Analysis).where(Analysis.analysis_id == test_id)
            to_delete = session.exec(statement).first()
            if to_delete:
                session.delete(to_delete)
                session.commit()
                print(f"   ✅ Deleted test analysis successfully")

        # Clean up test user
        with Session(engine) as session:
            statement = select(User).where(User.user_id == test_user_id)
            user_to_delete = session.exec(statement).first()
            if user_to_delete:
                session.delete(user_to_delete)
                session.commit()
                print(f"   ✅ Cleaned up test user successfully")
        print()

    except Exception as e:
        print(f"   ❌ Database operations failed: {e}")
        import traceback
        traceback.print_exc()
        return False

    # Success!
    print("=" * 70)
    print("✅ ALL TESTS PASSED - Database is ready!")
    print("=" * 70)
    print("\n📝 You can now:")
    print("   1. Run the backend: uvicorn app.main:app --reload")
    print("   2. Run the Flutter app")
    print("   3. Create an analysis and verify data is stored in Azure SQL")
    print("\n💾 Data will be stored in these tables:")
    print("   - Analysis, StockRecommendation, Signal")
    print("   - Order, GttOrder, ExecutionUpdate")
    print("   - Trade, OpenPosition")
    print("   - MonthlyPerformance, DailyPerformance")
    print()

    return True


if __name__ == "__main__":
    success = asyncio.run(test_database_connection())
    sys.exit(0 if success else 1)
