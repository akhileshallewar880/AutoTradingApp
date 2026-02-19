from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime

class TradeSignal(BaseModel):
    stock_symbol: str
    action: str = Field(..., pattern="^(BUY|SELL)$")
    entry_price: float
    stop_loss: float
    target_price: float
    confidence_score: float = Field(..., ge=0.0, le=1.0)
    reasoning: str

class TradeRecommendationResponse(BaseModel):
    trades: List[TradeSignal]

class AgentRunResponse(BaseModel):
    execution_id: str
    status: str
    generated_trades: List[TradeSignal]
    timestamp: datetime = Field(default_factory=datetime.utcnow)

class MonthlyPerformanceResponse(BaseModel):
    total_pnl: float
    win_rate: float
    max_drawdown: float
    total_trades: int
    month: str
