from fastapi import APIRouter, Query
from app.models.response_models import MonthlyPerformanceResponse
from app.engines.performance_engine import performance_engine
from app.models.trade_models import Trade
from app.core.logging import logger
from datetime import datetime
from typing import Optional

router = APIRouter()


@router.get("/monthly-performance", response_model=MonthlyPerformanceResponse)
async def get_monthly_performance(
    access_token: Optional[str] = Query(None),
    api_key: Optional[str] = Query(None),
):
    """
    Returns performance metrics for the current month from Zerodha trade history.
    Requires access_token and api_key query params for live data.
    """
    trades = []

    if access_token and api_key:
        try:
            import asyncio
            from kiteconnect import KiteConnect

            kite = KiteConnect(api_key=api_key)
            kite.set_access_token(access_token)

            loop = asyncio.get_event_loop()
            raw_trades = await loop.run_in_executor(None, kite.trades)

            now = datetime.now()
            for t in raw_trades:
                trade_time = t.get("fill_timestamp") or t.get("exchange_timestamp")
                if trade_time:
                    if hasattr(trade_time, "month"):
                        if trade_time.month != now.month or trade_time.year != now.year:
                            continue
                    else:
                        try:
                            dt = datetime.fromisoformat(str(trade_time))
                            if dt.month != now.month or dt.year != now.year:
                                continue
                        except Exception:
                            pass

                avg_price = float(t.get("average_price") or t.get("price") or 0)
                qty = int(t.get("quantity") or t.get("filled_quantity") or 0)
                action = (t.get("transaction_type") or "BUY").upper()
                symbol = t.get("tradingsymbol", "")

                if avg_price > 0 and qty > 0:
                    trades.append(Trade(
                        id=t.get("order_id", ""),
                        symbol=symbol,
                        action=action,
                        entry_price=avg_price,
                        exit_price=avg_price,
                        quantity=qty,
                        pnl=0.0,
                        pnl_percent=0.0,
                        entry_time=datetime.now(),
                        exit_time=datetime.now(),
                    ))

            logger.info(f"Fetched {len(trades)} trades from Zerodha for monthly performance")

        except Exception as e:
            logger.warning(f"Could not fetch trades from Zerodha: {e}")

    metrics = performance_engine.calculate_monthly_metrics(trades)

    return MonthlyPerformanceResponse(
        total_pnl=metrics["total_pnl"],
        win_rate=metrics["win_rate"],
        max_drawdown=metrics["max_drawdown"],
        total_trades=metrics["total_trades"],
        month=datetime.now().strftime("%B %Y"),
    )
