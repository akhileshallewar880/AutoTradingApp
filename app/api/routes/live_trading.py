from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional, List
from app.agents.autonomous_agent import autonomous_agent_manager
from app.core.logging import logger

router = APIRouter()


class StartAgentRequest(BaseModel):
    api_key: str
    access_token: str
    user_id: str
    max_positions: int = 2
    risk_percent: float = 1.0
    scan_interval_minutes: int = 5
    max_trades_per_day: int = 6
    max_daily_loss_pct: float = 2.0
    capital_to_use: float = 0.0  # 0 = use full available balance
    leverage: int = 1             # 1–5x MIS leverage


class RegisterPositionRequest(BaseModel):
    user_id: str
    api_key: str
    access_token: str
    symbol: str
    action: str           # "BUY" or "SELL"
    quantity: int
    entry_price: float
    stop_loss: float
    target: float
    gtt_id: Optional[str] = None      # GTT already placed by user (optional)
    entry_order_id: str = ""
    atr: float = 0.0                  # Optional — agent derives 1% fallback if not provided


class PlaceLimitOrderRequest(BaseModel):
    user_id: str
    api_key: str
    access_token: str
    symbol: str
    action: str = "BUY"       # BUY or SELL
    limit_price: float         # desired entry price
    stop_loss: float
    target: float
    atr: float = 0.0
    capital_to_use: float = 0.0    # 0 = use account balance
    risk_percent: float = 1.0      # % of capital to risk per trade
    leverage: int = 1


@router.post("/live-trading/start")
async def start_agent(req: StartAgentRequest):
    """
    Start the autonomous trading agent for a user in MONITORING-ONLY mode.
    The agent will NOT scan or place entry orders automatically.
    After starting, use POST /live-trading/register-position to tell the agent
    about positions you have already placed manually on Zerodha.
    The agent will then monitor those positions: trailing SL, target hits, auto-squareoff at 3:10 PM.
    """
    try:
        result = await autonomous_agent_manager.start_agent(
            user_id=req.user_id,
            api_key=req.api_key,
            access_token=req.access_token,
            max_positions=req.max_positions,
            risk_percent=req.risk_percent,
            scan_interval_minutes=req.scan_interval_minutes,
            max_trades_per_day=req.max_trades_per_day,
            max_daily_loss_pct=req.max_daily_loss_pct,
            capital_to_use=req.capital_to_use,
            leverage=req.leverage,
        )
        return result
    except Exception as e:
        logger.error(f"Failed to start agent for user {req.user_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/live-trading/stop")
async def stop_agent(user_id: str = Query(...)):
    """
    Stop the autonomous trading agent for a user.
    If market is open: squareoffs all open positions (MARKET order) and cancels GTTs.
    If market is closed: cancels GTTs only.
    Agent state is cleared from memory after stop.
    """
    try:
        result = await autonomous_agent_manager.stop_agent(user_id)
        return result
    except Exception as e:
        logger.error(f"Failed to stop agent for user {user_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/live-trading/status")
async def get_agent_status(user_id: str = Query(...)):
    """
    Get current agent status: running state, open positions, pending orders,
    trade count, daily P&L, recent decision logs.
    """
    status = autonomous_agent_manager.get_agent_status(user_id)
    if status is None:
        return {
            "is_running": False,
            "status": "STOPPED",
            "started_at": None,
            "last_scan_at": None,
            "open_positions": [],
            "pending_orders": [],
            "trade_count_today": 0,
            "daily_pnl": 0.0,
            "daily_loss_limit_hit": False,
            "settings": {},
            "recent_logs": [],
        }
    return status


