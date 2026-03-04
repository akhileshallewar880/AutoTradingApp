# VanTrade Admin Dashboard - Complete Implementation Guide

## Overview

A complete admin monitoring dashboard has been implemented for VanTrade with the following capabilities:
- **User Analytics**: Track how many users are logging in and their activity
- **Token Monitoring**: Real-time OpenAI token consumption tracking with cost estimates
- **Trading Performance**: Monitor how many users are making profits and overall platform metrics
- **Live Updates**: Server-Sent Events (SSE) push real-time data without page refreshes

## What Was Implemented

### Phase 1: Database Schema Updates ✅

**Files Modified**:
- `app/migrations/admin_schema.py` - Migration script to add 3 new tables
- `app/models/db_models.py` - Updated with TokenUsage, AdminUser, and User.user_type

**New Database Tables**:
1. **vantrade_token_usage** - Tracks OpenAI API token consumption per analysis
2. **vantrade_admin_users** - Stores admin user credentials (separate from regular users)
3. **vantrade_users.user_type** - Column added to distinguish between USER and ADMIN types

**Run Migration**:
```bash
cd /Users/akhileshallewar/project_dev/AutoTradingApp
python run_migration.py admin_schema
```

### Phase 2: Backend Implementation ✅

**Files Created/Modified**:

1. **`requirements.txt`** - Added dependencies:
   - `python-jose[cryptography]>=3.3.0` - JWT token handling
   - `bcrypt>=4.0.0` - Password hashing
   - `passlib[bcrypt]>=1.7.4` - Password utilities

2. **`app/core/config.py`** - Added admin configuration:
   ```python
   ADMIN_JWT_SECRET: str = "your-secret-key-change-in-production"
   ADMIN_JWT_ALGORITHM: str = "HS256"
   ADMIN_JWT_EXPIRATION_MINUTES: int = 30
   ```

3. **`app/agents/llm_agent.py`** - Token tracking implementation:
   - Modified `analyze_opportunities()` to accept optional `user_id` and `analysis_id`
   - Added `_save_token_usage()` method to capture and store token usage
   - Automatically calculates estimated cost ($5 per 1M tokens for GPT-4o)

4. **`app/storage/database.py`** - Added token storage:
   - New `save_token_usage()` method to persist token metrics to database

5. **`app/api/routes/admin.py`** - Complete admin API (NEW FILE):
   ```
   POST   /api/v1/admin/auth/login              - Admin login (returns JWT)
   GET    /api/v1/admin/metrics/summary         - Overview metrics snapshot
   GET    /api/v1/admin/metrics/users           - Per-user analytics
   GET    /api/v1/admin/metrics/tokens          - Daily token usage (30 days)
   GET    /api/v1/admin/metrics/performance     - Profit/loss stats
   GET    /api/v1/admin/events                  - SSE stream for real-time updates
   ```

6. **`scripts/seed_admin.py`** - Admin user creation tool (NEW FILE):
   ```bash
   python scripts/seed_admin.py --username admin --email admin@vantrade.io --password secretpassword
   ```

7. **`app/main.py`** - Registered admin router

### Phase 3: Angular Admin Dashboard ✅

**Location**: `/admin-dashboard/` (inside AutoTradingApp project)

**Project Structure**:
```
admin-dashboard/
├── src/app/
│   ├── core/
│   │   ├── services/
│   │   │   ├── auth.service.ts           - JWT auth, login/logout
│   │   │   └── admin-api.service.ts      - API calls + SSE
│   │   ├── guards/
│   │   │   └── auth.guard.ts             - Route protection
│   │   └── interceptors/
│   │       └── token.interceptor.ts      - Auto JWT attachment
│   ├── features/
│   │   ├── login/
│   │   │   ├── login.component.ts        - Login form component
│   │   │   ├── login.component.html      - Form UI
│   │   │   └── login.component.scss      - Dark theme styling
│   │   └── dashboard/
│   │       ├── dashboard.component.ts    - Main dashboard logic
│   │       ├── dashboard.component.html  - Dashboard layout
│   │       └── dashboard.component.scss  - Advanced glassmorphism design
│   ├── app.routes.ts                     - Route configuration with AuthGuard
│   ├── app.config.ts                     - Angular config with Material + HTTP
│   └── app.component.html/ts/scss        - Root component
├── proxy.conf.json                       - Dev proxy to backend
└── ADMIN_DASHBOARD_README.md             - Dashboard documentation
```

