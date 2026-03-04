# VanTrade - End-to-End Application Flow

**Last Updated**: March 4, 2026
**Version**: 1.0.0+2 (Multi-Login with Database Integration)

---

## 📱 Complete User Journey

### Phase 1: App Installation & Onboarding

```
┌─────────────────────────────────────────────────────────────────┐
│                    1. USER INSTALLS APP                         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
              ┌───────────────────────────────────┐
              │   Splash Screen (animated logo)   │
              │   Checks onboarding_completed     │
              └───────────────────────────────────┘
                              ↓
                    ❌ First Time User?
                   /                    \
                  YES                   NO
                  ↓                      ↓
         ┌─────────────────┐   ┌──────────────────┐
         │ Onboarding Flow │   │  Login Screen    │
         │ (4 steps)       │   └──────────────────┘
         └─────────────────┘
                  ↓
    ┌──────────────────────────────────────┐
    │ Step 1: Welcome to VanTrade          │
    │ - Features overview                  │
    │ - What app does                      │
    └──────────────────────────────────────┘
                  ↓
    ┌──────────────────────────────────────┐
    │ Step 2: Why Zerodha Account?         │
    │ - Broker integration explanation     │
    │ - Links to Zerodha                   │
    └──────────────────────────────────────┘
                  ↓
    ┌──────────────────────────────────────┐
    │ Step 3: Get API Credentials          │
    │ - Step-by-step guide                 │
    │ - Opens kite.trade to get creds      │
    └──────────────────────────────────────┘
                  ↓
    ┌──────────────────────────────────────┐
    │ Step 4: Ready to Start               │
    │ - Summary                            │
    │ - "Continue to Login" button         │
    └──────────────────────────────────────┘
                  ↓
    Saves: onboarding_completed = true
    (SharedPreferences)
```

---

### Phase 2: Authentication & API Credential Setup

```
┌─────────────────────────────────────────────────────────────────┐
│                      LOGIN SCREEN                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  [Login with Zerodha] button                            │   │
│  │  [Demo Mode] button (for testing)                       │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    Click "Login with Zerodha"
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│   ZERODHA OAUTH LOGIN (Browser redirects to Zerodha)            │
│   - User enters email/password                                  │
│   - Zerodha OTP verification                                    │
│   - Redirects back to app with oauth token                      │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              API SETTINGS SCREEN (New Screen)                   │
│                                                                 │
│  "Enter Your Zerodha API Credentials"                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ API Key:    [________________] (masked input)           │   │
│  │ API Secret: [________________] (masked input)           │   │
│  │                                                         │   │
│  │ Help: How to get API credentials?                       │   │
│  │ [Opens link to Zerodha Developer Console]              │   │
│  │                                                         │   │
│  │ [Validate] [Skip]                                       │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    Click "Validate"
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│          BACKEND: Validate Credentials                          │
│                                                                 │
│  POST /api/validate-zerodha-credentials                         │
│  Request:                                                       │
│  {                                                              │
│    "api_key": "user_entered_key",                               │
│    "api_secret": "user_entered_secret"                          │
│  }                                                              │
│                                                                 │
│  Backend Logic:                                                 │
│  1. Create KiteConnect instance with credentials                │
│  2. Make test API call: kite.instruments()                      │
│  3. If successful → return {valid: true}                        │
│  4. If failed → return {valid: false, message: error}           │
│                                                                 │
│  DB: Insert into vantrade_api_credentials                       │
│  - credential_id (PK)                                           │
│  - user_id (FK to vantrade_users)                               │
│  - api_key_encrypted (Fernet encryption)                        │
│  - api_secret_encrypted (Fernet encryption)                     │
│  - is_valid: true                                               │
│  - created_at: now()                                            │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    ✅ Credentials Valid?
                   /                    \
                  YES                   NO
                  ↓                      ↓
    ┌────────────────────┐   ┌──────────────────┐
    │ Save Credentials   │   │ Show Error Msg   │
    │ (encrypted local)  │   │ Try Again        │
    │ SharedPreferences  │   └──────────────────┘
    └────────────────────┘
                  ↓
         ┌──────────────────┐
         │   HOME SCREEN    │
         └──────────────────┘
```

---

