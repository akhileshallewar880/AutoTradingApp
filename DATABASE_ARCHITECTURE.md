# VanTrade Database Architecture
## Complete Schema Overview

---

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Mobile App                        │
│                   (algotrading/)                             │
└──────────────────────────┬──────────────────────────────────┘
                           │ HTTPS/REST API
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                    FastAPI Backend                           │
│                   (app/main.py)                             │
│  Routes: /api/v1/auth, /analysis, /orders, /dashboard      │
└──────────────────────────┬──────────────────────────────────┘
                           │
                ┌──────────┴──────────┐
                ↓                     ↓
        ┌─────────────────┐  ┌──────────────────┐
        │  Zerodha API    │  │  Azure SQL DB    │
        │  (Real Data)    │  │  (Data Storage)  │
        └─────────────────┘  └──────────────────┘
```

---

## 📦 Database Schema (13 Tables)

### User Management (3 Tables)
```
Users (user_id PK)
├─ zerodha_user_id (UNIQUE)
├─ email (UNIQUE)
├─ full_name
├─ is_active
└─ created_at

ApiCredentials (credential_id PK)
├─ user_id (FK → Users)
├─ access_token (encrypted)
├─ api_key (encrypted)
├─ is_valid
└─ expires_at

Sessions (session_id PK)
├─ user_id (FK → Users)
├─ access_token
├─ ip_address
├─ is_active
└─ last_activity
```

### Analysis & Signals (3 Tables)
```
Analyses (analysis_id PK)
├─ user_id (FK → Users)
├─ hold_duration_days (0=intraday, >0=swing)
├─ status (PENDING, CONFIRMED, EXECUTING, COMPLETED)
├─ total_investment
├─ max_profit / max_loss
└─ created_at

StockRecommendations (recommendation_id PK)
├─ analysis_id (FK → Analyses)
├─ stock_symbol
├─ action (BUY/SELL)
├─ entry_price, stop_loss, target_price
├─ confidence_score
└─ technical_indicators (JSON)

Signals (signal_id PK)
├─ recommendation_id (FK)
├─ signal_type (VWAP+RSI, MACD+RSI, BB+RSI)
├─ signal_value (BUY/SELL/NEUTRAL)
└─ indicator_values (JSON)
```

### Orders & Execution (3 Tables)
```
Orders (order_id PK)
├─ user_id (FK → Users)
├─ analysis_id (FK → Analyses)
├─ stock_symbol
├─ action (BUY/SELL)
├─ status (PLACED, PENDING, FILLED, REJECTED)
├─ zerodha_order_id
└─ fill_price, fill_quantity

GttOrders (gtt_id PK)
├─ user_id (FK → Users)
├─ order_id (FK → Orders)
├─ stock_symbol
├─ target_price / stop_loss
├─ status (ACTIVE, TRIGGERED, EXPIRED)
└─ triggered_at

ExecutionUpdates (update_id PK)
├─ analysis_id (FK → Analyses)
├─ stock_symbol
├─ update_type (ORDER_PLACED, GTT_TRIGGERED, etc.)
└─ created_at
```

### Trades & Positions (2 Tables)
```
Trades (trade_id PK)
├─ user_id (FK → Users)
├─ entry_order_id (FK → Orders)
├─ stock_symbol
├─ entry_price / exit_price
├─ status (OPEN/CLOSED)
├─ pnl / pnl_percent
└─ reason_closed (TARGET_HIT, STOPLOSS_HIT, etc.)

OpenPositions (position_id PK)
├─ user_id (FK → Users)
├─ trade_id (FK → Trades)
├─ stock_symbol
├─ current_price
├─ unrealized_pnl / unrealized_pnl_percent
└─ updated_at
```

### Performance Analytics (2 Tables)
```
MonthlyPerformance (month_id PK)
├─ user_id (FK → Users)
├─ year / month
├─ total_trades / winning_trades / losing_trades
├─ win_rate
├─ total_pnl
├─ profit_factor
└─ largest_win / largest_loss

DailyPerformance (day_id PK)
├─ user_id (FK → Users)
├─ performance_date
├─ total_trades
├─ total_pnl
├─ intraday_trades / swing_trades
└─ created_at
```

### Audit & Logging (3 Tables)
```
AuditLogs (log_id PK)
├─ user_id (FK → Users)
├─ action (LOGIN, ANALYSIS_CREATED, ORDER_PLACED, etc.)
├─ resource_type (ANALYSIS, ORDER, TRADE)
├─ resource_id
├─ status_code
├─ ip_address
└─ created_at

ApiCallLogs (call_id PK)
├─ user_id (FK → Users)
├─ endpoint (/quote, /place_order, /gtt, etc.)
├─ method (GET, POST)
├─ request_params (JSON)
├─ response_time_ms
├─ error_code / error_message
└─ created_at

