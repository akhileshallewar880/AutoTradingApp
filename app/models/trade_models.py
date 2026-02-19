from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional

class Trade(BaseModel):
    id: str
    symbol: str
    entry_price: float
    stop_loss: float
    target_price: float
    quantity: int
    risk_amount: float
    status: str = "OPEN" # OPEN, CLOSED, CANCELLED
    pnl: Optional[float] = 0.0
    entry_time: datetime = Field(default_factory=datetime.utcnow)
    exit_time: Optional[datetime] = None
    strategy_name: str = "VolumeBreakout" 