@router.post("/live-trading/register-position")
async def register_position(req: RegisterPositionRequest):
    """
    Register a manually-executed trade with the monitoring agent.

    Flow:
      1. User placed a trade manually on Zerodha.
      2. User calls this endpoint with the trade details.
      3. Agent adds it to its monitoring list and connects KiteTicker.
      4. From now on the agent monitors SL, target, trailing stop, and P&L for this position.

    The agent must already be running (POST /live-trading/start) before calling this.
    """
    if req.action not in ("BUY", "SELL"):
        raise HTTPException(status_code=400, detail="action must be 'BUY' or 'SELL'")
    if req.quantity <= 0:
        raise HTTPException(status_code=400, detail="quantity must be > 0")
    if req.entry_price <= 0:
        raise HTTPException(status_code=400, detail="entry_price must be > 0")

    try:
        result = await autonomous_agent_manager.register_position(
            user_id=req.user_id,
            symbol=req.symbol.upper(),
            action=req.action,
            quantity=req.quantity,
            entry_price=req.entry_price,
            stop_loss=req.stop_loss,
            target=req.target,
            gtt_id=req.gtt_id,
            entry_order_id=req.entry_order_id,
            atr=req.atr,
        )
        if result.get("status") == "error":
            raise HTTPException(status_code=400, detail=result.get("detail", "Unknown error"))
        return result
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to register position for user {req.user_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/live-trading/place-limit-order")
async def place_limit_order(req: PlaceLimitOrderRequest):
    """
    Place a LIMIT order on Zerodha for a candidate found via /live-trading/analyze.

    Flow:
      1. Fetch available capital from Zerodha (or use capital_to_use if set).
      2. Calculate quantity: floor(capital × leverage × risk_percent / |limit_price - stop_loss|).
      3. Place a LIMIT BUY/SELL MIS order on Zerodha.
      4. If the agent is already running, inject the order into its pending_orders
         so fill-detection starts immediately.
      5. Return order_id + computed quantity to the client.
    """
    from kiteconnect import KiteConnect
    import math

    if req.action not in ("BUY", "SELL"):
        raise HTTPException(status_code=400, detail="action must be 'BUY' or 'SELL'")
    if req.limit_price <= 0:
        raise HTTPException(status_code=400, detail="limit_price must be > 0")
    risk_per_share = abs(req.limit_price - req.stop_loss)
    if risk_per_share <= 0:
        raise HTTPException(status_code=400, detail="limit_price and stop_loss must not be equal")

    try:
        kite = KiteConnect(api_key=req.api_key, timeout=15)
        kite.set_access_token(req.access_token)

        # Step 1: fetch available capital
        import asyncio
        loop = asyncio.get_running_loop()
        try:
            margins = await loop.run_in_executor(None, kite.margins)
            equity = margins.get("equity", {})
            available = float(
                equity.get("available", {}).get("live_balance")
                or equity.get("net", 0)
            )
        except Exception:
            available = req.capital_to_use  # fallback

        capital = min(available, req.capital_to_use) if req.capital_to_use > 0 else available
        effective_capital = capital * max(1, req.leverage)

        # Step 2: compute quantity
        max_risk = effective_capital * (req.risk_percent / 100)
        quantity = max(1, math.floor(max_risk / risk_per_share))
        # Cap at 10% of capital per trade
        max_by_capital = max(1, math.floor((capital * 0.10) / req.limit_price)) if req.limit_price > 0 else 1
        quantity = min(quantity, max_by_capital)

        logger.info(
            f"[place_limit_order] {req.symbol} {req.action} "
            f"capital=₹{capital:.0f} risk_per_share=₹{risk_per_share:.2f} "
            f"max_risk=₹{max_risk:.0f} qty={quantity}"
        )

        # Step 3: place LIMIT order on Zerodha
        order_id = str(await loop.run_in_executor(
            None,
            lambda: kite.place_order(
                variety="regular",
                exchange="NSE",
                tradingsymbol=req.symbol.upper(),
                transaction_type=req.action,
                quantity=quantity,
                product="MIS",
                order_type="LIMIT",
                price=req.limit_price,
            ),
        ))

        logger.info(f"[place_limit_order] Order placed: {order_id} for {req.symbol} qty={quantity}")

        # Step 4: inject into running agent (if any) for fill monitoring
        agent_status = "no_agent"
        if autonomous_agent_manager.is_running(req.user_id):
            autonomous_agent_manager.inject_pending_order(
                user_id=req.user_id,
                symbol=req.symbol.upper(),
                order_id=order_id,
                action=req.action,
                quantity=quantity,
                limit_price=req.limit_price,
                stop_loss=req.stop_loss,
                target=req.target,
                atr=req.atr,
            )
            agent_status = "watching"

        return {
            "status": "placed",
            "order_id": order_id,
            "symbol": req.symbol.upper(),
            "action": req.action,
            "quantity": quantity,
            "limit_price": req.limit_price,
            "stop_loss": req.stop_loss,
            "target": req.target,
            "capital_used": round(quantity * req.limit_price, 2),
            "agent_status": agent_status,
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[place_limit_order] Failed for {req.user_id}/{req.symbol}: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/live-trading/analyze")
async def analyze_intraday(
    user_id: str = Query(...),
    api_key: str = Query(...),
    access_token: str = Query(...),
    limit: int = Query(default=5, ge=1, le=20),
):
    """
    Run intraday market analysis — same screener as normal analysis.
    Returns top candidate stocks with entry price, stop-loss, target, and signal details.
    No agent is started. No trades are placed.

    Use this BEFORE starting an agent to decide which stocks to trade.
    After placing trades manually, use POST /live-trading/register-position.
    """
    try:
        from app.services.analysis_service import AnalysisService
        from app.engines.strategy_engine import strategy_engine

        svc = AnalysisService()
        logger.info(f"[analyze_intraday] Running intraday screen for user {user_id[:8]}...")

        candidates = await svc.screen_and_enrich_intraday(
            limit=limit,
            user_api_key=api_key,
            user_access_token=access_token,
        )

        if not candidates:
            return {"candidates": [], "message": "No qualifying candidates found this cycle. Try again in a few minutes."}

        results: List[dict] = []
        for c in candidates:
            indicators = c.get("indicators", {})
            ltp = float(c.get("last_price", 0))
            sig = strategy_engine.generate_intraday_signal(indicators)
            signal = sig.get("signal", "NEUTRAL")
            strength = sig.get("strength", 0)
            reasons = sig.get("reasons", [])
            atr = float(indicators.get("atr", ltp * 0.01) or ltp * 0.01)

            # Calculate suggested entry / SL / target (ATR-based)
            if signal == "BUY":
                stop_loss = round(ltp - 1.5 * atr, 2)
                target    = round(ltp + 3.0 * atr, 2)
                t1        = round(ltp + 1.5 * atr, 2)
                # fallback if ATR-derived levels are illogical
                if not (stop_loss < ltp < t1 < target):
                    stop_loss = round(ltp * 0.985, 2)
                    t1        = round(ltp * 1.015, 2)
                    target    = round(ltp * 1.03, 2)
            elif signal == "SELL":
                stop_loss = round(ltp + 1.5 * atr, 2)
                target    = round(ltp - 3.0 * atr, 2)
                t1        = round(ltp - 1.5 * atr, 2)
                if not (target < t1 < ltp < stop_loss):
                    stop_loss = round(ltp * 1.015, 2)
                    t1        = round(ltp * 0.985, 2)
                    target    = round(ltp * 0.97, 2)
            else:
                # NEUTRAL — still return it but mark as such
                stop_loss = round(ltp * 0.985, 2)
                t1        = round(ltp * 1.015, 2)
                target    = round(ltp * 1.03, 2)

            risk = abs(ltp - stop_loss)
            reward = abs(target - ltp)
            rr_ratio = round(reward / risk, 2) if risk > 0 else 0.0

            results.append({
                "symbol":          c.get("symbol", ""),
                "signal":          signal,
                "strength":        strength,
                "reasons":         reasons,
                "ltp":             round(ltp, 2),
                "entry_price":     round(ltp, 2),
                "stop_loss":       stop_loss,
                "t1":              t1,
                "target":          target,
                "rr_ratio":        rr_ratio,
                "atr":             round(atr, 2),
                "volume":          c.get("volume", 0),
                "volume_ratio":    c.get("volume_ratio", 0.0),
                "day_change_pct":  c.get("day_change_pct", 0.0),
                "vwap":            indicators.get("vwap"),
                "rsi":             indicators.get("rsi"),
                "macd_histogram":  indicators.get("macd_histogram"),
            })

        logger.info(f"[analyze_intraday] Returning {len(results)} candidates for user {user_id[:8]}")
        return {"candidates": results, "count": len(results)}

    except Exception as e:
        logger.error(f"[analyze_intraday] Failed for user {user_id}: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))