### Phase 3: Stock Analysis Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                      HOME SCREEN                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Welcome, User!                                         │   │
│  │  Account Balance: ₹1,00,000                             │   │
│  │                                                         │   │
│  │  [Start Analysis] button                                │   │
│  │  [View Open Positions]                                  │   │
│  │  [Dashboard] (Performance Metrics)                      │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    Click "Start Analysis"
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              ANALYSIS INPUT SCREEN                              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ How long do you want to hold?                           │   │
│  │ • 0 days (Intraday) ← SELECTED                          │   │
│  │ • 1-2 days (Short Swing)                                │   │
│  │ • 3-5 days (Swing)                                      │   │
│  │ • 5+ days (Long-term)                                   │   │
│  │                                                         │   │
│  │ Investment Amount: [₹_______]                           │   │
│  │ Max Risk per Trade: [__]%                               │   │
│  │                                                         │   │
│  │ [Analyze Stocks]                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    Click "Analyze Stocks"
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│         BACKEND: Analysis Request Processing                    │
│                                                                 │
│  POST /api/v1/analysis/start                                    │
│  Request:                                                       │
│  {                                                              │
│    "hold_duration_days": 0,                                     │
│    "investment_amount": 100000,                                 │
│    "max_risk_percent": 2.0                                      │
│  }                                                              │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐   │
│  │ STEP 1: Get Stock Universe                             │   │
│  ├────────────────────────────────────────────────────────┤   │
│  │ If Intraday (hold=0):                                  │   │
│  │ • Call data_service.screen_top_movers()                │   │
│  │ • Returns ~80 stocks (Nifty 50 + Next 50)              │   │
│  │ • Filters by: volume > 100k, price change > 2%         │   │
│  │                                                        │   │
│  │ If Swing (hold>0):                                     │   │
│  │ • Use NSE universe CSV (~2000 stocks)                  │   │
│  │ • Filter by market cap, liquidity                      │   │
│  └────────────────────────────────────────────────────────┘
                              ↓
│  ┌────────────────────────────────────────────────────────┐   │
│  │ STEP 2: Fetch Data & Calculate Indicators              │   │
│  ├────────────────────────────────────────────────────────┤   │
│  │ For Each Stock in Universe:                            │   │
│  │ ┌─────────────────────────────────────────────────┐   │   │
│  │ │ Intraday (hold=0):                              │   │   │
│  │ │ • Zerodha kite.quote() → live prices            │   │   │
│  │ │ • Zerodha kite.historical_data() → 5min candles │   │   │
│  │ │   (last 2 hours for intraday signals)           │   │   │
│  │ │ • Calculate indicators:                         │   │   │
│  │ │   - VWAP, Bollinger Bands                       │   │   │
│  │ │   - RSI, MACD, Stochastic                       │   │   │
│  │ │   - Pivot Points                                │   │   │
│  │ └─────────────────────────────────────────────────┘   │   │
│  │ ┌─────────────────────────────────────────────────┐   │   │
│  │ │ Swing (hold>0):                                 │   │   │
│  │ │ • yfinance.download() → daily candles           │   │   │
│  │ │   (last 30 days for swing signals)              │   │   │
│  │ │ • Calculate indicators:                         │   │   │
│  │ │   - ATR, EMA, RSI, MACD                         │   │   │
│  │ │   - Support/Resistance levels                   │   │   │
│  │ └─────────────────────────────────────────────────┘   │   │
│  └────────────────────────────────────────────────────────┘
                              ↓
│  ┌────────────────────────────────────────────────────────┐   │
│  │ STEP 3: Generate Trading Signals                       │   │
│  ├────────────────────────────────────────────────────────┤   │
│  │ strategy_engine.py → 3 Signal Combos Vote:             │   │
│  │                                                        │   │
│  │ 1️⃣  VWAP+RSI Combo:                                    │   │
│  │     BUY:  Price > VWAP AND RSI 50-70                  │   │
│  │     SELL: Price < VWAP AND RSI 30-50                  │   │
│  │                                                        │   │
│  │ 2️⃣  MACD+RSI Combo:                                    │   │
│  │     BUY:  MACD > 0 AND RSI 40-70                       │   │
│  │     SELL: MACD < 0 AND RSI 30-60                       │   │
│  │                                                        │   │
│  │ 3️⃣  Bollinger Bands+RSI Combo:                         │   │
│  │     BUY:  Near Lower Band AND RSI < 40                │   │
│  │     SELL: Near Upper Band AND RSI > 60                │   │
│  │                                                        │   │
│  │ Majority Voting: If 2+ combos agree → Signal Valid     │   │
│  │ Tiebreaker: EMA alignment (50-day MA direction)        │   │
│  └────────────────────────────────────────────────────────┘
                              ↓