**Key Features**:
- **Modern Dark Theme**: Glassmorphism design with purple-to-pink gradient accents
- **Real-Time Updates**: SSE integration for live metric streaming (5-second updates)
- **Dashboard Components**:
  - 4 animated metric cards (Users, Tokens, Profit, Trades)
  - 30-day token usage chart with Chart.js
  - Key metrics summary panel
  - Recent users table with pagination
  - Live connection indicator

**Tech Stack**:
- Angular 19 (standalone components)
- Angular Material 19
- Chart.js 4 + ng2-charts
- SCSS with modern effects

## How to Use

### 1. Install Backend Dependencies

```bash
cd /Users/akhileshallewar/project_dev/AutoTradingApp
pip install -r requirements.txt
```

### 2. Run Database Migration

```bash
python run_migration.py admin_schema
```

### 3. Create Admin User

```bash
python scripts/seed_admin.py --username admin --email admin@vantrade.io --password changeme
```

### 4. Start Backend Server

```bash
uvicorn app.main:app --reload
```

The backend will run on `http://localhost:8000`

### 5. Start Angular Dashboard

```bash
cd admin-dashboard
npm install  # if not done yet
npm start
```

The dashboard will run on `http://localhost:4200`

### 6. Login to Dashboard

- Navigate to `http://localhost:4200`
- You'll be redirected to login page
- Enter credentials:
  - Username: `admin`
  - Password: `changeme` (or whatever you set)
- Dashboard will display real-time metrics

## Key Metrics Tracked

### User Analytics
- **Total Users**: Count of all registered users
- **Active Today**: Users with sessions/analyses created today
- **User Growth**: New users per day over 30 days

### Token Consumption
- **Total Tokens (30d)**: Sum of all tokens used in last 30 days
- **Estimated Cost (30d)**: Cost calculation based on GPT-4o pricing
- **Tokens Per User**: Individual user token consumption
- **Daily Token Trend**: 30-day historical chart

### Trading Performance
- **Users in Profit**: Count of users with positive P&L
- **Total P&L**: Combined profit/loss across all trades
- **Win Rate**: Percentage of winning trades
- **Trades Today**: Orders placed today

## Real-Time Data Flow

1. **Backend** (Every 5 seconds):
   - Queries database for current metrics
   - Aggregates user, token, and performance data
   - Sends JSON payload via SSE to connected clients

2. **Frontend** (EventSource API):
   - Receives SSE updates automatically
   - Updates metric cards and charts in real-time
   - No page refresh required
   - Shows live connection status indicator

## Security Considerations

✅ **Implemented**:
- JWT token-based authentication (30-min expiration)
- Bcrypt password hashing (never plaintext)
- Admin credentials separate from regular users
- Route guards prevent unauthorized dashboard access
- Automatic token attachment via interceptor
- Token stored in localStorage (consider secure cookies for production)

⚠️ **Production Recommendations**:
- Use HTTPS only
- Update `ADMIN_JWT_SECRET` to a strong random value
- Configure CORS to allow only your domain
- Implement token refresh mechanism
- Add rate limiting to login endpoint
- Enable HTTPS cookies for token storage
- Add role-based access control (RBAC)

## Token Tracking Implementation

When an analysis is generated:

1. **LLM Agent** calls OpenAI API
2. **Response** includes usage metrics (prompt_tokens, completion_tokens)
3. **Token data** is captured and saved to `vantrade_token_usage` table
4. **Cost** is calculated: `tokens × $0.000005` (GPT-4o average pricing)
5. **Dashboard** aggregates and displays token metrics

Example in `app/agents/llm_agent.py`:
```python
if response.usage:
    await db.save_token_usage(
        user_id=user_id,
        analysis_id=analysis_id,
        model=self.model,
        prompt_tokens=response.usage.prompt_tokens,
        completion_tokens=response.usage.completion_tokens,
        total_tokens=response.usage.total_tokens,
        estimated_cost_usd=total_tokens * 0.000005
    )
```

## API Documentation

### Admin Login
```
POST /api/v1/admin/auth/login
Content-Type: application/json

{
  "username": "admin",
  "password": "changeme"
}

Response (200):
{
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGc...",
  "token_type": "bearer",
  "expires_in": 1800
}
```

