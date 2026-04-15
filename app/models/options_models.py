from pydantic import BaseModel, Field
from typing import Optional, Union
from datetime import datetime, date


class OptionsRequest(BaseModel):
    index: str = Field(..., description="Index to trade options on: NIFTY or BANKNIFTY")
    expiry_date: date = Field(..., description="Option expiry date (YYYY-MM-DD)")
    risk_percent: float = Field(1.0, gt=0.0, le=5.0, description="Risk percentage of capital per trade")
    capital_to_use: float = Field(..., gt=0, description="Capital to deploy for this trade")
    access_token: str = Field(..., description="User's Zerodha access token")
    api_key: str = Field(..., description="User's Zerodha API key")
    user_id: Optional[Union[int, str]] = Field(None, description="User ID (numeric VanTrade ID or Zerodha string ID)")
    lots: int = Field(default=1, ge=1, le=50, description="Number of lots to trade")
    leverage_multiplier: float = Field(default=1.0, ge=1.0, le=5.0, description="Risk multiplier: 1×=normal, 2×=double risk, up to 5×")


class OptionsTrade(BaseModel):
    """A single options trade recommendation."""
    option_symbol: str              # e.g. NIFTY25APR22500CE
    index: str                      # NIFTY or BANKNIFTY
    option_type: str                # CE or PE
    strike_price: float
    expiry_date: date
    lot_size: int                   # Zerodha lot size (NIFTY=75, BANKNIFTY=30)
    lots: int                       # Number of lots recommended
    quantity: int                   # lots × lot_size
    instrument_token: int

    # Premium levels (per unit)
    entry_premium: float            # Buy at this premium
    stop_loss_premium: float        # Exit if premium drops to this
    target_premium: float           # Exit when premium reaches this

    # Risk/reward
    total_investment: float         # entry_premium × quantity
    max_loss: float                 # (entry_premium - stop_loss_premium) × quantity
    max_profit: float               # (target_premium - entry_premium) × quantity
    risk_reward_ratio: float

    confidence_score: float = Field(..., ge=0.0, le=1.0)
    suggested_hold_minutes: int = 30       # how long to hold before time-based exit
    hold_reasoning: str = ""               # why that duration
    ai_reasoning: str

    # Index context
    current_index_price: float
    signal: str                     # BUY_CE or BUY_PE


class OptionsAnalysisResponse(BaseModel):
    analysis_id: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
    index: str
    current_index_price: float
    expiry_date: date
    trade: Optional[OptionsTrade] = None
    index_indicators: dict
    status: str = "PENDING_CONFIRMATION"  # PENDING_CONFIRMATION, CONFIRMED, EXECUTING, COMPLETED
    # Regime-based engine fields (v2)
    regime: str = "UNKNOWN"                  # TRENDING_UP | TRENDING_DOWN | CHOPPY | SIDEWAYS
    signal_reasons: list = Field(default_factory=list)    # gates passed
    failed_filters: list = Field(default_factory=list)    # gates failed / why NO_TRADE
    or_high: float = 0.0                     # opening range high
    or_low:  float = 0.0                     # opening range low
    adx:     float = 0.0                     # trend strength


class OptionsConfirmation(BaseModel):
    confirmed: bool
    access_token: str
    api_key: str


class OptionsExpiriesResponse(BaseModel):
    index: str
    expiries: list  # List of date strings YYYY-MM-DD


class SessionStartRequest(BaseModel):
    """Request to start a live continuous trading session."""
    index: str = Field(..., description="NIFTY or BANKNIFTY")
    expiry_date: date = Field(..., description="Option expiry date YYYY-MM-DD")
    capital_to_use: float = Field(..., gt=0, description="Capital to deploy")
    lots: int = Field(default=1, ge=1, le=50, description="Lots per trade")
    risk_percent: float = Field(1.0, gt=0.0, le=5.0, description="Risk % of capital per trade")
    api_key: str = Field(..., description="User's Zerodha API key")
    access_token: str = Field(..., description="User's Zerodha access token")
    user_id: Optional[Union[int, str]] = None


class MonitorResumeRequest(BaseModel):
    """Sent by the client to re-attach monitoring after a server restart."""
    symbol: str = Field(..., description="Zerodha tradingsymbol e.g. NIFTY2640722200CE")
    option_type: str = Field(..., description="CE or PE")
    quantity: int = Field(..., gt=0)
    fill_price: float = Field(..., gt=0, description="Actual fill price from execution")
    sl_order_id: str = Field(..., description="Zerodha order ID of the active SL order")
    target_order_id: str = Field(..., description="Zerodha order ID of the active target order")
    sl_trigger: float = Field(..., gt=0, description="Current SL trigger price")
    sl_limit: float = Field(..., gt=0, description="Current SL limit price")
    target_price: float = Field(..., gt=0, description="Target premium price")
    instrument_token: int = Field(0, description="Zerodha instrument token for WebSocket subscription")
    api_key: str
    access_token: str