│  ┌────────────────────────────────────────────────────────┐   │
│  │ STEP 4: LLM Analysis & Price Target Generation         │   │
│  ├────────────────────────────────────────────────────────┤   │
│  │ llm_agent.py → OpenAI GPT-4o:                          │   │
│  │                                                        │   │
│  │ Prompt Input:                                          │   │
│  │ "Stock: TCS, Signal: BUY, Current Price: 3750          │   │
│  │  ATR: 45, Support: 3700, Resistance: 3850              │   │
│  │  Historical Win Rate: 62%, Risk Budget: 2000"          │   │
│  │                                                        │   │
│  │ LLM Output:                                            │   │
│  │ {                                                      │   │
│  │   "action": "BUY",                                     │   │
│  │   "entry_price": 3750,                                 │   │
│  │   "target_price": 3850,  (2.7% profit)                │   │
│  │   "stop_loss": 3700,     (1.3% loss)                  │   │
│  │   "confidence": 75,                                    │   │
│  │   "rationale": "Strong reversal signal with RSI..."    │   │
│  │ }                                                      │   │
│  └────────────────────────────────────────────────────────┘
                              ↓
│  ┌────────────────────────────────────────────────────────┐   │
│  │ STEP 5: Risk Sizing & Position Calculation             │   │
│  ├────────────────────────────────────────────────────────┤   │
│  │ risk_engine.py:                                        │   │
│  │                                                        │   │
│  │ Max Loss per Trade = Investment * Max Risk %           │   │
│  │                   = 100,000 * 2% = ₹2,000              │   │
│  │                                                        │   │
│  │ Entry-to-SL Distance = Entry - Stop Loss               │   │
│  │                      = 3750 - 3700 = ₹50                │   │
│  │                                                        │   │
│  │ Quantity = Max Loss / Entry-to-SL Distance             │   │
│  │          = 2000 / 50 = 40 shares                       │   │
│  │                                                        │   │
│  │ Profit Target = Quantity * (Target - Entry)            │   │
│  │               = 40 * (3850 - 3750) = ₹4,000            │   │
│  │ Profit % = 4,000 / 100,000 = 4% 📈                     │   │
│  └────────────────────────────────────────────────────────┘
                              ↓
│  ┌────────────────────────────────────────────────────────┐   │
│  │ STEP 6: Save Analysis to Database                      │   │
│  ├────────────────────────────────────────────────────────┤   │
│  │ INSERT into vantrade_analyses:                         │   │
│  │ - analysis_id (auto)                                   │   │
│  │ - user_id (from session)                               │   │
│  │ - status: "COMPLETED"                                  │   │
│  │ - hold_duration_days: 0                                │   │
│  │ - total_investment: 100000                             │   │
│  │ - max_profit: 4000                                     │   │
│  │ - max_loss: -2000                                      │   │
│  │ - created_at: now()                                    │   │
│  │                                                        │   │
│  │ INSERT into vantrade_stock_recommendations:            │   │
│  │ - recommendation_id (auto)                             │   │
│  │ - analysis_id (FK)                                     │   │
│  │ - stock_symbol: "TCS"                                  │   │
│  │ - action: "BUY"                                        │   │
│  │ - entry_price: 3750                                    │   │
│  │ - stop_loss: 3700                                      │   │
│  │ - target_price: 3850                                   │   │
│  │ - confidence_score: 75                                 │   │
│  │ - rationale: "..."                                     │   │
│  │                                                        │   │
│  │ INSERT into vantrade_signals:                          │   │
│  │ - signal_id (auto)                                     │   │
│  │ - recommendation_id (FK)                               │   │
│  │ - signal_type: "VWAP_RSI"                              │   │
│  │ - signal_value: "BUY"                                  │   │
│  │ - indicator_values: {RSI: 55, VWAP: 3745, ...}        │   │
│  └────────────────────────────────────────────────────────┘
└─────────────────────────────────────────────────────────────────┘
                              ↓
               Loading: "Analyzing 80 stocks..."
                    (3-5 seconds on live data)
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│         ANALYSIS RESULTS SCREEN (Frontend)                      │
│                                                                 │
│  Top Recommendations:                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ 🟢 TCS                                                  │   │
│  │ Action: BUY at ₹3,750                                   │   │
│  │ Target: ₹3,850 (2.7%)  |  Stop Loss: ₹3,700 (-1.3%)   │   │
│  │ Confidence: ⭐⭐⭐⭐⭐ (75%)                               │   │
│  │ [Signals] [Buy] [Reject]                               │   │
│  └─────────────────────────────────────────────────────────┘
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ 🟢 INFY                                                 │   │
│  │ Action: BUY at ₹1,850                                   │   │
│  │ Target: ₹1,920 (3.8%)  |  Stop Loss: ₹1,800 (-2.7%)   │   │
│  │ Confidence: ⭐⭐⭐⭐ (68%)                                │   │
│  │ [Signals] [Buy] [Reject]                               │   │
│  └─────────────────────────────────────────────────────────┘
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ 🔴 HDFC BANK                                            │   │
│  │ Action: SELL at ₹1,950                                  │   │
│  │ Target: ₹1,880 (-3.6%) |  Stop Loss: ₹2,000 (+2.6%)   │   │
│  │ Confidence: ⭐⭐⭐ (62%)                                 │   │
│  │ [Signals] [Sell] [Reject]                              │   │
│  └─────────────────────────────────────────────────────────┘
│                                                             │
│  Summary: 12 BUYs | 5 SELLs | Max Risk: ₹2,000            │
│  Total Potential Profit: ₹4,500 (if all executed)          │
│                                                             │
│  [Execute Selected Trades] [Cancel]                         │
└─────────────────────────────────────────────────────────────┘
```

---

### Phase 4: Order Execution

```
┌─────────────────────────────────────────────────────────────────┐
│     USER CLICKS [EXECUTE SELECTED TRADES]                       │
└─────────────────────────────────────────────────────────────────┘
                              ↓
        ┌──────────────────────────────────┐
        │ Execution Confirmation Dialog     │
        │ "Execute 3 orders? Max Loss: ₹2k"│
        │ [Confirm] [Cancel]                │
        └──────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│         BACKEND: execution_agent.py → Order Placement           │
