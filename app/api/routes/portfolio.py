"""
Portfolio Routes — Paid Kite Connect API features

GET  /portfolio/holdings          — Long-term CNC holdings with P&L
GET  /portfolio/quote             — Full market depth quote for any symbol
POST /portfolio/order-margins     — Pre-trade margin calculator
POST /portfolio/convert-position  — Convert MIS → CNC (extend intraday to delivery)
PUT  /portfolio/orders/{order_id} — Modify a pending order
DELETE /portfolio/orders/{order_id} — Cancel a pending order
GET  /portfolio/orders/{order_id}/history — Full order lifecycle
"""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from app.services.zerodha_service import zerodha_service
from app.core.logging import logger
from typing import List, Optional
import asyncio

_PERMISSION_ERROR_MSG = (
    "This feature requires the Zerodha Kite Connect paid API plan. "
    "Enable it at console.zerodha.com/app/kiteconnect"
)


def _check_permission_error(e: Exception) -> None:
    """Raise HTTP 403 if the exception looks like a Zerodha permission/plan error."""
    err_str = str(e).lower()
    if (
        "permission" in err_str
        or "insufficient" in err_str
        or "403" in err_str
        or (hasattr(e, "status") and getattr(e, "status", 0) == 403)
    ):
        raise HTTPException(status_code=403, detail=_PERMISSION_ERROR_MSG)

router = APIRouter()


# ── GET /portfolio/holdings ───────────────────────────────────────────────────

def _extract_gtt_levels(gtt: dict) -> tuple[float, float] | None:
    """
    Extract (stop_loss_price, target_price) from a Zerodha GTT dict.

    Two-leg GTT for a long (BUY) position:
      orders[0] = SELL at stop_loss  (lower price)
      orders[1] = SELL at target     (higher price)
    Two-leg GTT for a short (SELL) position:
      orders[0] = BUY  at target     (lower price)
      orders[1] = BUY  at stop_loss  (higher price)

    Returns (stop_loss_price, target_price) regardless of position direction.
    Returns None when the GTT has fewer than 2 legs or missing prices.
    """
    orders = gtt.get("orders") or []
    if len(orders) < 2:
        return None
    try:
        p0 = float(orders[0].get("price") or 0)
        p1 = float(orders[1].get("price") or 0)
        if p0 <= 0 or p1 <= 0:
            return None
        txn = str(orders[0].get("transaction_type", "")).upper()
        if txn == "SELL":
            # Long position: lower = SL, higher = target
            return (min(p0, p1), max(p0, p1))
        else:
            # Short position: lower = target (profit), higher = SL (loss cap)
            return (max(p0, p1), min(p0, p1))
    except (TypeError, ValueError):
        return None


async def _build_gtt_map_from_db(api_key: str) -> dict:
    """
    Fall back to our DB (vantrade_swing_positions) to get GTT levels.
    Includes OPEN positions (GTT placed) and AMO_PENDING (GTT not placed yet
    but stop_loss/target are known from analysis).
    """
    try:
        from app.storage.database import db
        positions = await db.get_open_swing_positions_by_api_key(api_key)
        result = {}
        for pos in positions:
            sym = pos.get("stock_symbol", "")
            sl  = pos.get("stop_loss")
            tgt = pos.get("target_price")
            if sym and sl and tgt:
                result[sym] = {
                    "stop_loss": float(sl),
                    "target_price": float(tgt),
                    "gtt_id": str(pos.get("gtt_id") or ""),
                    "action": pos.get("action", "BUY"),
                }
        return result
    except Exception as e:
        logger.warning(f"[Holdings] DB GTT fallback failed: {e}")
        return {}


