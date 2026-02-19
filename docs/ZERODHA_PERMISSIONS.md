# Zerodha API Permissions Issue - Solutions

## Problem
```
ERROR: Insufficient permission for that call
```

The Zerodha API key doesn't have permission to fetch historical data (OHLC candles), which is required for AI analysis.

## Root Cause
Historical data access requires a **paid Zerodha Kite Connect subscription** with historical data permissions.

## Solutions

### Option 1: Enable Demo Mode (Recommended for Testing)

I can add a demo mode that generates mock stock analysis without requiring historical data. This lets you test the entire app functionality.

**Benefits:**
- ✅ Test the complete app flow
- ✅ No additional cost
- ✅ Works immediately
- ❌ Uses mock data (not real market data)

### Option 2: Upgrade Zerodha Subscription (Production)

For real trading with live market data:

1. Visit https://kite.trade/
2. Subscribe to "Kite Connect + Historical Data"
3. Cost: ₹2000/month
4. Your API key will get historical data access
5. App will work with real market data

## What's Needed?

**For Demo Mode:**
- I'll add a `DEMO_MODE=true` flag to `.env`
- When enabled, generates realistic mock analysis
- Perfect for testing UI and workflow

**For Production:**
- Upgrade Zerodha subscription
- Give me the new API key with historical data access
- Update `.env` file

---

**Recommendation:** Start with Demo Mode to test everything, then upgrade to production when ready to trade with real money.

Would you like me to implement the demo mode?
