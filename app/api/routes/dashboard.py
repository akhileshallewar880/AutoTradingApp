from fastapi import APIRouter, Query, HTTPException
from app.services.zerodha_service import zerodha_service
from app.core.logging import logger
from datetime import datetime
import asyncio
from typing import List, Dict, Any

router = APIRouter()


def _safe_float(val, default=0.0) -> float:
    try:
        return float(val) if val is not None else default
    except (TypeError, ValueError):
        return default


def _calc_month_pnl(trades: List[Dict]) -> Dict:
    """
    Sum realised P&L for trades in the current calendar month.
    Zerodha tradebook entries have: tradingsymbol, transaction_type,
    quantity, price, fill_timestamp / trade_date.
    We compute realised P&L as: SELL proceeds - BUY cost (per symbol, FIFO).
    Simpler approach: sum (sell_value - buy_value) per trade pair.
    """
    now = datetime.now()
    month_trades = []
    for t in trades:
        ts = t.get("fill_timestamp") or t.get("trade_date") or ""
        try:
            if isinstance(ts, str):
                dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
            else:
                dt = ts  # already datetime
            if dt.month == now.month and dt.year == now.year:
                month_trades.append(t)
        except Exception:
            pass

    # Group by symbol and compute realised P&L
    buys: Dict[str, List] = {}
    sells: Dict[str, List] = {}
    for t in month_trades:
        sym = t.get("tradingsymbol", "")
        qty = _safe_float(t.get("quantity", 0))
        price = _safe_float(t.get("price", 0) or t.get("average_price", 0))
        if t.get("transaction_type", "").upper() == "BUY":
            buys.setdefault(sym, []).append((qty, price))
        else:
            sells.setdefault(sym, []).append((qty, price))

    total_pnl = 0.0
    wins = 0
    losses = 0
    for sym, sell_list in sells.items():
        buy_list = buys.get(sym, [])
        if not buy_list:
            continue
        avg_buy = sum(q * p for q, p in buy_list) / sum(q for q, _ in buy_list)
        for qty, sell_price in sell_list:
            pnl = (sell_price - avg_buy) * qty
            total_pnl += pnl
            if pnl >= 0:
                wins += 1
            else:
                losses += 1

    total_closed = wins + losses
    win_rate = (wins / total_closed * 100) if total_closed > 0 else 0.0
    return {
        "month_pnl": round(total_pnl, 2),
        "month_trades": total_closed,
        "month_wins": wins,
        "month_losses": losses,
        "month_win_rate": round(win_rate, 1),
    }


