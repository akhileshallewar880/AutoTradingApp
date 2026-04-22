from fastapi import APIRouter, Query, HTTPException
from app.models.response_models import MonthlyPerformanceResponse
from app.core.logging import logger
from datetime import datetime
from typing import Optional
import asyncio

router = APIRouter()


def _safe_float(val, default=0.0) -> float:
    try:
        return float(val) if val is not None else default
    except (TypeError, ValueError):
        return default


@router.get("/monthly-performance", response_model=MonthlyPerformanceResponse)
async def get_monthly_performance(
    access_token: str = Query(...),
    api_key: str = Query(...),
    user_id: Optional[str] = Query(None),   # kept for API compat, not used
):
    """
    Returns current-month trading performance directly from Zerodha.

    Sources:
    - kite.positions() → day positions for realized P&L, wins/losses
    - kite.trades()    → today's executed fills for trade count & gross figures
    """
    now = datetime.now()
    month_label = now.strftime("%B %Y")

    try:
        from kiteconnect import KiteConnect
        kite = KiteConnect(api_key=api_key)
        kite.set_access_token(access_token)
        loop = asyncio.get_event_loop()

        positions_raw, trades_raw = await asyncio.gather(
            loop.run_in_executor(None, kite.positions),
            loop.run_in_executor(None, kite.trades),
            return_exceptions=True,
        )

        if isinstance(positions_raw, Exception) and isinstance(trades_raw, Exception):
            raise HTTPException(
                status_code=500,
                detail="Failed to fetch data from Zerodha. Please try again."
            )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[PERF] Zerodha fetch failed: {e}")
        raise HTTPException(status_code=500, detail=f"Zerodha fetch failed: {e}")

    # ── Realized P&L from day positions ──────────────────────────────────────
    realized_pnl = 0.0
    gross_profit = 0.0
    gross_loss = 0.0
    winning_positions = 0
    losing_positions = 0
    unrealized_pnl = 0.0

    if isinstance(positions_raw, dict):
        day_positions = positions_raw.get("day", [])
        net_positions = positions_raw.get("net", [])
        day_symbols: set = set()

        for pos in day_positions:
            sym = pos.get("tradingsymbol", "")
            day_symbols.add(sym)
            pnl = _safe_float(pos.get("pnl"))
            realized_pnl += _safe_float(pos.get("realised") or pnl)
            if pnl > 0:
                gross_profit += pnl
                winning_positions += 1
            elif pnl < 0:
                gross_loss += abs(pnl)
                losing_positions += 1

        for pos in net_positions:
            if pos.get("tradingsymbol", "") in day_symbols:
                continue
            if int(pos.get("quantity") or 0) == 0:
                continue
            unrealized_pnl += _safe_float(pos.get("unrealised") or pos.get("pnl"))

    # ── Trade counts from tradebook ───────────────────────────────────────────
    total_trades = 0
    total_charges = 0.0

    if isinstance(trades_raw, list):
        total_trades = len(trades_raw)
        # Zerodha equity CNC charges: ₹0 brokerage + STT 0.1% on sell + misc ~₹5–8 per trade
        # Use a conservative flat estimate since exact charges are not in the tradebook
        for t in trades_raw:
            qty   = _safe_float(t.get("quantity") or t.get("filled_quantity") or 0)
            price = _safe_float(t.get("price") or t.get("average_price") or 0)
            txn   = str(t.get("transaction_type") or "").upper()
            if qty <= 0 or price <= 0:
                continue
            turnover = qty * price
            # CNC equity: STT 0.1% on sell, exchange 0.00345%, SEBI 0.000001%, GST 18% on exchange
            stt        = turnover * 0.001   if txn == "SELL" else 0.0
            exchange   = turnover * 0.0000345
            sebi       = turnover * 0.000001
            gst        = (exchange) * 0.18
            stamp      = turnover * 0.00015 if txn == "BUY"  else 0.0
            total_charges += stt + exchange + sebi + gst + stamp

    total_charges = round(total_charges, 2)
    total_pnl = round(realized_pnl + unrealized_pnl, 2)
    net_pnl   = round(total_pnl - total_charges, 2)

    total_closed = winning_positions + losing_positions
    win_rate = round((winning_positions / total_closed) * 100, 1) if total_closed > 0 else 0.0

    logger.info(
        f"[PERF] {month_label} — P&L: ₹{total_pnl:.2f}, trades: {total_trades}, "
        f"wins: {winning_positions}, losses: {losing_positions}, win_rate: {win_rate}%"
    )

    return MonthlyPerformanceResponse(
        month=month_label,
        realized_pnl=round(realized_pnl, 2),
        unrealized_pnl=round(unrealized_pnl, 2),
        total_pnl=total_pnl,
        gross_profit=round(gross_profit, 2),
        gross_loss=round(gross_loss, 2),
        total_charges=total_charges,
        net_pnl=net_pnl,
        total_trades=total_trades,
        winning_positions=winning_positions,
        losing_positions=losing_positions,
        win_rate=win_rate,
        max_drawdown=0.0,
    )
