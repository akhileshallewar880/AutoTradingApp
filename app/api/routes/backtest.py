from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from typing import List, Optional
from app.engines.backtest_engine import backtest_engine, BacktestRequest, NIFTY_UNIVERSE
from app.core.logging import logger

router = APIRouter()


class BacktestRequestBody(BaseModel):
    symbols: Optional[List[str]] = Field(
        default=None,
        description="Stock symbols to test. Leave empty to use full Nifty 50 universe.",
        example=["RELIANCE", "TCS", "INFY"],
    )
    start_date: str = Field(
        default="2024-01-01",
        description="Backtest start date (YYYY-MM-DD)",
    )
    end_date: Optional[str] = Field(
        default=None,
        description="Backtest end date (YYYY-MM-DD). Defaults to yesterday.",
    )
    sl_atr_multiplier: float = Field(
        default=1.5,
        ge=0.5,
        le=5.0,
        description="Stop-loss = entry ± ATR × multiplier",
    )
    target_rr: float = Field(
        default=2.0,
        ge=0.5,
        le=10.0,
        description="Target = SL_distance × RR ratio (risk-reward)",
    )
    min_signal_strength: int = Field(
        default=2,
        ge=1,
        le=5,
        description="Minimum number of indicator combos that must agree (1–5)",
    )
    max_hold_bars: int = Field(
        default=5,
        ge=1,
        le=30,
        description="Exit at close after N days if neither SL nor target is hit",
    )
    include_short: bool = Field(
        default=True,
        description="Whether to backtest SELL (short) signals in addition to BUY",
    )
    include_trades_detail: bool = Field(
        default=True,
        description="Include per-trade detail rows in the response",
    )


@router.post("/run")
async def run_backtest(body: BacktestRequestBody):
    """
    Run a full backtest of the current strategy on historical daily data.

    **Signal logic** (identical to live strategy):
    - Combo 1: VWAP-20 (rolling proxy) + RSI
    - Combo 2: MACD histogram + RSI + crossover detection
    - Combo 3: Bollinger Bands + RSI
    - Combo 4: EMA 9/21 trend alignment
    - Combo 5: Stochastic %K/%D

    **Entry**: next bar's open after signal fires.
    **Exit**:
    - WIN  → target hit (bar high ≥ target for BUY; bar low ≤ target for SELL)
    - LOSS → SL hit (bar low ≤ SL for BUY; bar high ≥ SL for SELL)
    - TIMEOUT → neither hit within `max_hold_bars` days, exit at close

    **Report includes**: win rate, profit factor, expected value, max drawdown,
    Sharpe ratio, breakdown by signal type, signal strength, and per-symbol stats.
    """
    try:
        req = BacktestRequest(
            symbols=body.symbols or [],
            start_date=body.start_date,
            end_date=body.end_date or "",
            sl_atr_multiplier=body.sl_atr_multiplier,
            target_rr=body.target_rr,
            min_signal_strength=body.min_signal_strength,
            max_hold_bars=body.max_hold_bars,
            include_short=body.include_short,
            include_trades_detail=body.include_trades_detail,
        )

        logger.info(
            f"[Backtest-API] Request: symbols={len(req.symbols) or 'NIFTY_UNIVERSE'} "
            f"| {req.start_date}→{req.end_date or 'today-1'} "
            f"| SL×{req.sl_atr_multiplier} RR×{req.target_rr} "
            f"| min_strength={req.min_signal_strength}"
        )

        report = await backtest_engine.run_backtest(req)
        return report

    except Exception as e:
        logger.error(f"[Backtest-API] Failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Backtest failed: {str(e)}")


@router.get("/universe")
async def get_universe():
    """Returns the default Nifty 50 universe used when no symbols are specified."""
    return {"symbols": NIFTY_UNIVERSE, "count": len(NIFTY_UNIVERSE)}
