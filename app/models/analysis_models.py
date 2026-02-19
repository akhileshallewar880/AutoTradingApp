from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime, date


class AnalysisRequest(BaseModel):
    analysis_date: date = Field(..., description="Date for analysis (YYYY-MM-DD)")
    num_stocks: int = Field(..., gt=0, le=50, description="Number of top stocks to analyze")
    risk_percent: float = Field(1.0, gt=0.0, le=5.0, description="Risk percentage per trade")
    access_token: str = Field(..., description="User's Zerodha access token")
    sectors: List[str] = Field(
        default=["ALL"],
        description="Stock sectors to include. Use ['ALL'] for entire NSE market."
    )
    hold_duration_days: int = Field(
        default=0,
        ge=0,
        description="Hold duration in days. 0 = Intraday. Stocks auto-sold after this period."
    )


class StockAnalysis(BaseModel):
    stock_symbol: str
    company_name: Optional[str] = None
    action: str = Field(..., pattern="^(BUY|SELL|HOLD)$")
    entry_price: float
    stop_loss: float
    target_price: float
    quantity: int
    risk_amount: float
    potential_profit: float
    potential_loss: float
    risk_reward_ratio: float
    confidence_score: float = Field(..., ge=0.0, le=1.0)
    ai_reasoning: str
    days_to_target: Optional[int] = Field(
        default=None,
        description="LLM-estimated trading days to reach target price"
    )
    technical_indicators: Optional[dict] = None


class AnalysisResponse(BaseModel):
    analysis_id: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
    request: AnalysisRequest
    stocks: List[StockAnalysis]
    portfolio_metrics: dict  # total_investment, total_risk, max_profit, max_loss, etc.
    available_balance: float
    status: str = "PENDING_CONFIRMATION"  # PENDING_CONFIRMATION, CONFIRMED, EXECUTING, COMPLETED, CANCELLED


class OrderConfirmation(BaseModel):
    confirmed: bool
    access_token: str  # User's Zerodha access token for executing trades
    user_notes: Optional[str] = None
    hold_duration_days: int = Field(
        default=0,
        description="Hold duration in days passed from the app"
    )
    stock_overrides: Optional[List[dict]] = Field(
        default=None,
        description="Per-stock quantity overrides from user edits. Each entry: {stock_symbol, quantity}"
    )


class ExecutionUpdate(BaseModel):
    analysis_id: str
    stock_symbol: str
    update_type: str  # ORDER_PLACED, ORDER_FILLED, GTT_PLACED, GTT_TRIGGERED, COMPLETED, ERROR
    message: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    order_id: Optional[str] = None
    details: Optional[dict] = None


class ExecutionStatus(BaseModel):
    analysis_id: str
    overall_status: str  # EXECUTING, COMPLETED, PARTIAL, FAILED
    total_stocks: int
    completed_stocks: int
    failed_stocks: int
    updates: List[ExecutionUpdate]
    created_at: datetime
    updated_at: datetime
