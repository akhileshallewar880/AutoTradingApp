from fastapi import APIRouter, Query, HTTPException
from app.models.response_models import MonthlyPerformanceResponse
from app.core.logging import logger
from datetime import datetime, date
from decimal import Decimal
from typing import Optional
import asyncio

router = APIRouter()


# ── Zerodha F&O Options charge rates (NSE) ────────────────────────────────────
# Source: Zerodha brokerage calculator (F&O / Options segment)
_BROKERAGE_CAP = 20.0           # ₹20 flat cap per executed order
_BROKERAGE_PCT = 0.0003         # 0.03% of turnover (lower of flat vs pct)
_STT_SELL_RATE = 0.000125       # 0.0125% on sell-side premium turnover (F&O options)
_EXCHANGE_RATE = 0.00053        # 0.053% NSE exchange transaction charge (options)
_SEBI_RATE = 0.0000001          # ₹10 per crore = 0.00001% of turnover
_GST_RATE = 0.18                # 18% on (brokerage + exchange charges)
_STAMP_BUY_RATE = 0.00003       # 0.003% on buy turnover (stamp duty)


def _calc_charges_for_trades(trades: list) -> float:
    """
    Calculate Zerodha F&O (options) charges for a list of executed trades.
    Uses correct NSE F&O options rates (not equity rates).
    Note: Zerodha KiteConnect does not expose per-trade charges; we calculate
    them using the official published rate card.
    """
    total = 0.0
    for t in trades:
        qty = float(t.get("quantity") or t.get("filled_quantity") or 0)
        price = float(t.get("average_price") or t.get("price") or 0)
        txn = (t.get("transaction_type") or "BUY").upper()
        if qty <= 0 or price <= 0:
            continue

        turnover = qty * price
        brokerage = min(_BROKERAGE_CAP, turnover * _BROKERAGE_PCT)
        stt = turnover * _STT_SELL_RATE if txn == "SELL" else 0.0
        exchange = turnover * _EXCHANGE_RATE
        sebi = turnover * _SEBI_RATE
        gst = (brokerage + exchange) * _GST_RATE
        stamp = turnover * _STAMP_BUY_RATE if txn == "BUY" else 0.0
        total += brokerage + stt + exchange + sebi + gst + stamp

    return round(total, 2)


def _avg_charge_per_trade(trades: list) -> float:
    if not trades:
        return 8.0   # conservative F&O default
    n = len(trades)
    return _calc_charges_for_trades(trades) / n if n else 8.0


# ── DB helpers ─────────────────────────────────────────────────────────────────

def _upsert_daily_record(
    user_id: int,
    trade_date: str,
    realized_pnl: float,
    gross_profit: float,
    gross_loss: float,
    total_charges: float,
    total_trades: int,
    winning_positions: int,
    losing_positions: int,
) -> None:
    """Upsert today's P&L snapshot into vantrade_daily_pnl_records."""
    try:
        from sqlmodel import Session, select
        from app.core.database import engine
        from app.models.db_models import DailyPnlRecord

        with Session(engine) as session:
            existing = session.exec(
                select(DailyPnlRecord)
                .where(DailyPnlRecord.user_id == user_id)
                .where(DailyPnlRecord.trade_date == trade_date)
            ).first()

            if existing:
                existing.realized_pnl = Decimal(str(realized_pnl))
                existing.gross_profit = Decimal(str(gross_profit))
                existing.gross_loss = Decimal(str(gross_loss))
                existing.total_charges = Decimal(str(total_charges))
                existing.total_trades = total_trades
                existing.winning_positions = winning_positions
                existing.losing_positions = losing_positions
                existing.updated_at = datetime.utcnow()
                session.add(existing)
            else:
                record = DailyPnlRecord(
                    user_id=user_id,
                    trade_date=trade_date,
                    realized_pnl=Decimal(str(realized_pnl)),
                    gross_profit=Decimal(str(gross_profit)),
                    gross_loss=Decimal(str(gross_loss)),
                    total_charges=Decimal(str(total_charges)),
                    total_trades=total_trades,
                    winning_positions=winning_positions,
                    losing_positions=losing_positions,
                )
                session.add(record)
            session.commit()
        logger.info(f"[PERF] Saved daily P&L record for user={user_id} date={trade_date}")
    except Exception as e:
        logger.warning(f"[PERF] Failed to save daily P&L record: {e}")


def _load_monthly_records(user_id: int, year: int, month: int) -> list:
    """Load all daily P&L records for the given user/month from DB."""
    try:
        from sqlmodel import Session, select
        from app.core.database import engine
        from app.models.db_models import DailyPnlRecord

        month_prefix = f"{year:04d}-{month:02d}"
        with Session(engine) as session:
            records = session.exec(
                select(DailyPnlRecord)
                .where(DailyPnlRecord.user_id == user_id)
                .where(DailyPnlRecord.trade_date.startswith(month_prefix))
            ).all()
        return records
    except Exception as e:
        logger.warning(f"[PERF] Failed to load monthly records: {e}")
        return []