│                                                                 │
│  POST /api/v1/analysis/execute                                  │
│  Request: { analysis_id, selected_stocks: [TCS, INFY, ...] }   │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐   │
│  │ For Each Selected Stock (TCS, INFY, etc.):             │   │
│  ├────────────────────────────────────────────────────────┤   │
│  │                                                        │   │
│  │ 1️⃣  Check Market Hours (9:15 AM - 3:30 PM IST)         │   │
│  │     ✅ If within hours: Place order immediately        │   │
│  │     ❌ If outside: Schedule for next market open       │   │
│  │                                                        │   │
│  │ 2️⃣  Place ENTRY ORDER via Zerodha:                    │   │
│  │                                                        │   │
│  │     If Intraday (MIS):                                 │   │
│  │     kite.place_order(                                  │   │
│  │       variety="regular",                               │   │
│  │       exchange="NSE",                                  │   │
│  │       tradingsymbol="TCS",                             │   │
│  │       transaction_type="BUY",                          │   │
│  │       quantity=40,                                     │   │
│  │       order_type="MARKET",                             │   │
│  │       product="MIS"  ← Margin Intraday                │   │
│  │     )                                                  │   │
│  │                                                        │   │
│  │     If Swing (CNC):                                    │   │
│  │     kite.place_order(                                  │   │
│  │       ...                                              │   │
│  │       product="CNC"  ← Cash & Carry                    │   │
│  │     )                                                  │   │
│  │                                                        │   │
│  │     Response: {order_id: "123456", status: "COMPLETE"} │   │
│  │                                                        │   │
│  │ 3️⃣  Save ORDER to Database:                           │   │
│  │                                                        │   │
│  │     INSERT into vantrade_orders:                       │   │
│  │     - order_id (auto)                                  │   │
│  │     - user_id (FK)                                     │   │
│  │     - analysis_id (FK)                                 │   │
│  │     - stock_symbol: "TCS"                              │   │
│  │     - action: "BUY"                                    │   │
│  │     - quantity: 40                                     │   │
│  │     - order_status: "FILLED"                           │   │
│  │     - entry_price: 3748 (market fill)                  │   │
│  │     - fill_price: 3748                                 │   │
│  │     - zerodha_order_id: "123456"                       │   │
│  │     - product_type: "MIS"                              │   │
│  │     - created_at: now()                                │   │
│  │     - filled_at: now()                                 │   │
│  │                                                        │   │
│  │ 4️⃣  Place GTT EXIT ORDER (Auto Stop Loss + Target):   │   │
│  │                                                        │   │
│  │     For BUY order (Long):                              │   │
│  │     kite.place_gtt(                                    │   │
│  │       trigger_values: [3700, 3850],  ← SL, Target     │   │
│  │       last_price: 3748,                                │   │
│  │       orders: [                                        │   │
│  │         {                                              │   │
│  │           transaction_type: "SELL",                    │   │
│  │           quantity: 40,                                │   │
│  │           price: 3700,   ← Stop Loss SELL              │   │
│  │           order_type: "LIMIT"                          │   │
│  │         },                                             │   │
│  │         {                                              │   │
│  │           transaction_type: "SELL",                    │   │
│  │           quantity: 40,                                │   │
│  │           price: 3850,   ← Target SELL                 │   │
│  │           order_type: "LIMIT"                          │   │
│  │         }                                              │   │
│  │       ]                                                │   │
│  │     )                                                  │   │
│  │                                                        │   │
│  │     For SELL order (Short):                            │   │
│  │     kite.place_gtt(                                    │   │
│  │       trigger_values: [1880, 2000],  ← Target, SL     │   │
│  │       orders: [                                        │   │
│  │         {                                              │   │
│  │           transaction_type: "BUY",                     │   │
│  │           quantity: 40,                                │   │
│  │           price: 1880,   ← Target BUY (cover)          │   │
│  │           order_type: "LIMIT"                          │   │
│  │         },                                             │   │
│  │         {                                              │   │
│  │           transaction_type: "BUY",                     │   │
│  │           quantity: 40,                                │   │
│  │           price: 2000,   ← SL BUY (cut loss)           │   │
│  │           order_type: "LIMIT"                          │   │
│  │         }                                              │   │
│  │       ]                                                │   │
│  │     )                                                  │   │
│  │                                                        │   │
│  │     Response: {gtt_id: "GTT789", status: "ACTIVE"}    │   │
│  │                                                        │   │
│  │ 5️⃣  Save GTT ORDER to Database:                       │   │
│  │                                                        │   │
│  │     INSERT into vantrade_gtt_orders:                   │   │
│  │     - gtt_id (auto)                                    │   │
│  │     - user_id (FK)                                     │   │
│  │     - order_id (FK)                                    │   │
│  │     - zerodha_gtt_id: "GTT789"                         │   │
│  │     - target_price: 3850                               │   │
│  │     - stop_loss: 3700                                  │   │
│  │     - gtt_status: "ACTIVE"                             │   │
│  │     - created_at: now()                                │   │
│  │                                                        │   │
│  │ 6️⃣  Log Execution Update:                             │   │
│  │                                                        │   │
│  │     INSERT into vantrade_execution_updates:            │   │
│  │     - analysis_id (FK)                                 │   │
│  │     - stock_symbol: "TCS"                              │   │
│  │     - update_type: "ORDER_PLACED"                      │   │
│  │     - update_details: {                                │   │
│  │         zerodha_order_id: "123456",                    │   │
│  │         fill_price: 3748,                              │   │
│  │         quantity: 40,                                  │   │
│  │         gtt_id: "GTT789"                               │   │
│  │       }                                                │   │
│  │     - created_at: now()                                │   │
│  │                                                        │   │
│  └────────────────────────────────────────────────────────┘
│                                                            │
│  Repeat for all selected stocks (TCS, INFY, etc.)         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│         EXECUTION STATUS SCREEN                                 │
│                                                                 │
│  Orders Executed: 3/3                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ✅ TCS       BUY   40 shares @ ₹3,748    GTT: ACTIVE    │   │
│  │ ✅ INFY      BUY   25 shares @ ₹1,848    GTT: ACTIVE    │   │
│  │ ✅ HDFC BK   SELL  15 shares @ ₹1,951    GTT: ACTIVE    │   │
│  │                                                         │   │
│  │ Total Invested: ₹1,50,520                              │   │
│  │ Max Risk Today: ₹2,000                                  │   │
│  │                                                         │   │
│  │ 🟢 All GTT orders placed! System will auto-exit         │   │
│  │ when target/SL is hit. No further action needed.        │   │
│  │                                                         │   │
│  │ ⚠️  Note: For Intraday (MIS), Zerodha will              │   │
│  │ auto-square-off at 3:15 PM. GTT will cancel at 3:20 PM.│   │
│  │                                                         │   │
│  │ [View Open Positions] [Back to Home]                    │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

