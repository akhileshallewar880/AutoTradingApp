# Migration Guide: JSON Storage → Azure SQL

## What Changed

The app now uses **Azure SQL database for persistent storage** instead of local JSON files.

### Updated Files (NOT COMMITTED - Test Locally First)
- ✅ `app/storage/database.py` - Completely rewritten to use SQLModel + Azure SQL
- ✅ `test_database_connection.py` - Test script to verify database setup

### Before (JSON Fallback)
```
Data Flow: Analysis → app/storage/database.py → JSON file (data/trades.json)
Problem: Data lost after server restart, silent failures
```

### After (Azure SQL)
```
Data Flow: Analysis → app/storage/database.py → SQLModel → Azure SQL
Benefit: Persistent storage, proper logging, transaction support
```

---

## Step-by-Step Testing Guide

### Phase 1: Prepare Environment

**1. Verify .env has Azure SQL credentials:**
```bash
cat .env | grep DB_
# Should output:
# DB_SERVER=<your-server>.database.windows.net
# DB_NAME=vantrade_db
# DB_USER=<username>
# DB_PASSWORD=<password>
# DB_DRIVER=ODBC Driver 17 for SQL Server
```

**2. Verify ODBC Driver is installed:**
```bash
# macOS
brew list | grep odbc

# Linux (Ubuntu/Debian)
apt list --installed | grep odbc

# Windows
odbcad32.exe  # Opens ODBC Data Source Administrator
```

**3. Install dependencies (if needed):**
```bash
pip install sqlmodel sqlalchemy[mssql] pyodbc
```

---

### Phase 2: Test Database Connection

**Run the test script:**
```bash
cd /Users/akhileshallewar/project_dev/AutoTradingApp
python test_database_connection.py
```

**Expected output:**
```
======================================================================
🧪 VanTrade Database Connection Test
======================================================================

📋 Step 1: Checking Configuration...
   ✅ DB_SERVER: vanyatradbserver.database.windows.net
   ✅ DB_NAME: vantrade_db
   ✅ DB_USER: vandba
   ✅ DB_DRIVER: ODBC Driver 17 for SQL Server

📡 Step 2: Testing Database Connection...
   ✅ Connected to Azure SQL successfully!

🏗️  Step 3: Creating Database Tables...
   ✅ All database tables created/verified!

✍️  Step 4: Testing Basic Database Operations...
   ✅ Created test analysis: TEST_2026-03-04T12:34:56.789123
   ✅ Retrieved test analysis successfully
   ✅ Deleted test analysis successfully

======================================================================
✅ ALL TESTS PASSED - Database is ready!
======================================================================
```

**If test fails:**

| Error | Solution |
|-------|----------|
| `Connection refused` | Check .env credentials, verify Azure SQL server is accessible |
| `ODBC driver not found` | Install ODBC Driver 17 for SQL Server |
| `Authentication failed` | Verify username includes @servername suffix |
| `Database not found` | Create database `vantrade_db` in Azure SQL |
| `Table creation failed` | Ensure user has CREATE TABLE permissions |

---

### Phase 3: Test the App Locally

**1. Start backend:**
```bash
cd app
uvicorn main:app --reload
```

**Expected logs:**
```
✅ Using Azure SQL database for persistent storage
✅ Creating database tables if they don't exist...
✅ Database tables verified/created successfully
```

**2. Run analysis:**
- Create new analysis in Flutter app
- App should return results normally
- No errors in console

