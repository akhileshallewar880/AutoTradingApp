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
import json

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

        # Only sell settled shares — T+1 shares bought today cannot be sold until settlement
        qty    = int(target.get("quantity", 0) or 0)
        t1_qty = int(target.get("t1_quantity", 0) or 0)
        if qty <= 0:
            if t1_qty > 0:
                raise HTTPException(
                    status_code=400,
                    detail=f"{t1_qty} share(s) of '{symbol}' are pending T+1 settlement and cannot be sold today. They will be available tomorrow.",
                )
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
            "t1_quantity": t1_qty,
            "exchange": exch,
            "price": limit_price,
            "message": f"Exit order placed for {qty} shares of {symbol} @ ₹{limit_price}",
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
            # Only sell settled shares — skip T+1 pending settlement
            qty    = int(h.get("quantity", 0) or 0)
            t1_qty = int(h.get("t1_quantity", 0) or 0)
            sym    = h.get("tradingsymbol", "")
            if qty <= 0:
                if t1_qty > 0:
                    errors.append({"symbol": sym, "error": f"{t1_qty} share(s) pending T+1 settlement — available tomorrow"})
                continue
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
                results.append({"symbol": sym, "quantity": qty, "order_id": str(order_id), "price": limit_price})
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


# ── GET /portfolio/gtt-suggest ────────────────────────────────────────────────

@router.get("/gtt-suggest")
async def suggest_gtt_levels(
    symbol: str = Query(...),
    avg_price: float = Query(...),
    quantity: int = Query(...),
    exchange: str = Query(default="NSE"),
    api_key: str = Query(...),
    access_token: str = Query(...),
):
    """
    AI-powered GTT stop-loss and target suggestion for a CNC holding.
    Fetches 30-day price history, computes ATR(14), then asks GPT to suggest
    optimal levels with reasoning.
    """
    try:
        import yfinance as yf

        suffix = ".NS" if exchange.upper() == "NSE" else ".BO"
        ticker_sym = f"{symbol.upper()}{suffix}"
        df = yf.download(ticker_sym, period="45d", interval="1d", progress=False)

        if df is None or df.empty or len(df) < 10:
            raise HTTPException(status_code=400, detail=f"Insufficient price data for {symbol}")

        # Flatten MultiIndex columns (newer yfinance returns (field, ticker))
        try:
            import pandas as pd
            if isinstance(df.columns, pd.MultiIndex):
                df.columns = df.columns.get_level_values(0)
        except Exception:
            pass

        closes = [float(v) for v in df["Close"].dropna().tolist()]
        highs  = [float(v) for v in df["High"].dropna().tolist()]
        lows   = [float(v) for v in df["Low"].dropna().tolist()]

        if len(closes) < 5:
            raise HTTPException(status_code=400, detail=f"Not enough data points for {symbol}")

        ltp = closes[-1]

        # ATR(14)
        trs = [
            max(highs[i] - lows[i], abs(highs[i] - closes[i-1]), abs(lows[i] - closes[i-1]))
            for i in range(1, len(closes))
        ]
        atr_vals = trs[-14:] if len(trs) >= 14 else trs
        atr = sum(atr_vals) / len(atr_vals)

        recent_low  = min(lows[-20:])
        recent_high = max(highs[-20:])

        # ATR-based baseline: SL = avg - 2×ATR, Target = avg + 3×ATR
        base_sl     = round(max(avg_price - 2.0 * atr, recent_low * 0.97), 2)
        base_target = round(avg_price + 3.0 * atr, 2)

        # GPT refinement
        from openai import AsyncOpenAI
        from app.core.config import get_settings
        settings_obj = get_settings()
        client = AsyncOpenAI(api_key=settings_obj.OPENAI_API_KEY)

        prompt = (
            f"You are a professional equity trader. Set a GTT stop-loss and target "
            f"for a CNC (delivery) long position.\n\n"
            f"Stock: {symbol} ({exchange})\n"
            f"Avg Buy Price: ₹{avg_price}\n"
            f"Current LTP: ₹{round(ltp, 2)}\n"
            f"ATR(14): ₹{round(atr, 2)}\n"
            f"20-day Low: ₹{round(recent_low, 2)}, 20-day High: ₹{round(recent_high, 2)}\n"
            f"Quantity: {quantity} shares\n"
            f"ATR-based baseline — SL: ₹{base_sl}, Target: ₹{base_target}\n\n"
            f"Rules:\n"
            f"1. stop_loss MUST be below avg_price\n"
            f"2. target MUST be above avg_price\n"
            f"3. Minimum R:R = 1.5\n"
            f"4. Stop loss must be at least 1.5% below avg_price\n"
            f"5. Stop loss must not be more than 8% below avg_price\n\n"
            f"Respond ONLY with valid JSON:\n"
            f'{{"stop_loss": <price>, "target": <price>, '
            f'"reasoning": "<1-2 sentences>", "confidence": <0.0-1.0>, '
            f'"key_level": "<brief support/resistance note>"}}'
        )

        response = await client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[{"role": "user", "content": prompt}],
            response_format={"type": "json_object"},
            temperature=0.3,
            max_tokens=300,
        )

        raw = response.choices[0].message.content or "{}"
        suggestion = json.loads(raw)

        sl        = float(suggestion.get("stop_loss", base_sl))
        target    = float(suggestion.get("target", base_target))
        reasoning = str(suggestion.get("reasoning", "ATR-based suggestion"))
        confidence = float(suggestion.get("confidence", 0.7))
        key_level  = str(suggestion.get("key_level", ""))

        # Validate: fall back to ATR-based if GPT returned bad values
        if sl >= avg_price or target <= avg_price:
            sl, target = base_sl, base_target
            reasoning = f"ATR-based: SL = avg − 2×ATR (₹{round(atr,2)}), Target = avg + 3×ATR"
            confidence = 0.65

        risk   = avg_price - sl
        reward = target - avg_price
        rr     = round(reward / risk, 2) if risk > 0 else 0.0

        logger.info(f"[GTT Suggest] {symbol} SL={round(sl,2)} Target={round(target,2)} RR={rr} conf={confidence}")

        return {
            "symbol":      symbol.upper(),
            "exchange":    exchange.upper(),
            "avg_price":   avg_price,
            "ltp":         round(ltp, 2),
            "atr":         round(atr, 2),
            "stop_loss":   round(sl, 2),
            "target":      round(target, 2),
            "risk_reward": rr,
            "max_profit":  round((target - avg_price) * quantity, 2),
            "max_loss":    round((sl - avg_price) * quantity, 2),
            "reasoning":   reasoning,
            "confidence":  confidence,
            "key_level":   key_level,
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[GTT Suggest] {symbol}: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"GTT suggestion failed: {e}")