@router.get("/monthly-performance", response_model=MonthlyPerformanceResponse)
async def get_monthly_performance(
    access_token: str = Query(...),
    api_key: str = Query(...),
    user_id: Optional[str] = Query(None),
):
    """
    Returns current-month trading performance.

    Flow:
    1. Fetch today's live data from Zerodha (positions + trades).
    2. Persist today's realized P&L to vantrade_daily_pnl_records (upsert).
    3. Load all daily records for the current month from DB — this gives full
       month history even after re-login (Zerodha only returns today's data).
    4. Merge DB history + live unrealized P&L → return monthly totals.
    """
    now = datetime.now()
    today_str = now.strftime("%Y-%m-%d")
    month_label = now.strftime("%B %Y")  # e.g. "April 2026"

    # ── Step 1: Fetch live data from Zerodha ──────────────────────────────────
    trades_raw: list = []
    day_positions: list = []
    net_positions: list = []
    zerodha_ok = False

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
        zerodha_ok = True

        logger.info(
            f"[PERF] Zerodha — day positions: {len(day_positions)}, "
            f"net positions: {len(net_positions)}, today trades: {len(trades_raw)}"
        )
    except Exception as e:
        logger.error(f"[PERF] Zerodha fetch failed: {e}")

    # ── Step 2: Compute today's realized metrics from Zerodha day positions ───
    today_realized = 0.0
    today_gross_profit = 0.0
    today_gross_loss = 0.0
    today_winning = 0
    today_losing = 0
    day_symbols: set = set()

    if zerodha_ok:
        for pos in day_positions:
            day_symbols.add(pos.get("tradingsymbol", ""))
            realized = float(pos.get("realised") or 0)
            today_realized += realized
            pnl = float(pos.get("pnl") or 0)
            if pnl > 0:
                today_gross_profit += pnl
                today_winning += 1
            elif pnl < 0:
                today_gross_loss += abs(pnl)
                today_losing += 1

        today_charges = _calc_charges_for_trades(trades_raw)
        today_trades = len(trades_raw)

        # Persist today's snapshot to DB (best-effort)
        if user_id:
            _upsert_daily_record(
                user_id=int(user_id),
                trade_date=today_str,
                realized_pnl=today_realized,
                gross_profit=today_gross_profit,
                gross_loss=today_gross_loss,
                total_charges=today_charges,
                total_trades=today_trades,
                winning_positions=today_winning,
                losing_positions=today_losing,
            )

    # ── Step 3: Load full month history from DB ────────────────────────────────
    month_realized = 0.0
    month_gross_profit = 0.0
    month_gross_loss = 0.0
    month_charges = 0.0
    month_trades = 0
    month_winning = 0
    month_losing = 0
    pnl_list_for_drawdown: list = []
    has_history = False

    if user_id:
        records = _load_monthly_records(int(user_id), now.year, now.month)
        for r in records:
            month_realized += float(r.realized_pnl)
            month_gross_profit += float(r.gross_profit)
            month_gross_loss += float(r.gross_loss)
            month_charges += float(r.total_charges)
            month_trades += r.total_trades
            month_winning += r.winning_positions
            month_losing += r.losing_positions
            pnl_list_for_drawdown.append(float(r.realized_pnl))
        has_history = len(records) > 0
        logger.info(
            f"[PERF] DB history — {len(records)} day records for "
            f"{now.month}/{now.year}, realized: ₹{month_realized:.2f}"
        )

    # ── Step 4: If no DB history and Zerodha failed, error out ────────────────
    if not has_history and not zerodha_ok:
        raise HTTPException(
            status_code=500,
            detail="Failed to fetch performance data. Please try again."
        )

    # ── Step 5: Compute unrealized P&L from live net positions ────────────────
    unrealized_pnl = 0.0
    if zerodha_ok:
        for pos in net_positions:
            sym = pos.get("tradingsymbol", "")
            if sym in day_symbols:
                continue   # already counted in day positions
            if int(pos.get("quantity") or 0) == 0:
                continue
            u = float(pos.get("unrealised") or pos.get("pnl") or 0)
            if u == 0:
                continue
            unrealized_pnl += u

    # ── Step 5b: Add closed swing positions from DB for current month ─────────
    # Zerodha tradebook misses swing CNC trades from previous days.
    # Count EXPIRED swing positions closed this month as additional trades.
    if user_id:
        try:
            from app.storage.database import db
            swing_closed = await db.get_closed_swing_positions_for_month(
                api_key=api_key, year=now.year, month=now.month
            )
            for sp in swing_closed:
                fill   = float(sp.get("fill_price") or sp.get("entry_price") or 0)
                avg    = float(sp.get("entry_price") or 0)
                qty    = int(sp.get("quantity") or 0)
                action = str(sp.get("action") or "BUY").upper()
                if fill <= 0 or avg <= 0 or qty <= 0:
                    continue
                # For a BUY position exited at some point: P&L = (exit - entry) * qty
                # We don't store the exit price currently, so we can count the trade
                # but can't compute P&L here — just increment trade count
                if zerodha_ok:
                    # Avoid double counting if already in tradebook
                    continue
                today_trades += 1
        except Exception as e:
            logger.warning(f"[PERF] Swing position count failed: {e}")

    # ── Step 6: Use DB monthly totals if available, else fall back to today ───
    if has_history:
        realized_pnl = month_realized
        gross_profit = month_gross_profit
        gross_loss = month_gross_loss
        total_charges = month_charges
        total_trades = month_trades
        winning_positions = month_winning
        losing_positions = month_losing
    else:
        # DB unavailable — today-only view (Zerodha data)
        month_label = now.strftime("%d %B %Y")  # show date to clarify scope
        realized_pnl = today_realized
        gross_profit = today_gross_profit
        gross_loss = today_gross_loss
        total_charges = today_charges if zerodha_ok else 0.0
        total_trades = today_trades if zerodha_ok else 0
        winning_positions = today_winning
        losing_positions = today_losing

    # ── Step 7: Max drawdown (cumulative over daily records) ──────────────────
    max_drawdown = 0.0
    if pnl_list_for_drawdown:
        cumulative = 0.0
        peak = 0.0
        for p in pnl_list_for_drawdown:
            cumulative += p
            peak = max(peak, cumulative)
            max_drawdown = min(max_drawdown, cumulative - peak)

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
