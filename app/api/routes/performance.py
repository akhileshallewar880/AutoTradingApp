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
        brokerage = min(20.0, turnover * 0.0003)
        stt = turnover * 0.00025 if txn == "SELL" else 0.0
        exchange = turnover * 0.0000345
        sebi = turnover * 0.00001
        gst = (brokerage + exchange) * 0.18
        stamp = turnover * 0.00003 if txn == "BUY" else 0.0
        total += brokerage + stt + exchange + sebi + gst + stamp

    return round(total, 2)


def _charge_per_trade(trades: list) -> float:
    """Average charge per trade — used to estimate monthly charges from DB trade count."""
    if not trades:
        return 6.0  # conservative default per trade
    return _estimate_charges(trades) / len(trades)


@router.get("/monthly-performance", response_model=MonthlyPerformanceResponse)
async def get_monthly_performance(
    access_token: str = Query(...),
    api_key: str = Query(...),
    user_id: Optional[str] = Query(None),
):
    """
    Returns current-month trading performance.

    Primary source: vantrade_trades + vantrade_open_positions DB tables (full month).
    Fallback: Zerodha kite.positions() + kite.trades() for today only (when no DB data).
    """
    now = datetime.now()
    month_label = now.strftime("%B %Y")   # e.g. "March 2026"

    # ── Step 1: Try DB for current month data ─────────────────────────────────
    db_realized_pnl = 0.0
    db_gross_profit = 0.0
    db_gross_loss = 0.0
    db_winning = 0
    db_losing = 0
    db_total_trades = 0
    db_unrealized_pnl = 0.0
    db_pnl_list: list = []   # for drawdown calc
    has_db_data = False

    if user_id:
        try:
            from sqlmodel import Session, select
            from sqlalchemy import func as sqlfunc
            from app.core.database import engine
            from app.models.db_models import Trade, TradeStatusEnum, OpenPosition

            with Session(engine) as session:
                # Closed trades entered this month
                closed_trades = session.exec(
                    select(Trade)
                    .where(Trade.user_id == int(user_id))
                    .where(sqlfunc.month(Trade.entry_at) == now.month)
                    .where(sqlfunc.year(Trade.entry_at) == now.year)
                    .where(Trade.trade_status == TradeStatusEnum.CLOSED)
                ).all()

                for t in closed_trades:
                    if t.pnl is not None:
                        pnl = float(t.pnl)
                    elif t.exit_price and t.entry_price:
                        pnl = (float(t.exit_price) - float(t.entry_price)) * t.quantity
                    else:
                        continue

                    db_realized_pnl += pnl
                    db_total_trades += 1
                    db_pnl_list.append(pnl)
                    if pnl > 0:
                        db_gross_profit += pnl
                        db_winning += 1
                    elif pnl < 0:
                        db_gross_loss += abs(pnl)
                        db_losing += 1

                # Open positions — unrealized P&L
                open_pos = session.exec(
                    select(OpenPosition).where(OpenPosition.user_id == int(user_id))
                ).all()

                for p in open_pos:
                    u = float(p.unrealized_pnl)
                    db_unrealized_pnl += u
                    if u > 0:
                        db_gross_profit += u
                        db_winning += 1
                    elif u < 0:
                        db_gross_loss += abs(u)
                        db_losing += 1

                has_db_data = db_total_trades > 0 or len(open_pos) > 0
                logger.info(
                    f"[PERF] DB — month trades: {db_total_trades}, "
                    f"open positions: {len(open_pos)}, "
                    f"realized: ₹{db_realized_pnl:.2f}, unrealized: ₹{db_unrealized_pnl:.2f}"
                )

        except Exception as e:
            logger.warning(f"[PERF] DB query failed, falling back to Zerodha API: {e}")

    # ── Step 2: Fetch Zerodha data (needed for charges + fallback P&L) ────────
    try:
        from kiteconnect import KiteConnect

        kite = KiteConnect(api_key=api_key)
        kite.set_access_token(access_token)
        loop = asyncio.get_event_loop()

        positions_raw, trades_raw = await asyncio.gather(
            loop.run_in_executor(None, kite.positions),
            loop.run_in_executor(None, kite.trades),
        )

        day_positions = positions_raw.get("day", [])
        net_positions = positions_raw.get("net", [])

        logger.info(
            f"[PERF] Zerodha — day positions: {len(day_positions)}, "
            f"net positions: {len(net_positions)}, today trades: {len(trades_raw)}"
        )

    except Exception as e:
        logger.error(f"[PERF] Zerodha fetch failed: {e}")
        if not has_db_data:
            raise HTTPException(status_code=500, detail=f"Failed to fetch performance: {str(e)}")
        trades_raw = []
        day_positions = []
        net_positions = []

    # ── Step 3: Build response ─────────────────────────────────────────────────

    if has_db_data:
        # Full month from DB
        realized_pnl = db_realized_pnl
        unrealized_pnl = db_unrealized_pnl
        gross_profit = db_gross_profit
        gross_loss = db_gross_loss
        winning_positions = db_winning
        losing_positions = db_losing
        total_trades = db_total_trades

        # Estimate monthly charges: avg per-trade charge × month trade count
        avg_charge = _charge_per_trade(trades_raw)
        total_charges = round(avg_charge * max(total_trades, len(trades_raw)), 2)

        # Max drawdown from DB pnl list (cumulative)
        max_drawdown = 0.0
        cumulative = 0.0
        peak = 0.0
        for p in db_pnl_list:
            cumulative += p
            peak = max(peak, cumulative)
            max_drawdown = min(max_drawdown, cumulative - peak)

    else:
        # ── Fallback: Zerodha today-only data ─────────────────────────────────
        logger.info("[PERF] No DB data found — using Zerodha today-only data")
        month_label = now.strftime("%d %B %Y")  # show full date to make scope clear

        realized_pnl = 0.0
        unrealized_pnl = 0.0
        gross_profit = 0.0
        gross_loss = 0.0
        winning_positions = 0
        losing_positions = 0
        day_symbols = set()

        for pos in day_positions:
            day_symbols.add(pos.get("tradingsymbol", ""))
            pos_pnl = float(pos.get("pnl") or 0)
            realized_pnl += float(pos.get("realised") or 0)
            unrealized_pnl += float(pos.get("unrealised") or 0)
            if pos_pnl > 0:
                gross_profit += pos_pnl
                winning_positions += 1
            elif pos_pnl < 0:
                gross_loss += abs(pos_pnl)
                losing_positions += 1

        for pos in net_positions:
            sym = pos.get("tradingsymbol", "")
            if sym in day_symbols:
                continue
            if int(pos.get("quantity") or 0) == 0:
                continue
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

        total_trades = len(trades_raw)
        total_charges = _estimate_charges(trades_raw)

        all_pnls = [float(p.get("pnl") or 0) for p in day_positions]
        max_drawdown = 0.0
        if all_pnls:
            peak = all_pnls[0]
            for p in all_pnls:
                peak = max(peak, p)
                max_drawdown = min(max_drawdown, p - peak)

    total_pnl = realized_pnl + unrealized_pnl
    net_pnl = round(total_pnl - total_charges, 2)
    total_positions = winning_positions + losing_positions
    win_rate = round((winning_positions / total_positions) * 100, 1) if total_positions > 0 else 0.0

    logger.info(
        f"[PERF] Final — month: {month_label}, P&L: ₹{total_pnl:.2f}, "
        f"charges: ₹{total_charges:.2f}, trades: {total_trades}, win_rate: {win_rate}%"
    )

    return MonthlyPerformanceResponse(
        month=month_label,
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