**3. Verify data persistence:**
- Refresh dashboard
- Analysis should still appear (it's in the database now!)
- Create another analysis
- Both should appear together

**4. Check database directly (optional):**
```bash
# Using sqlcmd (if installed)
sqlcmd -S your-server.database.windows.net -U vandba -d vantrade_db

# In SQL:
SELECT COUNT(*) as analysis_count FROM Analysis;
SELECT COUNT(*) as recommendation_count FROM StockRecommendation;
SELECT * FROM Analysis ORDER BY created_at DESC;
```

---

## Database Schema

### Tables Used for Persistence

**Analysis & Recommendations:**
- `Analysis` - AI analysis requests
- `StockRecommendation` - Individual stock recommendations per analysis
- `ExecutionUpdate` - Real-time order execution updates

**Trades & Orders:**
- `Trade` - Completed trades with P&L
- `Order` - Trade orders placed
- `GttOrder` - Good-Till-Triggered orders

**Performance:**
- `MonthlyPerformance` - Monthly aggregated metrics
- `DailyPerformance` - Daily aggregated metrics

**Other:**
- `OpenPosition` - Active positions
- `Signal` - Technical indicator signals
- `User`, `Session`, `ApiCredential` - User management
- `AuditLog`, `ApiCallLog`, `ErrorLog` - Logging tables

---

## Testing Checklist

- [ ] `.env` has correct Azure SQL credentials
- [ ] ODBC Driver 17 installed and working
- [ ] `test_database_connection.py` passes all 4 tests
- [ ] Backend starts without errors
- [ ] Can create new analysis
- [ ] Analysis results appear (with stocks listed)
- [ ] Analysis history persists after page refresh
- [ ] Multiple analyses can be viewed together
- [ ] No JSON files in `data/` directory (no fallback)
- [ ] Logs show database operations (✅ Analysis persisted to SQL)

---

## What If Something Goes Wrong?

### No data appearing after analysis:

**Check logs for:**
```
✅ Analysis persisted to SQL: ANALYSIS_ID_123 with 5 stocks
```

If not present:
1. Verify database connection test passed
2. Check Azure SQL user has INSERT permission
3. Check database name is correct in .env

### "Cannot import app.storage.database" error:

The new database.py has different imports. Make sure:
```python
# ✅ These should work:
from app.models.db_models import Analysis, StockRecommendation
from app.core.database import engine
from sqlmodel import Session, select
```

### Connection timeout errors:

1. Check firewall allows connection from your IP
2. Verify connection string format
3. Test with Azure Data Studio:
   ```
   Server: your-server.database.windows.net
   Database: vantrade_db
   Authentication: SQL Login
   Username: username@servername
   Password: your-password
   ```

---

## Code Changes Summary

### Old Implementation (JSON)
```python
class Database:
    def __init__(self):
        self._trades = []  # In-memory list
        self._analyses = {}  # In-memory dict

    async def save_analysis(self, analysis):
        self._analyses[analysis.analysis_id] = analysis.model_dump()
        await self._save()  # Writes to JSON file
```

**Problems:**
- Data lost on restart
- Silent failures
- No proper error handling
- No query capability

### New Implementation (Azure SQL)
```python
class Database:
    def __init__(self):
        SQLModel.metadata.create_all(engine)  # Creates tables

    async def save_analysis(self, analysis):
        with Session(engine) as session:
            db_analysis = Analysis(...)
            session.add(db_analysis)
            session.commit()  # Persists to SQL
```

**Benefits:**
- ✅ Persistent storage
- ✅ ACID transactions
- ✅ Proper error handling
- ✅ Query capabilities
- ✅ Scalable for multiple users
- ✅ Built-in backup/recovery

---

## Rollback Plan (If Needed)

If you need to revert to JSON storage:

```bash
# Restore old database.py
git checkout HEAD -- app/storage/database.py

# Or download from backup:
# https://github.com/your-repo/commits/old-database-backup
```

The improved logging version (with JSON) is still in git history.

---

## Next Steps After Testing

Once local testing passes:

1. **Commit the changes:**
   ```bash
   git add app/storage/database.py test_database_connection.py MIGRATE_TO_AZURE_SQL.md
   git commit -m "Migrate from JSON storage to Azure SQL database"
   ```

2. **Deploy to production:**
   - Update server .env with Azure SQL credentials
   - Run backend
   - Data will persist in production

3. **Monitor:** Watch logs for "✅ Analysis persisted to SQL"

---

## Performance Expectations

| Operation | JSON | Azure SQL |
|-----------|------|-----------|
| Save Analysis | 10-50ms | 50-100ms |
| Retrieve Analysis | 5-20ms | 50-150ms |
| List 50 Analyses | 20-50ms | 100-300ms |
| Concurrent users | 1 | Unlimited |
| Data persistence | ❌ Lost | ✅ Persistent |
| Query capability | ❌ No | ✅ Yes (SQL) |

---

## Support

If you encounter issues:

1. Check `test_database_connection.py` output
2. Review logs for error messages
3. Verify `.env` credentials
4. Check Azure SQL firewall rules
5. Ensure ODBC driver is installed

**Common Azure SQL resources:**
- Azure Portal: https://portal.azure.com
- ODBC Drivers: https://docs.microsoft.com/sql/connect/odbc/
- Troubleshooting: Check Azure SQL firewall, user permissions, network connectivity

---

## Summary

✅ **What's Ready:**
- SQLModel database layer (app/storage/database.py)
- Test script (test_database_connection.py)
- This migration guide

⏳ **What You Need to Do:**
1. Run `test_database_connection.py` locally
2. Verify all tests pass
3. Test the app locally with real analysis
4. Confirm data persists in Azure SQL
5. Commit changes when satisfied

🚀 **After Testing:**
- The app will use Azure SQL for all data storage
- No more JSON file fallback
- Proper error handling and logging
- Ready for production deployment