### Phase 5: Trade Execution & Monitoring

```
┌─────────────────────────────────────────────────────────────────┐
│   REAL-TIME MONITORING (Next minutes/hours)                     │
│                                                                 │
│   Zerodha webhooks / polling:                                   │
│   - Price updates every 1-5 seconds                             │
│   - GTT status changes → Backend receives notification          │
│   - Order fills → vantrade_execution_updates table updated      │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    ┌─────────────┐
                    │ SCENARIO 1: │
                    │ Target Hit! │
                    └─────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  12:45 PM - TCS hits target price of ₹3,850                    │
│                                                                 │
│  GTT Auto-Execution:                                            │
│  1. Zerodha GTT triggers → SELL order placed                    │
│  2. Order filled at ₹3,850 (or better)                          │
│  3. Zerodha sends webhook: GTT_TRIGGERED                        │
│                                                                 │
│  Backend Processing:                                            │
│  ┌────────────────────────────────────────────────────────┐   │
│  │ UPDATE vantrade_gtt_orders:                            │   │
│  │ - gtt_status: "TRIGGERED"                              │   │
│  │ - triggered_at: 12:45 PM                               │   │
│  │                                                        │   │
│  │ INSERT into vantrade_trades:                           │   │
│  │ - trade_id (auto)                                      │   │
│  │ - user_id (FK)                                         │   │
│  │ - entry_order_id (FK)                                  │   │
│  │ - stock_symbol: "TCS"                                  │   │
│  │ - entry_price: 3748                                    │   │
│  │ - exit_price: 3850                                     │   │
│  │ - quantity: 40                                         │   │
│  │ - trade_status: "CLOSED"                               │   │
│  │ - pnl: (3850-3748)*40 = ₹4,080                        │   │
│  │ - pnl_percent: (102/3748)*100 = 2.72%                 │   │
│  │ - entry_at: 10:00 AM                                   │   │
│  │ - exit_at: 12:45 PM                                    │   │
│  │                                                        │   │
│  │ INSERT into vantrade_execution_updates:                │   │
│  │ - update_type: "GTT_TRIGGERED"                         │   │
│  │ - update_details: {exit_price: 3850, pnl: 4080}       │   │
│  │                                                        │   │
│  │ Audit Log:                                             │   │
│  │ INSERT into vantrade_audit_logs:                       │   │
│  │ - action: "TRADE_CLOSED"                               │   │
│  │ - resource_type: "Trade"                               │   │
│  │ - resource_id: "trade_123"                             │   │
│  │ - update_details: {pnl: 4080, status: "CLOSED"}       │   │
│  └────────────────────────────────────────────────────────┘
│                                                            │
│  Frontend Update:                                          │
│  User sees: ✅ TCS - Target Hit! +₹4,080 profit          │
└─────────────────────────────────────────────────────────────────┘
```