@router.get("/holdings")
async def get_holdings(
    api_key: str = Query(...),
    access_token: str = Query(...),
):
    """
    Returns user's long-term CNC holdings with GTT-based max profit/loss.
    Each holding: symbol, quantity, avg_price, last_price, pnl, day_change, isin,
                  stop_loss, target, max_profit, max_loss (when an active GTT exists).
    Paid Kite Connect API.
    """
    try:
        from kiteconnect import KiteConnect
        kite = KiteConnect(api_key=api_key)
        kite.set_access_token(access_token)

        loop = asyncio.get_event_loop()

        # Fetch holdings, active GTTs, and swing expiry data in parallel
        from app.storage.database import db
        raw, raw_gtts, swing_expiry = await asyncio.gather(
            loop.run_in_executor(None, kite.holdings),
            loop.run_in_executor(None, kite.get_gtts),
            db.get_swing_expiry_by_api_key(api_key),
            return_exceptions=True,
        )
        if isinstance(swing_expiry, Exception):
            swing_expiry = {}

        if isinstance(raw, Exception):
            raise raw

        # Build symbol → GTT map from Zerodha API (active/triggered two-leg GTTs)
        gtt_map: dict[str, dict] = {}
        if isinstance(raw_gtts, Exception):
            logger.warning(f"[Holdings] Zerodha GTT fetch failed: {raw_gtts} — using DB fallback")
        elif isinstance(raw_gtts, list):
            logger.info(f"[Holdings] Zerodha returned {len(raw_gtts)} GTTs")
            for g in raw_gtts:
                status = str(g.get("status", "")).lower()
                if status not in ("active", "triggered"):
                    continue
                orders = g.get("orders") or []
                if len(orders) < 2:
                    continue
                symbol = (g.get("condition") or {}).get("tradingsymbol", "")
                if symbol:
                    gtt_map[symbol] = g

        # If Zerodha returned nothing, fall back to our DB swing positions
        if not gtt_map:
            logger.info("[Holdings] No GTTs from Zerodha — trying DB fallback")
            db_gtts = await _build_gtt_map_from_db(api_key)
            # Convert DB format into the same shape _extract_gtt_levels expects
            for sym, d in db_gtts.items():
                sl, tgt = d["stop_loss"], d["target_price"]
                is_short = d["action"] == "SELL"
                txn = "BUY" if is_short else "SELL"
                gtt_map[sym] = {
                    "_db_source": True,
                    "id": d["gtt_id"],
                    "status": "active",
                    "condition": {"tradingsymbol": sym},
                    "orders": [
                        {"transaction_type": txn, "price": sl if not is_short else tgt},
                        {"transaction_type": txn, "price": tgt if not is_short else sl},
                    ],
                }
            if gtt_map:
                logger.info(f"[Holdings] DB fallback found {len(gtt_map)} GTT position(s)")

        holdings = []
        total_invested = 0.0
        total_current = 0.0
        total_pnl = 0.0

        for h in (raw or []):
            qty    = int(h.get("quantity", 0) or 0)
            t1_qty = int(h.get("t1_quantity", 0) or 0)
            # Use total qty (settled + T+1) for value calculations so T+1-only
            # holdings don't show ₹0 for Invested/Current.
            total_qty = qty + t1_qty
            avg = float(h.get("average_price", 0) or 0)
            ltp = float(h.get("last_price", 0) or 0)
            pnl = float(h.get("pnl", 0) or 0)
            day_chg = float(h.get("day_change", 0) or 0)
            day_chg_pct = float(h.get("day_change_percentage", 0) or 0)
            invested = avg * total_qty
            current  = ltp * total_qty
            pnl_pct  = ((ltp - avg) / avg * 100) if avg > 0 else 0.0

            total_invested += invested
            total_current  += current
            total_pnl      += pnl

            symbol = h.get("tradingsymbol", "")
            swing = swing_expiry.get(symbol, {}) if isinstance(swing_expiry, dict) else {}
            entry: dict = {
                "symbol": symbol,
                "exchange": h.get("exchange", "NSE"),
                "isin": h.get("isin", ""),
                "instrument_token": int(h.get("instrument_token", 0) or 0),
                "quantity": total_qty,   # show effective qty (settled + T+1)
                "t1_quantity": t1_qty,
                "average_price": round(avg, 2),
                "last_price": round(ltp, 2),
                "close_price": float(h.get("close_price", 0) or 0),
                "pnl": round(pnl, 2),
                "pnl_pct": round(pnl_pct, 2),
                "day_change": round(day_chg, 2),
                "day_change_pct": round(day_chg_pct, 2),
                "invested_value": round(invested, 2),
                "current_value": round(current, 2),
                "product": h.get("product", "CNC"),
                # Holding period countdown (from DB swing positions)
                "hold_duration_days": swing.get("hold_duration_days"),
                "days_left": swing.get("days_left"),
                "expiry_date": swing.get("expiry_date"),
                # GTT fields — populated below if an active GTT exists
                "stop_loss": None,
                "target": None,
                "max_profit": None,
                "max_loss": None,
                "has_gtt": False,
                "gtt_id": None,
            }

            gtt = gtt_map.get(symbol)
            if gtt and avg > 0 and total_qty > 0:
                levels = _extract_gtt_levels(gtt)
                if levels:
                    sl_price, target_price = levels
                    max_profit = round((target_price - avg) * total_qty, 2)
                    max_loss = round((sl_price - avg) * total_qty, 2)
                    entry.update({
                        "stop_loss": round(sl_price, 2),
                        "target": round(target_price, 2),
                        "max_profit": max_profit,
                        "max_loss": max_loss,
                        "has_gtt": True,
                        "gtt_id": str(gtt.get("id", "")),
                    })

            holdings.append(entry)

        # Sort by absolute P&L descending
        holdings.sort(key=lambda x: abs(x["pnl"]), reverse=True)

        overall_pnl_pct = (
            (total_current - total_invested) / total_invested * 100
            if total_invested > 0 else 0.0
        )

        return {
            "holdings": holdings,
            "count": len(holdings),
            "summary": {
                "total_invested": round(total_invested, 2),
                "total_current_value": round(total_current, 2),
                "total_pnl": round(total_pnl, 2),
                "overall_pnl_pct": round(overall_pnl_pct, 2),
            },
        }
    except Exception as e:
        _check_permission_error(e)
        logger.error(f"[Holdings] {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Holdings fetch failed: {e}")


