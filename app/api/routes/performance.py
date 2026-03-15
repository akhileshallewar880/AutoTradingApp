from fastapi import APIRouter, Query, HTTPException
from app.models.response_models import MonthlyPerformanceResponse
from app.core.logging import logger
from datetime import datetime
from typing import Optional
import asyncio

router = APIRouter()


def _estimate_charges(trades: list) -> float:
    """
    Estimate Zerodha charges for a list of executed trades.
    Components: brokerage, STT, exchange charges, SEBI charges, GST, stamp duty.
    """
    total = 0.0
    for t in trades:
        qty = float(t.get("quantity") or t.get("filled_quantity") or 0)
        price = float(t.get("average_price") or t.get("price") or 0)
        txn = (t.get("transaction_type") or "BUY").upper()
        if qty <= 0 or price <= 0:
            continue

        turnover = qty * price

        # Brokerage: ₹20 or 0.03% per executed order, whichever is lower
        brokerage = min(20.0, turnover * 0.0003)

        # STT: 0.025% on sell-side turnover (intraday equity)
        stt = turnover * 0.00025 if txn == "SELL" else 0.0

        # NSE exchange transaction charge: 0.00345%
        exchange = turnover * 0.0000345

        # SEBI charges: ₹10 per crore = 0.000001%
        sebi = turnover * 0.00001

        # GST 18% on (brokerage + exchange charges)
        gst = (brokerage + exchange) * 0.18

        # Stamp duty: 0.003% on buy-side (intraday)
        stamp = turnover * 0.00003 if txn == "BUY" else 0.0

        total += brokerage + stt + exchange + sebi + gst + stamp

    return round(total, 2)


@router.get("/monthly-performance", response_model=MonthlyPerformanceResponse)
async def get_monthly_performance(
    access_token: str = Query(...),
    api_key: str = Query(...),
):
    """
    Returns today's trading performance from Zerodha.
    Fetches live P&L from kite.positions() and calculates
    estimated charges from kite.trades().

    Note: KiteConnect provides intraday (same-day) data only.
    """
    try:
        from kiteconnect import KiteConnect

        kite = KiteConnect(api_key=api_key)
        kite.set_access_token(access_token)
        loop = asyncio.get_event_loop()

        # Fetch positions and trades in parallel
        positions_raw, trades_raw = await asyncio.gather(
            loop.run_in_executor(None, kite.positions),
            loop.run_in_executor(None, kite.trades),
        )

        day_positions = positions_raw.get("day", [])
        net_positions = positions_raw.get("net", [])

        logger.info(
            f"[PERF] Zerodha positions — day: {len(day_positions)}, "
            f"net: {len(net_positions)}, trades: {len(trades_raw)}"
        )

        # ── P&L from day positions (closed + open intraday) ──────────────────
        # day positions = every symbol touched today regardless of product type.
        realized_pnl = 0.0
        unrealized_pnl = 0.0
        gross_profit = 0.0
        gross_loss = 0.0
        winning_positions = 0
        losing_positions = 0

        # Build a set of symbols already covered by day positions
        day_symbols = set()

        for pos in day_positions:
            day_symbols.add(pos.get("tradingsymbol", ""))
            pos_pnl = float(pos.get("pnl") or 0)
            r = float(pos.get("realised") or 0)
            u = float(pos.get("unrealised") or 0)
            realized_pnl += r
            unrealized_pnl += u

            if pos_pnl > 0:
                gross_profit += pos_pnl
                winning_positions += 1
            elif pos_pnl < 0:
                gross_loss += abs(pos_pnl)
                losing_positions += 1

        # ── Also capture open net positions NOT already in day ───────────────
        # (e.g. CNC delivery positions held overnight and still open)
        for pos in net_positions:
            sym = pos.get("tradingsymbol", "")
            if sym in day_symbols:
                continue  # already counted above
            qty = int(pos.get("quantity") or 0)
            if qty == 0:
                continue  # closed position, skip
            u = float(pos.get("unrealised") or pos.get("pnl") or 0)
            if u == 0:
                continue
            unrealized_pnl += u
            if u > 0:
                gross_profit += u
                winning_positions += 1
            else:
                gross_loss += abs(u)
                losing_positions += 1

        total_pnl = realized_pnl + unrealized_pnl
        total_positions = winning_positions + losing_positions
        win_rate = round((winning_positions / total_positions) * 100, 1) if total_positions > 0 else 0.0

        logger.info(
            f"[PERF] P&L — realized: ₹{realized_pnl:.2f}, "
            f"unrealized: ₹{unrealized_pnl:.2f}, total: ₹{total_pnl:.2f}"
        )

        # ── Charges from trades ──────────────────────────────────────────────
        total_charges = _estimate_charges(trades_raw)
        net_pnl = round(total_pnl - total_charges, 2)
        total_trades = len(trades_raw)

        # ── Max drawdown (simplified on positions) ───────────────────────────
        all_pnls = [float(p.get("pnl") or 0) for p in day_positions]
        pnls = all_pnls
        max_drawdown = 0.0
        if pnls:
            peak = pnls[0]
            for p in pnls:
                peak = max(peak, p)
                max_drawdown = min(max_drawdown, p - peak)

        logger.info(
            f"Performance fetched — P&L: ₹{total_pnl:.2f}, "
            f"charges: ₹{total_charges:.2f}, trades: {total_trades}"
        )

        return MonthlyPerformanceResponse(
            month=datetime.now().strftime("%d %B %Y"),
            realized_pnl=round(realized_pnl, 2),
            unrealized_pnl=round(unrealized_pnl, 2),
            total_pnl=round(total_pnl, 2),
            gross_profit=round(gross_profit, 2),
            gross_loss=round(gross_loss, 2),
            total_charges=total_charges,
            net_pnl=net_pnl,
            total_trades=total_trades,
            winning_positions=winning_positions,
            losing_positions=losing_positions,
            win_rate=win_rate,
            max_drawdown=round(max_drawdown, 2),
        )

    except Exception as e:
        logger.error(f"Performance fetch failed: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch performance: {str(e)}")