@router.get("/summary")
async def get_dashboard_summary(
    access_token: str = Query(..., description="Zerodha access token"),
):
    """
    Returns a consolidated dashboard summary:
    - Available balance (from margins)
    - Today's P&L (from positions)
    - Current month P&L (from tradebook)
    - Today's orders (from orders API)
    - Open positions
    - Active GTTs
    """
    try:
        # Set token first, then fetch all data in parallel
        zerodha_service.kite.set_access_token(access_token)

        margins_data, positions_data, orders_data, trades_data, gtts_data = await asyncio.gather(
            zerodha_service.get_margins(),
            zerodha_service.get_positions(access_token),
            zerodha_service.get_orders(access_token),
            zerodha_service.get_tradebook(access_token),
            zerodha_service.get_gtts(access_token),
            return_exceptions=True,
        )

        # ── Balance ──────────────────────────────────────────────────────
        available_balance = 0.0
        if isinstance(margins_data, dict):
            equity = margins_data.get("equity", {})
            available_balance = _safe_float(equity.get("available", {}).get("live_balance") or equity.get("net"))

        # ── Today's P&L from positions ───────────────────────────────────
        today_pnl = 0.0
        today_pnl_unrealised = 0.0
        open_positions = []

        if isinstance(positions_data, dict):
            day_positions = positions_data.get("day", [])
            net_positions = positions_data.get("net", [])

            for pos in day_positions:
                today_pnl += _safe_float(pos.get("pnl"))

            for pos in net_positions:
                qty = int(pos.get("quantity", 0) or 0)
                if qty == 0:
                    continue
                avg_price = _safe_float(pos.get("average_price"))
                ltp = _safe_float(pos.get("last_price"))
                pnl = _safe_float(pos.get("pnl"))
                pnl_pct = ((ltp - avg_price) / avg_price * 100) if avg_price > 0 else 0.0
                today_pnl_unrealised += pnl
                open_positions.append({
                    "symbol": pos.get("tradingsymbol", ""),
                    "quantity": qty,
                    "avg_price": round(avg_price, 2),
                    "ltp": round(ltp, 2),
                    "pnl": round(pnl, 2),
                    "pnl_pct": round(pnl_pct, 2),
                    "product": pos.get("product", ""),
                })

        # ── Orders ───────────────────────────────────────────────────────
        formatted_orders = []
        if isinstance(orders_data, list):
            for o in orders_data:
                placed_at = ""
                ts = o.get("order_timestamp") or o.get("exchange_timestamp")
                if ts:
                    try:
                        placed_at = ts.isoformat() if hasattr(ts, "isoformat") else str(ts)
                    except Exception:
                        placed_at = str(ts)

                formatted_orders.append({
                    "order_id": str(o.get("order_id", "")),
                    "symbol": o.get("tradingsymbol", ""),
                    "transaction_type": o.get("transaction_type", ""),
                    "quantity": int(o.get("quantity", 0) or 0),
                    "filled_quantity": int(o.get("filled_quantity", 0) or 0),
                    "price": _safe_float(o.get("price") or o.get("average_price")),
                    "status": o.get("status", ""),
                    "status_message": o.get("status_message") or "",
                    "order_type": o.get("order_type", ""),
                    "product": o.get("product", ""),
                    "placed_at": placed_at,
                })
            # Most recent first
            formatted_orders.sort(key=lambda x: x["placed_at"], reverse=True)

        # ── Month P&L ────────────────────────────────────────────────────
        month_stats = {"month_pnl": 0.0, "month_trades": 0, "month_win_rate": 0.0}
        if isinstance(trades_data, list):
            month_stats = _calc_month_pnl(trades_data)

        # ── GTTs ─────────────────────────────────────────────────────────
        formatted_gtts = []
        if isinstance(gtts_data, list):
            for g in gtts_data:
                condition = g.get("condition", {})
                orders_list = g.get("orders", [])
                trigger_values = condition.get("trigger_values", [])
                # Only include active GTTs
                status = g.get("status", "")
                if status.lower() not in ("active", "triggered"):
                    continue
                order_info = orders_list[0] if orders_list else {}
                formatted_gtts.append({
                    "gtt_id": str(g.get("id", "")),
                    "symbol": condition.get("tradingsymbol", ""),
                    "exchange": condition.get("exchange", ""),
                    "status": status,
                    "gtt_type": g.get("type", ""),
                    "trigger_values": trigger_values,
                    "last_price": _safe_float(condition.get("last_price")),
                    "transaction_type": order_info.get("transaction_type", ""),
                    "quantity": int(order_info.get("quantity", 0) or 0),
                    "product": order_info.get("product", ""),
                    "created_at": str(g.get("created_at", "")),
                    "updated_at": str(g.get("updated_at", "")),
                })

        today_pnl_total = round(today_pnl, 2)
        today_pnl_pct = round(
            (today_pnl_total / available_balance * 100) if available_balance > 0 else 0.0, 2
        )

        logger.info(
            f"Dashboard: balance=₹{available_balance:.0f} "
            f"today_pnl=₹{today_pnl_total} "
            f"month_pnl=₹{month_stats['month_pnl']} "
            f"orders={len(formatted_orders)} positions={len(open_positions)} "
            f"gtts={len(formatted_gtts)}"
        )

        return {
            "available_balance": round(available_balance, 2),
            "today_pnl": today_pnl_total,
            "today_pnl_pct": today_pnl_pct,
            "month_pnl": month_stats["month_pnl"],
            "month_trades": month_stats["month_trades"],
            "month_win_rate": month_stats["month_win_rate"],
            "month_wins": month_stats.get("month_wins", 0),
            "month_losses": month_stats.get("month_losses", 0),
            "orders": formatted_orders,
            "positions": open_positions,
            "gtts": formatted_gtts,
            "fetched_at": datetime.now().isoformat(),
        }

    except Exception as e:
        logger.error(f"Dashboard summary error: {e}")
        raise HTTPException(status_code=500, detail=f"Dashboard fetch failed: {str(e)}")
