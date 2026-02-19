from pydantic import BaseModel, Field, field_validator

class AgentRunRequest(BaseModel):
    number_of_stocks: int = Field(..., gt=0, le=50, description="Number of top volume stocks to scan")
    risk_percent: float = Field(..., gt=0.0, le=5.0, description="Risk percentage per trade")
    timeframe: str = Field("day", description="Candle timeframe (e.g., 'day', '60min')")

    @field_validator('timeframe')
    def validate_timeframe(cls, v):
        allowed = ['day', '60min', '30min', '15min', '5min']
        if v not in allowed:
            raise ValueError(f"Timeframe must be one of {allowed}")
        return v