# ── POST /portfolio/exit/{symbol} ────────────────────────────────────────────

@router.post("/exit/{symbol}")
async def exit_holding(
    symbol: str,
    api_key: str = Query(...),
    access_token: str = Query(...),
):
    """
    Place a SELL MARKET order for the full CNC holding of the given symbol.
    Uses kite.place_order — free Kite Connect API.
    """
    try:
        from kiteconnect import KiteConnect
        kite = KiteConnect(api_key=api_key)
        kite.set_access_token(access_token)

        loop = asyncio.get_event_loop()
        holdings = await loop.run_in_executor(None, kite.holdings)

        target = next(
            (h for h in holdings if h.get("tradingsymbol", "").upper() == symbol.upper()),
            None,
        )
        if not target:
            raise HTTPException(status_code=404, detail=f"Holding '{symbol}' not found")

        qty = int(target.get("quantity", 0) or 0) + int(target.get("t1_quantity", 0) or 0)
        if qty <= 0:
            raise HTTPException(status_code=400, detail=f"No quantity available to exit for '{symbol}'")

        exch = target.get("exchange", "NSE")

        # Zerodha API rejects pure MARKET orders for CNC without market protection.
        # Use LIMIT at LTP instead — fills immediately for liquid stocks.
        ltp = float(target.get("last_price") or 0)
        if ltp <= 0:
            raise HTTPException(
                status_code=400,
                detail=f"Cannot determine LTP for '{symbol}'. Refresh holdings and try again.",
            )
        limit_price = round(ltp, 2)

        order_id = await loop.run_in_executor(None, lambda: kite.place_order(
            variety=kite.VARIETY_REGULAR,
            exchange=exch,
            tradingsymbol=symbol.upper(),
            transaction_type=kite.TRANSACTION_TYPE_SELL,
            quantity=qty,
            product=kite.PRODUCT_CNC,
            order_type=kite.ORDER_TYPE_LIMIT,
            price=limit_price,
        ))

        logger.info(f"[Exit] {symbol} SELL LIMIT qty={qty} price={limit_price} order_id={order_id}")
        return {
            "success": True,
            "order_id": str(order_id),
            "symbol": symbol.upper(),
            "quantity": qty,
            "exchange": exch,
            "message": f"Exit order placed for {qty} shares of {symbol}",
        }
    except HTTPException:
        raise
    except Exception as e:
        _check_permission_error(e)
        logger.error(f"[Exit] {symbol}: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Exit order failed: {e}")


