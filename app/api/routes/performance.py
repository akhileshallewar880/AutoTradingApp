from fastapi import APIRouter, Query, HTTPException
from app.models.response_models import MonthlyPerformanceResponse
from app.core.logging import logger
from datetime import datetime
from typing import Optional, List
import asyncio

router = APIRouter()


def _safe_float(val, default=0.0) -> float:
    try:
        return float(val) if val is not None else default
    except (TypeError, ValueError):
        return default


def _compute_perf_from_positions(positions: list, label: str) -> dict:
    """Aggregate P&L metrics from a list of closed swing position dicts."""
    realized_pnl = 0.0
    gross_profit = 0.0
    gross_loss = 0.0
    winning = 0
    losing = 0

    for pos in positions:
        # Prefer stored pnl; fall back to computing from exit/fill prices
        pnl = _safe_float(pos.get("pnl"))
        if pnl == 0.0:
            qty        = _safe_float(pos.get("quantity"))
            exit_price = _safe_float(pos.get("exit_price") or pos.get("fill_price"))
            entry_price = _safe_float(pos.get("entry_price"))
            action      = str(pos.get("action") or "BUY").upper()
            if qty > 0 and exit_price > 0 and entry_price > 0:
                pnl = (exit_price - entry_price) * qty if action == "BUY" \
                      else (entry_price - exit_price) * qty

        realized_pnl += pnl
        if pnl > 0:
            gross_profit += pnl
            winning += 1
        elif pnl < 0:
            gross_loss += abs(pnl)
            losing += 1

    total_closed = winning + losing
    win_rate = round((winning / total_closed) * 100, 1) if total_closed > 0 else 0.0

    return dict(
        realized_pnl=round(realized_pnl, 2),
        gross_profit=round(gross_profit, 2),
        gross_loss=round(gross_loss, 2),
        winning_positions=winning,
        losing_positions=losing,
        total_trades=total_closed,
        win_rate=win_rate,
    )


@router.get("/monthly-performance", response_model=MonthlyPerformanceResponse)
async def get_monthly_performance(
    access_token: str = Query(...),
    api_key: str = Query(...),
    user_id: Optional[str] = Query(None),   # kept for API compat, not used
    period: str = Query("today"),            # today | monthly | yearly
    month: Optional[int] = Query(None),      # 1-12, defaults to current month
    year: Optional[int] = Query(None),       # defaults to current year
):
    """
    Returns trading performance for the requested period.

    period=today   → live Zerodha positions + trades (today only)
    period=monthly → closed swing positions for the given month/year from DB
    period=yearly  → closed swing positions for the given year from DB
    """
    now = datetime.now()
    eff_year  = year  if year  else now.year
    eff_month = month if month else now.month

    if period == "today":
        return await _today_performance(access_token, api_key, now)

    # ── Historical periods: query vantrade_swing_positions ───────────────────
    from app.storage.database import db

    if period == "monthly":
        label = datetime(eff_year, eff_month, 1).strftime("%B %Y")
        positions = await db.get_closed_swing_positions_for_month(api_key, eff_year, eff_month)
    else:  # yearly
        label = str(eff_year)
        positions = await db.get_closed_swing_positions_for_year(api_key, eff_year)

    metrics = _compute_perf_from_positions(positions, label)
    logger.info(
        f"[PERF] {label} ({period}) — P&L: ₹{metrics['realized_pnl']:.2f}, "
        f"trades: {metrics['total_trades']}, win_rate: {metrics['win_rate']}%"
    )

    return MonthlyPerformanceResponse(
        month=label,
        realized_pnl=metrics["realized_pnl"],
        unrealized_pnl=0.0,
        total_pnl=metrics["realized_pnl"],
        gross_profit=metrics["gross_profit"],
        gross_loss=metrics["gross_loss"],
        total_charges=0.0,
        net_pnl=metrics["realized_pnl"],
        total_trades=metrics["total_trades"],
        winning_positions=metrics["winning_positions"],
        losing_positions=metrics["losing_positions"],
        win_rate=metrics["win_rate"],
        max_drawdown=0.0,
    )


@router.get("/performance-history")
async def get_performance_history(
    access_token: str = Query(...),
    api_key: str = Query(...),
    months: int = Query(12, ge=1, le=36),
):
    """
    Returns per-month P&L for the last N months plus an all-time cumulative total.

    Response shape:
    {
      "months": [
        { "year": 2025, "month": 3, "month_label": "Mar 2025",
          "total_pnl": 4200.0, "total_trades": 8, "win_rate": 62.5,
          "cumulative_pnl": 4200.0 }
      ],
      "all_time_pnl": 4200.0,
      "all_time_trades": 8,
      "all_time_win_rate": 62.5
    }
    """
    from app.storage.database import db

    history = await db.get_monthly_pnl_history(api_key, months)

    cumulative = 0.0
    all_trades = 0
    all_winning = 0
    result_months: List[dict] = []

    for row in history:
        yr, mo = row["year"], row["month"]
        pnl = round(row["total_pnl"], 2)
        trades = row["total_trades"]
        winning = row["winning_trades"]
        cumulative = round(cumulative + pnl, 2)
        win_rate = round((winning / trades) * 100, 1) if trades > 0 else 0.0
        all_trades += trades
        all_winning += winning

        month_label = datetime(yr, mo, 1).strftime("%b %Y")
        result_months.append({
            "year": yr,
            "month": mo,
            "month_label": month_label,
            "total_pnl": pnl,
            "total_trades": trades,
            "win_rate": win_rate,
            "cumulative_pnl": cumulative,
        })

    all_time_win_rate = round((all_winning / all_trades) * 100, 1) if all_trades > 0 else 0.0

    logger.info(
        f"[PERF-HIST] api_key=...{api_key[-4:]} — {len(result_months)} months, "
        f"all_time_pnl=₹{cumulative:.2f}, trades={all_trades}"
    )

    return {
        "months": result_months,
        "all_time_pnl": cumulative,
        "all_time_trades": all_trades,
        "all_time_win_rate": all_time_win_rate,
    }


async def _today_performance(access_token: str, api_key: str, now: datetime) -> MonthlyPerformanceResponse:
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
        for t in trades_raw:
            qty   = _safe_float(t.get("quantity") or t.get("filled_quantity") or 0)
            price = _safe_float(t.get("price") or t.get("average_price") or 0)
            txn   = str(t.get("transaction_type") or "").upper()
            if qty <= 0 or price <= 0:
                continue
            turnover = qty * price
            stt        = turnover * 0.001   if txn == "SELL" else 0.0
            exchange   = turnover * 0.0000345
            sebi       = turnover * 0.000001
            gst        = exchange * 0.18
            stamp      = turnover * 0.00015 if txn == "BUY"  else 0.0
            total_charges += stt + exchange + sebi + gst + stamp

    total_charges = round(total_charges, 2)
    total_pnl = round(realized_pnl + unrealized_pnl, 2)
    net_pnl   = round(total_pnl - total_charges, 2)

    total_closed = winning_positions + losing_positions
    win_rate = round((winning_positions / total_closed) * 100, 1) if total_closed > 0 else 0.0

    logger.info(
        f"[PERF] {month_label} (today) — P&L: ₹{total_pnl:.2f}, trades: {total_trades}, "
        f"wins: {winning_positions}, losses: {losing_positions}, win_rate: {win_rate}%"
    )

    return MonthlyPerformanceResponse(
        month=f"Today · {month_label}",
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