ErrorLogs (error_id PK)
├─ user_id (FK → Users)
├─ error_type
├─ error_message
├─ stack_trace
├─ severity (CRITICAL, ERROR, WARNING)
└─ created_at
```

---

## 🔄 Data Flow Diagrams

### User Login Flow
```
1. User Opens App
   ↓
2. Flutter → POST /api/v1/auth/login
   ↓
3. Backend → Zerodha OAuth redirect
   ↓
4. User logs in at Zerodha
   ↓
5. Zerodha → Callback with request_token
   ↓
6. Flask → POST /api/v1/auth/session {request_token}
   ↓
7. Backend verifies with Zerodha
   ↓
8. CREATE User (if not exists)
   INSERT ApiCredentials (encrypted access_token)
   CREATE Session
   INSERT AuditLog ('LOGIN')
   ↓
9. RETURN SessionResponse to Flutter
   ↓
10. Flutter → Home Screen (authenticated)
```

### Analysis Execution Flow
```
1. POST /api/v1/analysis/generate {analysis_request}
   ↓
2. INSERT Analyses {status='PENDING_CONFIRMATION'}
   ↓
3. Run AnalysisService.screen_and_enrich()
   → ScreenService.screen_top_movers()
   → AnalysisService.calculate_indicators()
   → LLMAgent.analyze_opportunities()
   ↓
4. INSERT StockRecommendations (per stock)
   INSERT Signals (per indicator)
   ↓
5. UPDATE Analyses {portfolio_metrics}
   INSERT AuditLog('ANALYSIS_CREATED')
   ↓
6. RETURN AnalysisResponse to Flutter
   ↓
7. User reviews & clicks "Confirm"
   ↓
8. POST /api/v1/analysis/{analysis_id}/confirm
   ↓
9. UPDATE Analyses {status='CONFIRMED'}
   Trigger background task: execute_trades()
   ↓
10. FOR EACH recommendation:
    - Call ExecutionAgent.execute_trade_with_gtt()
    - INSERT Orders {status='PLACED'}
    - Poll order status → INSERT Orders {status='FILLED'}
    - INSERT GttOrders {status='ACTIVE'}
    - INSERT ExecutionUpdates (real-time tracking)
    ↓
11. GTT triggers or user cancels
    - INSERT Trades {status='CLOSED', pnl}
    - UPDATE GttOrders {status='TRIGGERED'}
    - UPDATE OpenPositions or CLOSE
    - INSERT AuditLog('TRADE_CLOSED')
    ↓
12. UPDATE Analyses {status='COMPLETED'}
```

### Dashboard Update Flow
```
GET /api/v1/dashboard/summary {access_token}
   ↓
1. Query from Zerodha (live data):
   - margins()
   - positions()
   - tradebook()
   - gtt_list()
   ↓
2. INSERT AccountMetrics (snapshot)
   ↓
3. Calculate metrics:
   - Available balance
   - Today's P&L
   - Month P&L
   - Open positions count
   ↓
4. Query from DB:
   - SELECT * FROM OpenPositions WHERE user_id
   - SELECT * FROM GttOrders WHERE user_id AND status='ACTIVE'
   - SELECT SUM(pnl) FROM Trades WHERE user_id AND DATE=TODAY
   ↓
5. RETURN DashboardResponse to Flutter
```

---

## 🔐 Security Model

### Encryption Strategy
```
At Rest:
├─ Azure SQL TDE (Transparent Data Encryption) - Auto enabled
└─ Application-level encryption for:
   ├─ ApiCredentials.access_token (Fernet cipher)
   ├─ ApiCredentials.request_token (Fernet cipher)
   ├─ ApiCredentials.api_key (Fernet cipher)
   └─ ApiCredentials.api_secret (Fernet cipher)

In Transit:
├─ All API calls: HTTPS/TLS 1.3
└─ DB connections: Encrypted TCP connections

Access Control:
├─ Row-level filtering: Always WHERE user_id = current_user
├─ Session validation: Check Sessions.is_active
└─ API key rotation: Automatic on re-login
```

### PII Protection
```
Sensitive Fields:
├─ Users.email → Indexed, exposed only to owner
├─ ApiCredentials.access_token → Never logged
├─ Audit logs → Sanitize request_body before logging
└─ API call logs → Redact sensitive params
```

---

## 📈 Index Strategy

**Key Indexes for Performance:**

```
Users:
  ├─ PK: user_id
  └─ UQ: zerodha_user_id, email

Orders:
  ├─ PK: order_id
  ├─ FK: user_id (ordered query)
  ├─ IDX: (user_id, stock_symbol)
  ├─ IDX: status
  └─ IDX: analysis_id