# ── POST /portfolio/exit-all ──────────────────────────────────────────────────

@router.post("/exit-all")
async def exit_all_holdings(
    api_key: str = Query(...),
    access_token: str = Query(...),
):
    """
    Place SELL MARKET orders for every CNC holding sequentially.
    Returns per-symbol results including any individual failures.
    Uses kite.place_order — free Kite Connect API.
    """
    try:
        from kiteconnect import KiteConnect
        kite = KiteConnect(api_key=api_key)
        kite.set_access_token(access_token)

        loop = asyncio.get_event_loop()
        holdings = await loop.run_in_executor(None, kite.holdings)

        results = []
        errors = []

        for h in (holdings or []):
            qty = int(h.get("quantity", 0) or 0) + int(h.get("t1_quantity", 0) or 0)
            if qty <= 0:
                continue
            sym  = h.get("tradingsymbol", "")
            exch = h.get("exchange", "NSE")
            ltp  = float(h.get("last_price") or 0)
            if ltp <= 0:
                errors.append({"symbol": sym, "error": "LTP unavailable — refresh and retry"})
                continue
            limit_price = round(ltp, 2)
            try:
                order_id = await loop.run_in_executor(None, lambda: kite.place_order(
                    variety=kite.VARIETY_REGULAR,
                    exchange=exch,
                    tradingsymbol=sym,
                    transaction_type=kite.TRANSACTION_TYPE_SELL,
                    quantity=qty,
                    product=kite.PRODUCT_CNC,
                    order_type=kite.ORDER_TYPE_LIMIT,
                    price=limit_price,
                ))
                results.append({"symbol": sym, "quantity": qty, "order_id": str(order_id)})
                logger.info(f"[ExitAll] {sym} SELL LIMIT qty={qty} price={limit_price} order_id={order_id}")
            except Exception as e:
                errors.append({"symbol": sym, "error": str(e)})
                logger.error(f"[ExitAll] {sym}: {e}")

        return {
            "success": len(results) > 0,
            "orders_placed": len(results),
            "orders_failed": len(errors),
            "results": results,
            "errors": errors,
        }
    except Exception as e:
        _check_permission_error(e)
        logger.error(f"[ExitAll] {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Exit all failed: {e}")


# ── GET /portfolio/quote ──────────────────────────────────────────────────────

@router.get("/quote")
async def get_market_quote(
    symbols: str = Query(..., description="Comma-separated symbols e.g. NSE:RELIANCE,NSE:TCS"),
    api_key: str = Query(...),
    access_token: str = Query(...),
):
    """
    Full market depth quote for one or more instruments.
    Returns last_price, OHLC, volume, circuit limits, and 5-level bid/ask depth.
    """
    symbol_list = [s.strip() for s in symbols.split(",") if s.strip()]
    if not symbol_list:
        raise HTTPException(status_code=400, detail="symbols parameter is required")

    try:
        zerodha_service.set_credentials(api_key, access_token)
        result = await zerodha_service.get_market_depth(symbol_list)
        return {"quotes": result, "count": len(result)}
    except Exception as e:
        _check_permission_error(e)
        logger.error(f"[Quote] {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Quote fetch failed: {e}")


# ── POST /portfolio/order-margins ─────────────────────────────────────────────

class OrderMarginItem(BaseModel):
    exchange: str = Field(..., description="NSE, NFO, BSE etc.")
    tradingsymbol: str
    transaction_type: str = Field(..., description="BUY or SELL")
    variety: str = Field(default="regular")
    product: str = Field(..., description="MIS, CNC, NRML")
    order_type: str = Field(default="MARKET")
    quantity: int
    price: float = Field(default=0.0)

class OrderMarginsRequest(BaseModel):
    orders: List[OrderMarginItem]
    api_key: str
    access_token: str