```
                    ┌─────────────┐
                    │ SCENARIO 2: │
                    │ Stop Loss   │
                    │ Hit (Loss)  │
                    └─────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  11:30 AM - INFY drops to stop loss ₹1,800                     │
│                                                                 │
│  Backend Processing (same as above, but):                       │
│  - exit_price: 1800                                             │
│  - pnl: (1800-1848)*25 = -₹1,200                              │
│  - pnl_percent: (-48/1848)*100 = -2.60%                       │
│                                                                 │
│  Frontend Update:                                               │
│  User sees: 🔴 INFY - Stop Loss Hit! -₹1,200 loss             │
└─────────────────────────────────────────────────────────────────┘
```

```
                    ┌─────────────┐
                    │ SCENARIO 3: │
                    │ End of Day  │
                    │ (Intraday   │
                    │ MIS Auto    │
                    │ Squareoff)  │
                    └─────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  3:15 PM - Zerodha auto-squares off all MIS positions           │
│                                                                 │
│  HDFC BANK short position:                                      │
│  - Entry: SELL @ ₹1,951 (15 shares)                             │
│  - Exit: BUY @ ₹1,945 (auto squareoff price)                    │
│  - pnl: (1951-1945)*15 = ₹90                                   │
│  - pnl_percent: (6/1951)*100 = 0.31%                           │
│                                                                 │
│  Backend:                                                        │
│  INSERT into vantrade_trades:                                   │
│  - trade_status: "CLOSED"                                       │
│  - exit_price: 1945                                             │
│  - pnl: 90                                                      │
│  - exit_at: 3:15 PM                                             │
│                                                                 │
│  Frontend Notification:                                         │
│  "Auto Squareoff: HDFC BANK closed at ₹1,945. Profit: +₹90"    │
└─────────────────────────────────────────────────────────────────┘
```

---

