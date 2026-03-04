# Database Implementation Guide - VanTrade
## Step-by-Step Execution Plan

---

## 📋 Quick Summary of What We're Building

| Component | Purpose | Tables | Timeline |
|-----------|---------|--------|----------|
| **Phase 1** | Core user & session management | Users, ApiCredentials, Sessions | Week 1 |
| **Phase 2** | Analyses & order tracking | Analyses, Orders, GttOrders, ExecutionUpdates | Week 2-3 |
| **Phase 3** | Performance metrics & analytics | Trades, MonthlyPerformance, DailyPerformance | Week 3-4 |
| **Audit** | Logging & compliance | AuditLogs, ErrorLogs, ApiCallLogs | All phases |

---

## 🔧 PHASE 1: Core Infrastructure Setup (Week 1)

### Step 1.1 — Prepare Azure SQL Database

**If you don't have the connection string yet:**

1. Go to [Azure Portal](https://portal.azure.com)
2. Create SQL Database (if not already done)
3. Copy connection string from "Connection strings" section
4. Format: `Server=tcp:vantrade.database.windows.net,1433;Initial Catalog=VanTradeDB;Persist Security Info=False;User ID=tradingadmin;Password=YourPassword;Encrypt=True;Connection Timeout=30;`

**Test connectivity:**
```bash
# Install ODBC driver (macOS)
brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release
brew install msodbcsql17

# On Linux (Ubuntu)
sudo apt-get install msodbcsql17

# Test connection
sqlcmd -S vantrade.database.windows.net -U tradingadmin -P 'YourPassword' -d VanTradeDB -Q "SELECT 1"
```

### Step 1.2 — Update Dependencies

**File: [algotrading/pubspec.yaml](algotrading/pubspec.yaml)** (no changes needed - Flutter side)

**File: [app/requirements.txt](app/requirements.txt)** - Add database dependencies:

```bash
# Current dependencies + NEW:

sqlmodel==0.0.14
sqlalchemy==2.0.23
sqlalchemy-utils==0.41.1
alembic==1.12.1
pyodbc==5.0.1
cryptography==41.0.7
python-dotenv==1.0.0

# For async operations (optional but recommended):
sqlalchemy[asyncio]==2.0.23
aiosqlite==0.19.0
```

**Install:**
```bash
cd /Users/akhileshallewar/project_dev/AutoTradingApp
pip install -r app/requirements.txt
```

### Step 1.3 — Create Configuration

**File: [app/core/config.py](app/core/config.py)** - Add database settings:

```python
from pydantic_settings import BaseSettings, SettingsConfigDict
from functools import lru_cache
from typing import Optional

class Settings(BaseSettings):
    # Existing settings
    APP_NAME: str = "Agentic AI Trading Backend"
    DEBUG: bool = False

    # Zerodha Kite Connect Config
    ZERODHA_API_KEY: str
    ZERODHA_API_SECRET: str
    ZERODHA_ACCESS_TOKEN: Optional[str] = None

    # OpenAI Config
    OPENAI_API_KEY: str
    OPENAI_MODEL: str = "gpt-4o"

    # Trading Config
    DEFAULT_TIMEFRAME: str = "day"
    DEFAULT_RISK_PERCENT: float = 1.0

    # ===== NEW: Database Configuration =====
    # Azure SQL Database
    DB_SERVER: str  # e.g., "vantrade.database.windows.net"
    DB_USER: str    # e.g., "tradingadmin"
    DB_PASSWORD: str
    DB_NAME: str = "VanTradeDB"
    DB_DRIVER: str = "ODBC Driver 17 for SQL Server"
    DB_POOL_SIZE: int = 20
    DB_MAX_OVERFLOW: int = 10

    # Encryption for sensitive data
    ENCRYPTION_KEY: str  # Fernet key - generate with: from cryptography.fernet import Fernet; Fernet.generate_key()

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )

@lru_cache()
def get_settings():
    return Settings()
```

### Step 1.4 — Update .env File

**File: [.env](app/.env)** - Add database variables:

```bash
# Existing variables
ZERODHA_API_KEY=your_api_key
ZERODHA_API_SECRET=your_api_secret
OPENAI_API_KEY=your_openai_key

# ===== NEW: Database Configuration =====
DB_SERVER=vantrade.database.windows.net
DB_USER=tradingadmin
DB_PASSWORD=YourSecurePassword123!
DB_NAME=VanTradeDB

# Generate encryption key:
# python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
ENCRYPTION_KEY=your_generated_fernet_key_here
```

### Step 1.5 — Create Database Module

**File: [app/core/database.py](app/core/database.py)** - NEW:

```python
"""
Database configuration and connection management for VanTrade.
Uses SQLModel (Pydantic + SQLAlchemy) for type-safe ORM.
"""

from sqlmodel import create_engine, Session, SQLModel
from sqlalchemy.pool import QueuePool
from sqlalchemy.orm import sessionmaker
from app.core.config import get_settings
from app.core.logging import logger
from typing import Generator

settings = get_settings()

# Build connection string for Azure SQL
DATABASE_URL = (
    f"mssql+pyodbc://{settings.DB_USER}:{settings.DB_PASSWORD}"
    f"@{settings.DB_SERVER}/{settings.DB_NAME}"
    f"?driver={settings.DB_DRIVER.replace(' ', '+')}"
)

logger.info(f"Connecting to database: {settings.DB_SERVER}/{settings.DB_NAME}")

# Create engine with connection pooling
engine = create_engine(
    DATABASE_URL,
    poolclass=QueuePool,
    pool_size=settings.DB_POOL_SIZE,
    max_overflow=settings.DB_MAX_OVERFLOW,
    pool_pre_ping=True,  # Test connections before using
    pool_recycle=3600,   # Recycle connections every hour
    echo=False,          # Set to True for SQL debug logging
)

# Session maker for synchronous operations
SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
    class_=Session
)

def get_session() -> Generator[Session, None, None]:
    """Dependency for FastAPI routes to get DB session."""
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()

def init_db():
    """Initialize database tables from SQLModel definitions."""
    try:
        # Import models to ensure they're registered
        from app.models.db_models import (
            User, ApiCredential, Session as DbSession,
            Analysis, StockRecommendation, Signal,
            Order, GttOrder, ExecutionUpdate,
            Trade, OpenPosition,
            MonthlyPerformance, DailyPerformance,
            AuditLog, ApiCallLog, ErrorLog
        )

        # Create all tables
        SQLModel.metadata.create_all(engine)
        logger.info("✓ Database tables initialized successfully")
    except Exception as e:
        logger.error(f"✗ Failed to initialize database: {e}")
        raise

def close_db():
    """Close all database connections."""
    engine.dispose()
    logger.info("✓ Database connections closed")
```

### Step 1.6 — Create Database Models

**File: [app/models/db_models.py](app/models/db_models.py)** - NEW (550+ lines):

```python
"""
SQLModel database models for VanTrade trading platform.
These models define the database schema and provide type-safe ORM.
"""

from sqlmodel import SQLModel, Field, Relationship
from typing import Optional, List
from datetime import datetime
import json

# ==================== USER MANAGEMENT ====================

class User(SQLModel, table=True):
    __tablename__ = "Users"

    user_id: str = Field(primary_key=True, description="Unique user ID")
    zerodha_user_id: str = Field(index=True, unique=True)
    email: str = Field(index=True, unique=True)
    full_name: Optional[str] = None
    user_type: Optional[str] = None  # 'individual', 'huf', 'partnership'
    broker: str = "zerodha"
    is_active: bool = Field(default=True)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
    last_login: Optional[datetime] = None

    # Relationships
    api_credentials: List["ApiCredential"] = Relationship(back_populates="user")
    sessions: List["Session"] = Relationship(back_populates="user")
    analyses: List["Analysis"] = Relationship(back_populates="user")
    orders: List["Order"] = Relationship(back_populates="user")
    trades: List["Trade"] = Relationship(back_populates="user")

class ApiCredential(SQLModel, table=True):
    __tablename__ = "ApiCredentials"

    credential_id: Optional[int] = Field(default=None, primary_key=True)
    user_id: str = Field(foreign_key="Users.user_id", index=True)
    access_token: str  # Encrypted
    request_token: Optional[str] = None  # Encrypted
    api_key: Optional[str] = None  # Encrypted
    api_secret: Optional[str] = None  # Encrypted
    exchanges: Optional[str] = None  # JSON: ['NSE', 'BSE']
    products: Optional[str] = None  # JSON: ['MIS', 'CNC']
    is_valid: bool = Field(default=True, index=True)
    expires_at: Optional[datetime] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

    # Relationships
    user: Optional[User] = Relationship(back_populates="api_credentials")

class Session(SQLModel, table=True):
    __tablename__ = "Sessions"

    session_id: str = Field(primary_key=True)
    user_id: str = Field(foreign_key="Users.user_id", index=True)
    credential_id: Optional[int] = Field(foreign_key="ApiCredentials.credential_id")
    access_token: str  # Current session token
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    last_activity: datetime = Field(default_factory=datetime.utcnow)
    expires_at: Optional[datetime] = None
    is_active: bool = Field(default=True, index=True)

    # Relationships
    user: Optional[User] = Relationship(back_populates="sessions")

# ==================== ANALYSIS & SIGNALS ====================

class Analysis(SQLModel, table=True):
    __tablename__ = "Analyses"

    analysis_id: str = Field(primary_key=True)
    user_id: str = Field(foreign_key="Users.user_id", index=True)
    analysis_date: datetime = Field(index=True)
    hold_duration_days: int = Field(default=0, ge=0)
    sectors: Optional[str] = None  # JSON
    num_stocks: int
    available_balance: float
    risk_percent: float
    status: str = Field(default="PENDING_CONFIRMATION", index=True)  # PENDING, CONFIRMED, EXECUTING, COMPLETED, FAILED
    portfolio_metrics: Optional[str] = None  # JSON
    total_investment: float
    total_risk: float
    max_profit: float
    max_loss: float
    created_at: datetime = Field(default_factory=datetime.utcnow, index=True)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
    execution_started_at: Optional[datetime] = None
    execution_completed_at: Optional[datetime] = None

    # Relationships
    user: Optional[User] = Relationship(back_populates="analyses")
    recommendations: List["StockRecommendation"] = Relationship(back_populates="analysis")
    orders: List["Order"] = Relationship(back_populates="analysis")
    execution_updates: List["ExecutionUpdate"] = Relationship(back_populates="analysis")

class StockRecommendation(SQLModel, table=True):
    __tablename__ = "StockRecommendations"

    recommendation_id: Optional[int] = Field(default=None, primary_key=True)
    analysis_id: str = Field(foreign_key="Analyses.analysis_id", index=True)
    stock_symbol: str = Field(index=True)
    company_name: Optional[str] = None
    action: str  # BUY, SELL, HOLD
    entry_price: float
    stop_loss: float
    target_price: float
    quantity: int
    risk_amount: float
    potential_profit: float
    potential_loss: float
    risk_reward_ratio: float
    confidence_score: float  # 0.0 to 1.0
    ai_reasoning: Optional[str] = None
    technical_indicators: Optional[str] = None  # JSON
    signal_strength: int = Field(ge=0, le=3)
    signal_reasons: Optional[str] = None  # JSON array
    created_at: datetime = Field(default_factory=datetime.utcnow)

    # Relationships
    analysis: Optional[Analysis] = Relationship(back_populates="recommendations")

class Signal(SQLModel, table=True):
    __tablename__ = "Signals"

    signal_id: Optional[int] = Field(default=None, primary_key=True)
    recommendation_id: Optional[int] = Field(foreign_key="StockRecommendations.recommendation_id")
    symbol: str = Field(index=True)
    signal_type: str = Field(index=True)  # VWAP+RSI, MACD+RSI, BB+RSI
    signal_value: str  # BUY, SELL, NEUTRAL
    indicator_values: Optional[str] = None  # JSON
    created_at: datetime = Field(default_factory=datetime.utcnow)

# ==================== ORDERS & EXECUTION ====================

class Order(SQLModel, table=True):
    __tablename__ = "Orders"

    order_id: str = Field(primary_key=True)
    zerodha_order_id: Optional[str] = None
    analysis_id: Optional[str] = Field(foreign_key="Analyses.analysis_id")
    recommendation_id: Optional[int] = Field(foreign_key="StockRecommendations.recommendation_id")
    user_id: str = Field(foreign_key="Users.user_id", index=True)
    stock_symbol: str = Field(index=True)
    action: str  # BUY, SELL
    order_type: str  # MARKET, LIMIT
    quantity: int
    price: float
    product: str  # MIS, CNC
    status: str = Field(default="PLACED", index=True)  # PLACED, PENDING, FILLED, REJECTED, CANCELLED
    fill_price: Optional[float] = None
    fill_quantity: Optional[int] = None
    executed_at: Optional[datetime] = None
    created_at: datetime = Field(default_factory=datetime.utcnow, index=True)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
    zerodha_response: Optional[str] = None  # JSON
    error_message: Optional[str] = None

    # Relationships
    user: Optional[User] = Relationship(back_populates="orders")
    analysis: Optional[Analysis] = Relationship(back_populates="orders")

class GttOrder(SQLModel, table=True):
    __tablename__ = "GttOrders"

    gtt_id: str = Field(primary_key=True)
    zerodha_gtt_id: Optional[str] = None
    order_id: Optional[str] = Field(foreign_key="Orders.order_id")
    user_id: str = Field(foreign_key="Users.user_id", index=True)
    stock_symbol: str = Field(index=True)
    entry_price: float
    target_price: float
    stop_loss: float
    action: str  # BUY, SELL
    product: str  # MIS, CNC
    status: str = Field(default="ACTIVE", index=True)  # ACTIVE, TRIGGERED, EXPIRED, CANCELLED
    trigger_price: Optional[float] = None
    triggered_at: Optional[datetime] = None
    triggered_order_id: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
    zerodha_response: Optional[str] = None  # JSON

class ExecutionUpdate(SQLModel, table=True):
    __tablename__ = "ExecutionUpdates"

    update_id: Optional[int] = Field(default=None, primary_key=True)
    analysis_id: str = Field(foreign_key="Analyses.analysis_id", index=True)
    stock_symbol: str = Field(index=True)
    update_type: str  # ORDER_PLACED, ORDER_FILLED, GTT_PLACED, etc.
    message: str
    order_id: Optional[str] = None
    gtt_id: Optional[str] = None
    details: Optional[str] = None  # JSON
    created_at: datetime = Field(default_factory=datetime.utcnow, index=True)

# ==================== TRADES & POSITIONS ====================

class Trade(SQLModel, table=True):
    __tablename__ = "Trades"

    trade_id: str = Field(primary_key=True)
    user_id: str = Field(foreign_key="Users.user_id", index=True)
    entry_order_id: Optional[str] = Field(foreign_key="Orders.order_id")
    exit_order_id: Optional[str] = None
    stock_symbol: str = Field(index=True)
    action: str  # BUY, SELL
    entry_price: float
    exit_price: Optional[float] = None
    stop_loss: float
    target_price: float
    quantity: int
    entry_time: datetime
    exit_time: Optional[datetime] = None
    status: str = Field(default="OPEN", index=True)  # OPEN, CLOSED, CANCELLED
    hold_duration_days: int = 0
    product: str  # MIS, CNC
    pnl: Optional[float] = None
    pnl_percent: Optional[float] = None
    reason_closed: Optional[str] = None  # TARGET_HIT, STOPLOSS_HIT, MANUAL, GTT_TRIGGERED
    strategy_name: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow, index=True)

    # Relationships
    user: Optional[User] = Relationship(back_populates="trades")

class OpenPosition(SQLModel, table=True):
    __tablename__ = "OpenPositions"

    position_id: Optional[int] = Field(default=None, primary_key=True)
    user_id: str = Field(foreign_key="Users.user_id", index=True)
    trade_id: Optional[str] = Field(foreign_key="Trades.trade_id")
    stock_symbol: str = Field(index=True)
    action: str  # BUY, SELL
    quantity: int
    entry_price: float
    current_price: float
    entry_time: datetime
    stop_loss: float
    target_price: float
    unrealized_pnl: float
    unrealized_pnl_percent: float
    product: str  # MIS, CNC
    updated_at: datetime = Field(default_factory=datetime.utcnow)

# ==================== PERFORMANCE ANALYTICS ====================

class MonthlyPerformance(SQLModel, table=True):
    __tablename__ = "MonthlyPerformance"

    month_id: Optional[int] = Field(default=None, primary_key=True)
    user_id: str = Field(foreign_key="Users.user_id", index=True)
    year: int
    month: int
    total_trades: int = 0
    winning_trades: int = 0
    losing_trades: int = 0
    win_rate: Optional[float] = None
    total_pnl: float = 0.0
    avg_profit_per_win: Optional[float] = None
    avg_loss_per_loss: Optional[float] = None
    profit_factor: Optional[float] = None
    largest_win: Optional[float] = None
    largest_loss: Optional[float] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)

class DailyPerformance(SQLModel, table=True):
    __tablename__ = "DailyPerformance"

    day_id: Optional[int] = Field(default=None, primary_key=True)
    user_id: str = Field(foreign_key="Users.user_id", index=True)
    performance_date: datetime
    total_trades: int = 0
    total_pnl: float = 0.0
    intraday_trades: int = 0
    swing_trades: int = 0
    created_at: datetime = Field(default_factory=datetime.utcnow)

# ==================== AUDIT & LOGGING ====================

class AuditLog(SQLModel, table=True):
    __tablename__ = "AuditLogs"

    log_id: Optional[int] = Field(default=None, primary_key=True)
    user_id: Optional[str] = Field(foreign_key="Users.user_id", index=True)
    action: str = Field(index=True)  # ANALYSIS_CREATED, ORDER_PLACED, LOGIN, etc.
    resource_type: str = Field(index=True)  # ANALYSIS, ORDER, TRADE
    resource_id: Optional[str] = None
    request_body: Optional[str] = None  # JSON
    response_body: Optional[str] = None  # JSON
    status_code: Optional[int] = None
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None
    error_message: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow, index=True)

class ApiCallLog(SQLModel, table=True):
    __tablename__ = "ApiCallLogs"

    call_id: Optional[int] = Field(default=None, primary_key=True)
    user_id: Optional[str] = Field(foreign_key="Users.user_id", index=True)
    endpoint: str = Field(index=True)  # '/quote', '/place_order', etc.
    method: str  # GET, POST, PUT
    request_params: Optional[str] = None  # JSON
    response_data: Optional[str] = None  # JSON
    http_status: int
    response_time_ms: int
    error_code: Optional[str] = None
    error_message: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow, index=True)

class ErrorLog(SQLModel, table=True):
    __tablename__ = "ErrorLogs"

    error_id: Optional[int] = Field(default=None, primary_key=True)
    user_id: Optional[str] = Field(foreign_key="Users.user_id", index=True)
    error_type: str = Field(index=True)
    error_message: str
    stack_trace: Optional[str] = None
    context_data: Optional[str] = None  # JSON
    severity: str = Field(default="ERROR", index=True)  # CRITICAL, ERROR, WARNING, INFO
    created_at: datetime = Field(default_factory=datetime.utcnow, index=True)
```

### Step 1.7 — Update main.py

**File: [app/main.py](app/main.py)** - Add initialization:

```python
from app.core.database import init_db, close_db

def create_app() -> FastAPI:
    app = FastAPI(...)

    @app.on_event("startup")
    async def startup_event():
        logger.info("🚀 Application starting up...")
        logger.info("📚 Initializing database...")
        try:
            init_db()
            logger.info("✓ Database initialized successfully")
        except Exception as e:
            logger.error(f"✗ Failed to initialize database: {e}")
            raise

    @app.on_event("shutdown")
    async def shutdown_event():
        logger.info("🛑 Shutting down application...")
        close_db()
        logger.info("✓ Database connections closed")

    # ... rest of routes ...
    return app
```

### Step 1.8 — Test Database Connection

```bash
cd /Users/akhileshallewar/project_dev/AutoTradingApp

# Run Python to test connection
python -c "
from app.core.database import init_db
from app.core.config import get_settings

settings = get_settings()
print(f'Database Server: {settings.DB_SERVER}')
print(f'Database Name: {settings.DB_NAME}')
print('Attempting connection...')

try:
    init_db()
    print('✓ Database connection successful!')
    print('✓ All tables created successfully!')
except Exception as e:
    print(f'✗ Connection failed: {e}')
"
```

**Expected output:**
```
Database Server: vantrade.database.windows.net
Database Name: VanTradeDB
Attempting connection...
✓ Database connection successful!
✓ All tables created successfully!
```

---

## 📊 NEXT PHASES (High-Level Overview)

| Phase | Duration | Key Tasks | Output |
|-------|----------|-----------|--------|
| **Phase 2** | Week 2-3 | Integrate analysis → DB, order tracking, execution logging | Orders + GTT storage working |
| **Phase 3** | Week 3-4 | P&L calculation, performance metrics, dashboard queries | Analytics ready |
| **Audit** | All phases | Add AuditLogs middleware, error logging, compliance | Full audit trail |

---

## ✅ Phase 1 Completion Checklist

After completing all steps above:

```
[ ] Azure SQL database created and accessible
[ ] requirements.txt updated with SQLModel dependencies
[ ] app/core/config.py updated with DB settings
[ ] .env file updated with database credentials
[ ] app/core/database.py created with SQLModel engine
[ ] app/models/db_models.py created with all table models
[ ] app/main.py updated with database initialization
[ ] Python test script runs successfully
[ ] All 13 tables visible in Azure SQL Portal
[ ] Database connection working from backend
```

---

## 🔐 Security Notes

1. **Never commit .env file** - Add to .gitignore
2. **Encrypt API credentials** - Use Fernet before storing in DB
3. **Use TLS for connections** - Azure SQL enforces this
4. **Rotate encryption keys regularly** - Plan quarterly rotations

---

## 📞 Troubleshooting Phase 1

| Issue | Solution |
|-------|----------|
| "Cannot import sqlmodel" | Run `pip install -r app/requirements.txt` |
| "Connection timeout" | Check firewall - add your IP to Azure SQL |
| "Authentication failed" | Verify username/password in .env |
| "Table already exists" | Tables auto-create, this is expected on first run |
| "ODBC driver not found" | Install MS ODBC driver (see Step 1.1) |

---

## 🎯 Next Command

Once Phase 1 is complete, run this to start Phase 2:

```bash
cd /Users/akhileshallewar/project_dev/AutoTradingApp
python -c "from app.core.database import init_db; init_db(); print('✓ Ready for Phase 2!')"
```

---

**Status:** ⏳ Ready to Execute Phase 1
**Estimated Time:** 1-2 hours
**Dependencies:** Azure SQL DB access + .env file with credentials