@router.post("/order-margins")
async def calculate_order_margins(request: OrderMarginsRequest):
    """
    Calculate exact margin required for each order before placing it.
    Returns: total_margin, span, exposure, option_premium, additional_margin per order.
    Essential for options trading to know premium + margin upfront.
    """
    try:
        zerodha_service.set_credentials(request.api_key, request.access_token)
        orders_payload = [o.dict() for o in request.orders]
        margins = await zerodha_service.get_order_margins(orders_payload)

        total = sum(float(m.get("total", 0)) for m in margins)
        return {
            "margins": margins,
            "total_margin_required": round(total, 2),
            "order_count": len(margins),
        }
    except Exception as e:
        _check_permission_error(e)
        logger.error(f"[OrderMargins] {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Margin calculation failed: {e}")


# ── POST /portfolio/convert-position ──────────────────────────────────────────

class ConvertPositionRequest(BaseModel):
    tradingsymbol: str
    exchange: str = "NSE"
    transaction_type: str = Field(..., description="BUY or SELL")
    position_type: str = Field(..., description="day or overnight")
    quantity: int
    old_product: str = Field(..., description="MIS or CNC or NRML")
    new_product: str = Field(..., description="MIS or CNC or NRML")
    api_key: str
    access_token: str

@router.post("/convert-position")
async def convert_position(request: ConvertPositionRequest):
    """
    Convert a position product type.
    Most common use: MIS → CNC (extend an intraday trade to delivery).
    Must be done before 3:15 PM on the same day.
    """
    try:
        zerodha_service.set_credentials(request.api_key, request.access_token)
        success = await zerodha_service.convert_position(
            tradingsymbol=request.tradingsymbol,
            exchange=request.exchange,
            transaction_type=request.transaction_type,
            position_type=request.position_type,
            quantity=request.quantity,
            old_product=request.old_product,
            new_product=request.new_product,
        )
        return {
            "success": success,
            "message": (
                f"{request.tradingsymbol} converted from "
                f"{request.old_product} → {request.new_product} "
                f"(qty={request.quantity})"
            ),
        }
    except Exception as e:
        _check_permission_error(e)
        logger.error(f"[ConvertPosition] {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Position conversion failed: {e}")


# ── PUT /portfolio/orders/{order_id} ──────────────────────────────────────────

class ModifyOrderRequest(BaseModel):
    variety: str = "regular"
    api_key: str
    access_token: str
    quantity: Optional[int] = None
    price: Optional[float] = None
    order_type: Optional[str] = None
    trigger_price: Optional[float] = None

@router.put("/orders/{order_id}")
async def modify_order(order_id: str, request: ModifyOrderRequest):
    """Modify a pending LIMIT or SL order (price, quantity, or type)."""
    try:
        zerodha_service.set_credentials(request.api_key, request.access_token)
        result = await zerodha_service.modify_order(
            order_id=order_id,
            variety=request.variety,
            quantity=request.quantity,
            price=request.price,
            order_type=request.order_type,
            trigger_price=request.trigger_price,
        )
        return {"order_id": result, "message": f"Order {order_id} modified"}
    except Exception as e:
        _check_permission_error(e)
        logger.error(f"[ModifyOrder] {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Order modification failed: {e}")


# ── DELETE /portfolio/orders/{order_id} ────────────────────────────────────────

@router.delete("/orders/{order_id}")
async def cancel_order(
    order_id: str,
    variety: str = Query(default="regular"),
    api_key: str = Query(...),
    access_token: str = Query(...),
):
    """Cancel a pending order."""
    try:
        zerodha_service.set_credentials(api_key, access_token)
        result = await zerodha_service.cancel_order(order_id, variety)
        return {"order_id": result, "message": f"Order {order_id} cancelled"}
    except Exception as e:
        _check_permission_error(e)
        logger.error(f"[CancelOrder] {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Order cancellation failed: {e}")


# ── GET /portfolio/orders/{order_id}/history ──────────────────────────────────

@router.get("/orders/{order_id}/history")
async def get_order_history(
    order_id: str,
    api_key: str = Query(...),
    access_token: str = Query(...),
):
    """Full lifecycle history of a single order (all status transitions)."""
    try:
        zerodha_service.set_credentials(api_key, access_token)
        history = await zerodha_service.get_order_history(order_id)
        return {"order_id": order_id, "history": history, "steps": len(history)}
    except Exception as e:
        _check_permission_error(e)
        logger.error(f"[OrderHistory] {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Order history fetch failed: {e}")