### Phase 6: Dashboard & Performance Tracking

```
┌─────────────────────────────────────────────────────────────────┐
│              DASHBOARD SCREEN (After Trading)                   │
│                                                                 │
│  Today's Performance                          Last 7 Days       │
│  ┌──────────────────────────────────────┐  ┌──────────────┐   │
│  │ Total Trades:      3                 │  │ Win Rate: 67%│   │
│  │ Winning Trades:    2 (66.7%)         │  │ Profit:₹5,170│   │
│  │ Losing Trades:     1 (33.3%)         │  │ Loss: -₹1,200│   │
│  │ Total P&L:         +₹3,170           │  │ Net:  +₹3,970│   │
│  │ Best Trade:        +₹4,080 (TCS)     │  │               │   │
│  │ Worst Trade:       -₹1,200 (INFY)    │  │               │   │
│  │ Profit Factor:     3.4                │  │               │   │
│  │ Max Drawdown:      -2.6%              │  │               │   │
│  └──────────────────────────────────────┘  └──────────────┘   │
│                                                                 │
│  Trade History                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Time  │ Stock    │ Action │ Entry  │ Exit   │ P&L      │  │
│  ├──────────────────────────────────────────────────────────┤  │
│  │ 12:45 │ TCS      │ BUY    │ 3748   │ 3850   │ +₹4,080 ✅│  │
│  │ 11:30 │ INFY     │ BUY    │ 1848   │ 1800   │ -₹1,200 🔴│  │
│  │ 03:15 │ HDFC BK  │ SELL   │ 1951   │ 1945   │ +₹90   ✅│  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  [Detailed Analysis] [Export] [Settings]                       │
└─────────────────────────────────────────────────────────────────┘
```

**Database Updates for Dashboard:**

```sql
-- Daily Performance calculated from vantrade_trades
INSERT INTO vantrade_daily_performances:
- performance_date: "2026-03-04"
- user_id: 1
- total_trades: 3
- winning_trades: 2
- losing_trades: 1
- total_pnl: 3170
- best_trade: 4080
- worst_trade: -1200

-- Monthly Performance (aggregate)
INSERT INTO vantrade_monthly_performances:
- user_id: 1
- year: 2026
- month: 3
- total_trades: 15 (cumulative)
- winning_trades: 10
- losing_trades: 5
- win_rate: 66.7%
- total_pnl: 12500
- avg_win: 1250
- avg_loss: -500
- profit_factor: 2.5
- max_drawdown: -5.2%
```

---

## 🔄 Complete Data Flow Diagram

```
┌──────────────┐
│ Flutter App  │
└──────────────┘
       │
       │ (HTTPS REST API)
       ↓
┌─────────────────────────────────────────────┐
│       FastAPI Backend (app/main.py)         │
├─────────────────────────────────────────────┤
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │ API Routes:                          │  │
│  │ • /api/v1/auth/* → Authentication   │  │
│  │ • /api/v1/analysis/* → Analysis     │  │
│  │ • /api/validate-zerodha-credentials │  │
│  │ • /api/v1/dashboard/* → Performance │  │
│  └──────────────────────────────────────┘  │
│                    ↓                         │
│  ┌──────────────────────────────────────┐  │
│  │ Services:                            │  │
│  │ • ZerodhaService → Kite Connect API │  │
│  │ • DataService → NSE screener        │  │
│  │ • AnalysisService → Stock screening │  │
│  │ • OrderService → Order management   │  │
│  └──────────────────────────────────────┘  │
│                    ↓                         │
│  ┌──────────────────────────────────────┐  │
│  │ Engines:                             │  │
│  │ • StrategyEngine → Signal generation │  │
│  │ • RiskEngine → Position sizing       │  │
│  │ • PerformanceEngine → Metrics calc.  │  │
│  └──────────────────────────────────────┘  │
│                    ↓                         │
│  ┌──────────────────────────────────────┐  │
│  │ Agents:                              │  │
│  │ • LLMAgent → GPT-4o prompts          │  │
│  │ • ExecutionAgent → Place orders      │  │
│  └──────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
       ↓                              ↓
   (HTTP)                        (pyodbc)
       ↓                              ↓
┌─────────────────┐        ┌──────────────────────┐
│ Zerodha API     │        │ Azure SQL Database   │
│ - Place Orders  │        ├──────────────────────┤
│ - Get Quotes    │        │ vantrade_users       │
│ - Get History   │        │ vantrade_analyses    │
│ - Place GTT     │        │ vantrade_orders      │
│ - Get Status    │        │ vantrade_trades      │
└─────────────────┘        │ vantrade_gtt_orders  │
                           │ vantrade_audit_logs  │
                           │ + 10 more tables...  │
                           └──────────────────────┘
```