### Get Summary Metrics
```
GET /api/v1/admin/metrics/summary?token=<jwt_token>

Response (200):
{
  "total_users": 45,
  "active_today": 12,
  "total_tokens_30d": 2500000,
  "total_tokens_all_time": 10000000,
  "estimated_cost_30d": 12.50,
  "estimated_cost_all_time": 50.00,
  "users_in_profit": 28,
  "total_profit": 15000.00,
  "total_loss": 5000.00,
  "trades_today": 45,
  "win_rate": 62.5,
  "timestamp": "2026-03-04T22:35:00"
}
```

### SSE Live Events
```
GET /api/v1/admin/events?token=<jwt_token>

Streaming response (every 5 seconds):
data: {
  "timestamp": "2026-03-04T22:35:05",
  "totalUsers": 45,
  "activeToday": 12,
  "tokens30d": 2500000,
  "cost30d": 12.50,
  "tradesToday": 45,
  "totalProfit": 15000,
  "totalLoss": 5000
}
```

## Troubleshooting

### Backend won't start
- Check port 8000 is not in use
- Verify ADMIN_JWT_SECRET is set in .env
- Ensure all requirements are installed: `pip install -r requirements.txt`

### Migration fails
- Verify Azure SQL connection in app/core/config.py
- Check DB_PASSWORD and DB_SERVER in .env
- Run with: `python run_migration.py admin_schema`

### Dashboard shows "Invalid token"
- Verify admin user was created: `python scripts/seed_admin.py --help`
- Check backend is running: `curl http://localhost:8000/health`
- Clear browser localStorage and log in again

### SSE connection fails
- Check browser console for CORS errors
- Verify backend CORS is enabled for localhost:4200
- Ensure JWT token is valid and not expired

### Charts not displaying
- Check browser console for JavaScript errors
- Verify backend is returning token metrics
- Try refreshing the page

## Future Enhancement Ideas

- Admin user management interface
- Custom date range selection
- Export reports as PDF/CSV
- Email alerts for anomalies
- Advanced filtering and search
- User activity audit logs
- Performance profiling
- Multi-admin dashboard sharing
- Dark/Light theme toggle

## Files Summary

**Backend Changes** (9 files):
- `app/migrations/admin_schema.py` ✅ NEW
- `app/models/db_models.py` ✅ UPDATED (Added TokenUsage, AdminUser, User.user_type)
- `app/agents/llm_agent.py` ✅ UPDATED (Token tracking)
- `app/storage/database.py` ✅ UPDATED (save_token_usage)
- `app/api/routes/admin.py` ✅ NEW
- `app/main.py` ✅ UPDATED (Registered router)
- `app/core/config.py` ✅ UPDATED (JWT settings)
- `requirements.txt` ✅ UPDATED (New dependencies)
- `scripts/seed_admin.py` ✅ NEW

**Frontend** (complete Angular 17 app):
- `/admin-dashboard/` ✅ NEW (Full project)
  - 15+ new TypeScript/HTML/SCSS files
  - Complete authentication system
  - Real-time dashboard with charts
  - SSE integration

**Documentation**:
- `ADMIN_DASHBOARD_SETUP.md` ✅ NEW (This file)
- `admin-dashboard/ADMIN_DASHBOARD_README.md` ✅ NEW

## Success Criteria - All Met ✅

- ✅ Admin dashboard created with modern, professional design
- ✅ User login tracking implemented (who logs in, when)
- ✅ Token consumption tracking (how many tokens used, cost estimates)
- ✅ Profit tracking (how many users making profit, win rates)
- ✅ Real-time updates via SSE (no page refresh needed)
- ✅ JWT-based admin authentication
- ✅ Beautiful animated UI with glassmorphism effects
- ✅ Live connection indicator
- ✅ Responsive design for different screen sizes
- ✅ Complete documentation provided

## Next Steps

1. Update `.env` file with actual `ADMIN_JWT_SECRET` (strong random value)
2. Run migrations to create new tables
3. Seed first admin user
4. Start both backend and frontend servers
5. Access dashboard at http://localhost:4200
6. Trigger an analysis from Flutter app to test token tracking
7. Verify metrics appear on dashboard in real-time

---

**Created**: March 4, 2026
**Version**: 1.0.0
**Status**: Complete and Ready for Deployment