Analyses:
  ├─ PK: analysis_id
  ├─ FK: user_id
  ├─ IDX: (user_id, analysis_date DESC)
  ├─ IDX: status
  └─ IDX: created_at DESC

Trades:
  ├─ PK: trade_id
  ├─ FK: user_id
  ├─ IDX: (user_id, stock_symbol)
  ├─ IDX: status
  └─ IDX: entry_time DESC

AuditLogs:
  ├─ PK: log_id
  ├─ FK: user_id
  ├─ IDX: (user_id, created_at DESC)
  └─ IDX: (resource_type, resource_id)
```

---

## 🎯 Key Features

### Multi-User Support
- ✅ Each user has isolated credentials
- ✅ Independent analysis history
- ✅ Separate performance metrics
- ✅ Complete audit trail per user

### Real-Time Execution Tracking
- ✅ ExecutionUpdates table for live status
- ✅ Order status polling → database updates
- ✅ GTT trigger detection → database logging
- ✅ Position tracking (OpenPositions)

### Performance Analytics
- ✅ Monthly aggregations (MonthlyPerformance)
- ✅ Daily P&L tracking (DailyPerformance)
- ✅ Per-trade metrics (via Trades table)
- ✅ Win rate, profit factor, drawdown calculations

### Compliance & Audit
- ✅ Complete action audit trail (AuditLogs)
- ✅ API call logging (ApiCallLogs)
- ✅ Error tracking (ErrorLogs)
- ✅ Stack traces for debugging
- ✅ All timestamps in UTC

---

## 💾 Storage Capacity

**Estimated storage requirements per user:**

```
User 1:
├─ 1 Users record                    ~100 bytes
├─ 1 ApiCredentials record           ~500 bytes
├─ 365 Sessions (1 per day)          ~500 KB
├─ 250 Analyses/year                 ~10 MB
├─ 2500 Orders/year                  ~5 MB
├─ 2500 Trades/year                  ~5 MB
├─ 12 MonthlyPerformance records     ~5 KB
├─ 365 DailyPerformance records      ~50 KB
├─ 100K AuditLogs/year              ~50 MB
├─ 50K ApiCallLogs/year             ~50 MB
└─ Total per active user             ~130 MB/year

10,000 users → ~1.3 TB/year
```

Azure SQL Database sizing:
- **Standard Tier (recommended start)**: 250 GB - $300/month
- **Premium Tier (growth)**: 500 GB + - $600+/month

---

## 🚀 Scaling Considerations

### Connection Pooling
```
Pool Size: 20 connections (default)
Max Overflow: 10 additional connections
Pool Recycle: 3600 seconds (1 hour)
Result: Can handle ~100 concurrent API users
```

### Query Optimization
```
Strategy:
├─ Indexes on frequently filtered columns
├─ Covering indexes for common queries
├─ Denormalization (e.g., pnl in Trades table)
├─ JSON columns for flexible data (indicators, signals)
└─ Archive old data after 1 year
```

### Archival Strategy (Future)
```
After 1 year:
├─ Move old Trades → ArchiveTrades table
├─ Move old AuditLogs → ArchiveAuditLogs table
├─ Keep MonthlyPerformance (aggregate data)
└─ Reduces table sizes for faster queries
```

---

## 📊 Reporting Views (Future)

```sql
-- User Performance Dashboard
SELECT user_id, month, total_pnl, win_rate, profit_factor
FROM MonthlyPerformance
WHERE user_id = @user_id
ORDER BY year DESC, month DESC;

-- Top Performing Strategies
SELECT strategy_name, COUNT(*) as trades, AVG(pnl_percent) as avg_return
FROM Trades
WHERE user_id = @user_id
GROUP BY strategy_name
ORDER BY avg_return DESC;

-- Recent Trades
SELECT stock_symbol, action, entry_price, exit_price, pnl, entry_time
FROM Trades
WHERE user_id = @user_id AND status='CLOSED'
ORDER BY exit_time DESC
LIMIT 20;
```

---

## 🔍 Monitoring & Health Checks

```python
# Database health check endpoint (optional)
@router.get("/health/db")
async def db_health():
    """Check database connectivity."""
    try:
        with Session(engine) as session:
            # Simple query to test connection
            session.exec("SELECT 1")
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}, 503
```

---

## 📋 Summary

**13 Tables** providing:
- ✅ Multi-user support with encrypted credentials
- ✅ Complete analysis & recommendation tracking
- ✅ Full order & trade execution history
- ✅ Real-time position tracking
- ✅ Performance metrics & analytics
- ✅ Comprehensive audit trail
- ✅ Error logging for debugging
- ✅ Compliance-ready architecture

**Ready for production use with proper monitoring & backups!**

---

**Last Updated:** March 4, 2026
**Status:** ✅ Design Complete, Ready for Implementation