---

## 🔐 Security & Authentication Flow

```
┌────────────────────────────────────────────────────────────┐
│ 1. USER AUTHENTICATION                                     │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  Flutter App → Zerodha OAuth                              │
│  Returns: zerodha_user_id, access_token                   │
│                                                            │
│  Backend:                                                  │
│  ├─ Check if zerodha_user_id exists in vantrade_users    │
│  ├─ If YES: Load user data                                │
│  ├─ If NO: Create new user                                │
│  └─ Generate session token                                │
│                                                            │
│  INSERT into vantrade_sessions:                            │
│  - session_id (auto)                                       │
│  - user_id (FK)                                            │
│  - access_token (encrypted JWT)                            │
│  - ip_address: "192.168.1.100"                             │
│  - is_active: true                                         │
│  - created_at: now()                                       │
│                                                            │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│ 2. API CREDENTIAL ENCRYPTION                               │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  User enters API Key + Secret on ApiSettingsScreen        │
│                                                            │
│  Backend:                                                  │
│  1. Receive plaintext credentials                         │
│  2. Load ENCRYPTION_KEY from .env                         │
│  3. Encrypt with Fernet:                                  │
│                                                            │
│     from cryptography.fernet import Fernet                │
│     cipher = Fernet(ENCRYPTION_KEY)                       │
│     api_key_encrypted = cipher.encrypt(api_key.encode())  │
│     api_secret_encrypted = cipher.encrypt(secret.encode())│
│                                                            │
│  4. Store encrypted values in DB:                         │
│     INSERT vantrade_api_credentials:                      │
│     - user_id (FK)                                         │
│     - api_key_encrypted: "abc123def456..."                │
│     - api_secret_encrypted: "xyz789uvw012..."             │
│     - is_valid: true                                       │
│                                                            │
│  5. Use encrypted credentials when needed:                │
│     SELECT * FROM vantrade_api_credentials WHERE user_id  │
│     cipher.decrypt(api_key_encrypted) → plaintext         │
│     → Use with Zerodha API                                │
│                                                            │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│ 3. AUDIT TRAIL & COMPLIANCE                                │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  Every important action logged:                            │
│                                                            │
│  vantrade_audit_logs:                                      │
│  - USER_LOGIN: {zerodha_user_id, ip, timestamp}           │
│  - ANALYSIS_CREATED: {analysis_id, stocks, parameters}    │
│  - TRADE_EXECUTED: {order_id, symbol, qty, price}         │
│  - TRADE_CLOSED: {pnl, exit_reason, timestamp}            │
│                                                            │
│  vantrade_api_call_logs:                                   │
│  - Every Zerodha API call tracked                          │
│  - Response time, status, error (if any)                  │
│                                                            │
│  vantrade_error_logs:                                      │
│  - Connection failures, validation errors                 │
│  - Stack traces + context for debugging                   │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

---

## 📊 Summary: End-to-End Value Chain

```
User Investment: ₹100,000
        ↓
    [Onboarding]
        ↓
    [Login + API Setup]
        ↓
    [Start Analysis]
        ↓
    [Screen 80 stocks] → Filter by signals
        ↓
    [Generate Recommendations] → LLM validation
        ↓
    [Risk Sizing] → Position calculation
        ↓
    [Execute Trades] → Zerodha orders
        ↓
    [Place GTT Orders] → Auto exit
        ↓
    [Monitor Positions] → Real-time updates
        ↓
    [Close Trades] → P&L calculation
        ↓
    [Track Performance] → Daily/Monthly metrics
        ↓
    Outcome: Profit/Loss + Learnings for next trade
```

---

## 🎯 Key Integration Points

| Component | Integration | Data Storage |
|-----------|-------------|--------------|
| Flutter App | REST API | Device (encrypted) |
| FastAPI Backend | SQLModel ORM | Azure SQL |
| Zerodha | HTTP + Webhooks | vantrade_orders |
| OpenAI | HTTP API | vantrade_signals |
| Database | SQLAlchemy | 16 tables |
| Audit | Middleware | vantrade_audit_logs |

---

This is the **complete end-to-end flow** of VanTrade. Every piece connects to create a seamless experience from user login → stock analysis → trade execution → performance tracking.