# ── POST /portfolio/gtt-create ────────────────────────────────────────────────

class GttCreateRequest(BaseModel):
    symbol: str
    exchange: str = "NSE"
    avg_price: float
    quantity: int
    stop_loss: float
    target: float
    ltp: Optional[float] = None
    api_key: str
    access_token: str


@router.post("/gtt-create")
async def create_gtt(request: GttCreateRequest):
    """
    Place a two-leg CNC GTT for a long (BUY) holding:
      Leg 1 — SELL LIMIT at stop_loss  (lower trigger)
      Leg 2 — SELL LIMIT at target     (upper trigger)
    """
    try:
        from kiteconnect import KiteConnect
        kite = KiteConnect(api_key=request.api_key)
        kite.set_access_token(request.access_token)

        sl     = round(request.stop_loss, 2)
        target = round(request.target, 2)
        qty    = request.quantity

        if sl >= request.avg_price:
            raise HTTPException(status_code=400, detail="Stop loss must be below entry price")
        if target <= request.avg_price:
            raise HTTPException(status_code=400, detail="Target must be above entry price")

        # Resolve LTP — use provided value, else fetch, else fall back to avg_price
        ltp = request.ltp if request.ltp and request.ltp > 0 else None
        if not ltp:
            try:
                loop = asyncio.get_event_loop()
                instrument = f"{request.exchange.upper()}:{request.symbol.upper()}"
                quote_raw = await loop.run_in_executor(None, lambda: kite.quote([instrument]))
                ltp = float(quote_raw.get(instrument, {}).get("last_price", 0))
            except Exception:
                pass
        if not ltp or ltp <= 0:
            ltp = request.avg_price

        trigger_values = sorted([sl, target])
        orders = [
            {
                "transaction_type": kite.TRANSACTION_TYPE_SELL,
                "quantity": qty,
                "order_type": kite.ORDER_TYPE_LIMIT,
                "product": kite.PRODUCT_CNC,
                "price": sl,
            },
            {
                "transaction_type": kite.TRANSACTION_TYPE_SELL,
                "quantity": qty,
                "order_type": kite.ORDER_TYPE_LIMIT,
                "product": kite.PRODUCT_CNC,
                "price": target,
            },
        ]

        loop = asyncio.get_event_loop()
        raw_result = await loop.run_in_executor(
            None,
            lambda: kite.place_gtt(
                trigger_type=kite.GTT_TYPE_TWO_LEG,
                tradingsymbol=request.symbol.upper(),
                exchange=request.exchange.upper(),
                trigger_values=trigger_values,
                last_price=ltp,
                orders=orders,
            ),
        )

        gtt_id = raw_result.get("trigger_id", raw_result) if isinstance(raw_result, dict) else raw_result

        logger.info(f"[GTT Create] {request.symbol} SL={sl} Target={target} qty={qty} gtt_id={gtt_id}")

        return {
            "success":    True,
            "gtt_id":     str(gtt_id),
            "symbol":     request.symbol.upper(),
            "stop_loss":  sl,
            "target":     target,
            "quantity":   qty,
            "max_profit": round((target - request.avg_price) * qty, 2),
            "max_loss":   round((sl - request.avg_price) * qty, 2),
            "message":    f"GTT created for {request.symbol} — SL: ₹{sl}, Target: ₹{target}",
        }
    except HTTPException:
        raise
    except Exception as e:
        _check_permission_error(e)
        logger.error(f"[GTT Create] {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"GTT creation failed: {e}")
