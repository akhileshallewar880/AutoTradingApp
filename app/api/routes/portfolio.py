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

        # Fetch holdings and active GTTs in parallel
        raw, raw_gtts = await asyncio.gather(
            loop.run_in_executor(None, kite.holdings),
            loop.run_in_executor(None, kite.get_gtts),
            return_exceptions=True,
        )

        if isinstance(raw, Exception):
            raise raw

        # Build symbol → GTT map (active two-leg GTTs only)
        gtt_map: dict[str, dict] = {}
        if isinstance(raw_gtts, list):
            for g in raw_gtts:
                status = str(g.get("status", "")).lower()
                if status != "active":
                    continue
                orders = g.get("orders") or []
                if len(orders) < 2:
                    continue
                symbol = (g.get("condition") or {}).get("tradingsymbol", "")
                if symbol:
                    gtt_map[symbol] = g

        holdings = []
        total_invested = 0.0
        total_current = 0.0
        total_pnl = 0.0

        for h in (raw or []):
            qty = int(h.get("quantity", 0) or 0)
            t1_qty = int(h.get("t1_quantity", 0) or 0)
            avg = float(h.get("average_price", 0) or 0)
            ltp = float(h.get("last_price", 0) or 0)
            pnl = float(h.get("pnl", 0) or 0)
            day_chg = float(h.get("day_change", 0) or 0)
            day_chg_pct = float(h.get("day_change_percentage", 0) or 0)
            invested = avg * qty
            current = ltp * qty
            pnl_pct = ((ltp - avg) / avg * 100) if avg > 0 else 0.0

            total_invested += invested
            total_current += current
            total_pnl += pnl

            symbol = h.get("tradingsymbol", "")
            entry: dict = {
                "symbol": symbol,
                "exchange": h.get("exchange", "NSE"),
                "isin": h.get("isin", ""),
                "quantity": qty,
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
                # GTT fields — populated below if an active GTT exists
                "stop_loss": None,
                "target": None,
                "max_profit": None,
                "max_loss": None,
                "has_gtt": False,
                "gtt_id": None,
            }

            gtt = gtt_map.get(symbol)
            if gtt and avg > 0 and qty > 0:
                levels = _extract_gtt_levels(gtt)
                if levels:
                    sl_price, target_price = levels
                    total_qty = qty + t1_qty
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
