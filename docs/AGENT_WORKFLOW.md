# Enhanced AI Trading Agent - Complete Workflow Guide

## Overview
This system provides an intelligent trading agent that analyzes markets, provides detailed recommendations, and executes trades automatically with user confirmation.

## Complete Workflow

### Step 1: Generate AI Analysis
**Endpoint**: `POST /api/v1/analysis/generate`

Input your trading parameters and get AI-powered stock recommendations.

**Request**:
```json
{
  "analysis_date": "2026-02-17",
  "num_stocks": 10,
  "risk_percent": 1.5
}
```

**Response**:
```json
{
  "analysis_id": "abc-123-xyz",
  "stocks": [
    {
      "stock_symbol": "RELIANCE",
      "company_name": "Reliance Industries",
      "action": "BUY",
      "entry_price": 2500.50,
      "stop_loss": 2450.00,
      "target_price": 2600.00,
      "quantity": 10,
      "risk_amount": 505.00,
      "potential_profit": 995.00,
      "potential_loss": 505.00,
      "risk_reward_ratio": 1.97,
      "confidence_score": 0.85,
      "ai_reasoning": "Strong bullish trend with RSI at 65..."
    }
  ],
  "portfolio_metrics": {
    "total_investment": 25005.00,
    "total_risk": 505.00,
    "max_profit": 995.00,
    "max_loss": 505.00
  },
  "available_balance": 100000.00,
  "status": "PENDING_CONFIRMATION"
}
```

### Step 2: Review & Confirm
**Endpoint**: `POST /api/v1/analysis/{analysis_id}/confirm`

After reviewing the AI recommendations, confirm to start execution.

**Request**:
```json
{
  "confirmed": true,
  "user_notes": "Looks good, proceed with execution"
}
```

**Response**:
```json
{
  "status": "executing",
  "message": "Trade execution started",
  "analysis_id": "abc-123-xyz"
}
```

### Step 3: Monitor Execution
**Endpoint**: `GET /api/v1/analysis/{analysis_id}/status`

Track real-time execution progress.

**Response**:
```json
{
  "analysis_id": "abc-123-xyz",
  "overall_status": "EXECUTING",
  "total_stocks": 10,
  "completed_stocks": 3,
  "failed_stocks": 0,
  "updates": [
    {
      "stock_symbol": "RELIANCE",
      "update_type": "ORDER_PLACED",
      "message": "BUY order placed for 10 shares",
      "order_id": "230217000123456"
    },
    {
      "stock_symbol": "RELIANCE",
      "update_type": "ORDER_FILLED",
      "message": "BUY order filled at ₹2500.50"
    },
    {
      "stock_symbol": "RELIANCE",
      "update_type": "GTT_PLACED",
      "message": "GTT placed with SL: ₹2450, Target: ₹2600"
    },
    {
      "stock_symbol": "RELIANCE",
      "update_type": "COMPLETED",
      "message": "Trade execution completed"
    }
  ]
}
```

## Execution Update Types

- **ORDER_PLACING**: Preparing to place order
- **ORDER_PLACED**: Order placed successfully
- **ORDER_MONITORING**: Monitoring order status
- **ORDER_FILLED**: Order executed/filled
- **GTT_PLACING**: Preparing GTT order
- **GTT_PLACED**: GTT placed successfully
- **COMPLETED**: Trade fully executed
- **ERROR**: Something went wrong

## View History
**Endpoint**: `GET /api/v1/analysis/history?limit=20`

Get past analyses and their status.

## How It Works

1. **Data Collection**: Fetches top volume NSE stocks
2. **Technical Analysis**: Calculates ATR, RSI, SMA, volume metrics
3. **AI Reasoning**: OpenAI analyzes and recommends best opportunities
4. **Risk Management**: Calculates position sizing based on your risk %
5. **User Review**: You see detailed P&L projections
6. **Auto Execution**: 
   - Places BUY orders
   - Waits for order fill confirmation
   - Places GTT for automatic target/stop-loss
7. **Real-time Tracking**: Monitor each step via status endpoint

## Testing the Complete Flow

```bash
# 1. Generate analysis
curl -X POST http://localhost:8000/api/v1/analysis/generate \
  -H "Content-Type: application/json" \
  -d '{
    "analysis_date": "2026-02-17",
    "num_stocks": 5,
    "risk_percent": 1.0
  }'

# 2. Confirm (replace {analysis_id} with response from step 1)
curl -X POST http://localhost:8000/api/v1/analysis/{analysis_id}/confirm \
  -H "Content-Type: application/json" \
  -d '{"confirmed": true}'

# 3. Monitor status (poll this every few seconds)
curl http://localhost:8000/api/v1/analysis/{analysis_id}/status

# 4. View history
curl http://localhost:8000/api/v1/analysis/history
```

## Important Notes

- Ensure you have valid Zerodha access token in `.env`
- GTT orders are placed only AFTER buy orders are filled
- All trades use CNC (delivery) product type for GTT compatibility
- System monitors order status every 2 seconds with 5-minute timeout
- All execution updates are stored in `analyses.json`
