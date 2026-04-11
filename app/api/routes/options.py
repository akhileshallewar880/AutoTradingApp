"""
Options Trading API Routes

GET  /options/expiries                      — Available expiry dates for NIFTY/BANKNIFTY
GET  /options/premium-quote                 — Live ATM CE/PE premiums for a given index+expiry (input screen)
POST /options/analyze                       — Run AI options analysis + generate trade recommendation
POST /options/{id}/confirm                  — Execute the recommended options trade
GET  /options/{id}/status                   — Execution status (polling)
GET  /options/{id}/monitor                  — Monitoring state + events (polling, ~15s)
GET  /options/{id}/pnl                      — Lightweight live P&L (polling, every 1s)
GET  /options/{id}/pnl-stream               — SSE push stream, P&L every 1s (preferred)
POST /options/{id}/monitor/stop             — Stop monitoring for an analysis
POST /options/{id}/monitor/resume           — Re-attach AI monitoring to an existing trade after restart
"""

from fastapi import APIRouter, HTTPException, BackgroundTasks, Query
from fastapi.responses import StreamingResponse
import json
from app.models.options_models import (
    OptionsRequest,
    OptionsAnalysisResponse,
    OptionsTrade,
    OptionsConfirmation,
    OptionsExpiriesResponse,
    MonitorResumeRequest,
)
from app.models.analysis_models import ExecutionUpdate
from app.services.options_service import options_service
from app.engines.options_engine import options_engine
from app.agents.options_llm_agent import options_llm_agent
from app.agents.options_execution_agent import options_execution_agent
from app.agents.options_monitoring_agent import options_monitoring_agent, MonitoringSession
from app.core.logging import logger
from app.storage.database import db
from datetime import datetime, date
from typing import List, Optional
import uuid
import asyncio

router = APIRouter()

# In-memory store for options analyses (same pattern as analysis.py)
_options_analyses: dict = {}           # analysis_id → OptionsAnalysisResponse dict
_options_executions: dict = {}         # analysis_id → list of ExecutionUpdate
_options_monitoring_events: dict = {}  # analysis_id → list of monitoring event dicts


# ── GET /options/expiries ─────────────────────────────────────────────────────

@router.get("/expiries", response_model=OptionsExpiriesResponse)
async def get_expiries(
    index: str = Query(..., description="NIFTY or BANKNIFTY"),
    api_key: str = Query(..., description="User's Zerodha API key"),
    access_token: str = Query(..., description="User's Zerodha access token"),
):
    """
    Return upcoming expiry dates for the given index.
    Expiries are fetched from Zerodha NFO instruments (cached daily).
    """
    index = index.upper()
    if index not in ("NIFTY", "BANKNIFTY"):
        raise HTTPException(status_code=400, detail="index must be NIFTY or BANKNIFTY")

    try:
        loop = asyncio.get_event_loop()
        expiries: List[date] = await loop.run_in_executor(
            None,
            lambda: options_service.get_available_expiries(index, api_key, access_token),
        )
        return OptionsExpiriesResponse(
            index=index,
            expiries=[str(e) for e in expiries],
        )
    except Exception as e:
        logger.error(f"[Options-Expiries] {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to fetch expiries: {e}")


# ── GET /options/premium-quote ───────────────────────────────────────────────

@router.get("/premium-quote")
async def get_premium_quote(
    index: str = Query(..., description="NIFTY or BANKNIFTY"),
    expiry_date: date = Query(..., description="Expiry date YYYY-MM-DD"),
    api_key: str = Query(...),
    access_token: str = Query(...),
):
    """
    Lightweight endpoint for the input screen.
    Returns current index price + live ATM CE and PE premiums.
    Used to compute realistic max lots and leverage before running full analysis.
    """
    index = index.upper()
    if index not in ("NIFTY", "BANKNIFTY"):
        raise HTTPException(status_code=400, detail="index must be NIFTY or BANKNIFTY")

    try:
        loop = asyncio.get_event_loop()

        # Step 1: live index price
        current_price = await loop.run_in_executor(
            None,
            lambda: options_service.get_index_price(index, api_key, access_token),
        )

        # Step 2: ATM strike + CE/PE instruments
        atm_data = await loop.run_in_executor(
            None,
            lambda: options_service.select_atm_strike(
                index, expiry_date, current_price, api_key, access_token
            ),
        )
        if not atm_data:
            raise HTTPException(status_code=404, detail="No ATM contracts found for given expiry")

        ce_inst = atm_data["ce"]
        pe_inst = atm_data["pe"]
        atm_strike = atm_data["atm_strike"]
        # Read actual lot_size from Zerodha instrument data (auto-updates with SEBI changes)
        lot_size = int(ce_inst.get("lot_size") or options_service.get_lot_size(index))

        # Step 3: live premiums
        premium_ce = await loop.run_in_executor(
            None,
            lambda: options_service.get_option_premium(
                ce_inst["tradingsymbol"], api_key, access_token
            ),
        )
        premium_pe = await loop.run_in_executor(
            None,
            lambda: options_service.get_option_premium(
                pe_inst["tradingsymbol"], api_key, access_token
            ),
        )

        # Use higher of CE/PE as conservative cost estimate (worst case for affordability)
        est_premium = max(premium_ce, premium_pe)

        logger.info(
            f"[Options-PremiumQuote] {index} {expiry_date} "
            f"price={current_price:.2f} strike={atm_strike} "
            f"CE=₹{premium_ce:.2f} PE=₹{premium_pe:.2f}"
        )

        return {
            "index": index,
            "current_price": round(current_price, 2),
            "atm_strike": atm_strike,
            "expiry_date": str(expiry_date),
            "premium_ce": round(premium_ce, 2),
            "premium_pe": round(premium_pe, 2),
            "est_premium": round(est_premium, 2),
            "lot_size": lot_size,
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[Options-PremiumQuote] {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to fetch premium quote: {e}")


# ── POST /options/analyze ─────────────────────────────────────────────────────

@router.post("/analyze", response_model=OptionsAnalysisResponse)
async def analyze_options(request: OptionsRequest):
    """
    Options analysis pipeline v2 — Regime-Based Breakout System:
      1. Fetch live index price + previous-day OHLC
      2. Fetch 5-min candles
      3. Engine: regime detection → breakout detection → structure SL/target
         (engine is the final authority — no indicator voting, no GPT override)
      4. If NO_TRADE: return immediately with regime explanation
      5. If BUY_CE / BUY_PE: deterministic premium levels (no GPT approval)
      6. GPT writes narrative summary only
      7. Return full response

    Only NIFTY and BANKNIFTY. Only MIS (Intraday). Max 1 trade per day per index.
    """
    index = request.index.upper()
    if index not in ("NIFTY", "BANKNIFTY"):
        raise HTTPException(status_code=400, detail="index must be NIFTY or BANKNIFTY")

    logger.info(
        f"[Options-Analyze v2] START index={index} expiry={request.expiry_date} "
        f"lots={request.lots} capital=₹{request.capital_to_use}"
    )

    analysis_id = str(uuid.uuid4())

    try:
        loop = asyncio.get_event_loop()

        # ── Step 1: Live index price + previous-day high/low ───────────
        current_price: float = await loop.run_in_executor(
            None,
            lambda: options_service.get_index_price(
                index, request.api_key, request.access_token
            ),
        )
        logger.info(f"[Options-Analyze v2] {index} price: ₹{current_price:.2f}")

        # Prev-day OHLC — used by engine as secondary breakout level confirmation.
        # Fetched in parallel with candles; failure is non-fatal (engine uses 0.0).
        prev_day_task = asyncio.create_task(
            options_service.get_prev_day_ohlc(
                index, request.api_key, request.access_token
            )
        )

        # ── Step 2: 5-min candles + futures volume (parallel) ─────────
        candles_task = asyncio.create_task(
            options_service.get_index_candles(
                index, request.api_key, request.access_token
            )
        )
        fut_vol_task = asyncio.create_task(
            options_service.get_fut_volume_ratio(
                index, request.api_key, request.access_token
            )
        )

        candles, prev_day_ohlc, fut_volume_ratio = await asyncio.gather(
            candles_task, prev_day_task, fut_vol_task
        )
        prev_day_high = prev_day_ohlc.get("high", 0.0)
        prev_day_low  = prev_day_ohlc.get("low",  0.0)
        logger.info(f"[Options-Analyze v2] Futures volume ratio: {fut_volume_ratio:.2f}×")

        if len(candles) < 10:
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Not enough candle data ({len(candles)} candles) for {index}. "
                    "Need at least 10 five-minute candles. "
                    "If market just opened, retry after 9:30 AM IST."
                ),
            )

        logger.info(
            f"[Options-Analyze v2] {len(candles)} candles, "
            f"prev-day H={prev_day_high:.2f} L={prev_day_low:.2f}"
        )

        # ── Step 3: Engine — regime + breakout (FINAL authority) ───────
        engine_result = options_engine.generate_signal(
            candles=candles,
            index=index,
            expiry_date=request.expiry_date,
            prev_day_high=prev_day_high,
            prev_day_low=prev_day_low,
            fut_volume_ratio=fut_volume_ratio,
        )
        ind = engine_result.indicators

        logger.info(
            f"[Options-Analyze v2] Engine → signal={engine_result.signal} "
            f"regime={engine_result.regime.value} ADX={engine_result.adx:.1f}"
        )

        # ── Step 4: If NO_TRADE, return immediately (no Zerodha calls) ─
        if engine_result.signal == "NO_TRADE":
            analysis = OptionsAnalysisResponse(
                analysis_id=analysis_id,
                index=index,
                current_index_price=current_price,
                expiry_date=request.expiry_date,
                trade=None,
                index_indicators=ind,
                status="NO_TRADE",
                regime=engine_result.regime.value,
                signal_reasons=engine_result.reasons,
                failed_filters=engine_result.failed_filters,
                or_high=engine_result.or_high,
                or_low=engine_result.or_low,
                adx=engine_result.adx,
            )
            _options_analyses[analysis_id] = {
                "analysis": analysis,
                "request":  request,
                "created_at": datetime.utcnow(),
            }
            logger.info(
                f"[Options-Analyze v2] NO_TRADE — "
                f"{engine_result.failed_filters[0] if engine_result.failed_filters else 'conditions not met'}"
            )
            return analysis

        # ── Step 5: ATM strike + live premiums ────────────────────────
        opt_type = "CE" if engine_result.signal == "BUY_CE" else "PE"

        atm_data = await loop.run_in_executor(
            None,
            lambda: options_service.select_atm_strike(
                index,
                request.expiry_date,
                current_price,
                request.api_key,
                request.access_token,
            ),
        )
        if atm_data is None:
            raise HTTPException(
                status_code=404,
                detail=(
                    f"No option contracts found for {index} expiry={request.expiry_date}. "
                    "Verify the expiry date is valid."
                ),
            )

        atm_strike = atm_data["atm_strike"]
        ce_inst    = atm_data["ce"]
        pe_inst    = atm_data["pe"]
        lot_size   = int(ce_inst.get("lot_size") or options_service.get_lot_size(index))
        chosen_inst = ce_inst if opt_type == "CE" else pe_inst

        # Live premiums for both sides (for display in summary)
        try:
            premium_ce = await loop.run_in_executor(
                None,
                lambda: options_service.get_option_premium(
                    ce_inst["tradingsymbol"], request.api_key, request.access_token
                ),
            )
            premium_pe = await loop.run_in_executor(
                None,
                lambda: options_service.get_option_premium(
                    pe_inst["tradingsymbol"], request.api_key, request.access_token
                ),
            )
        except Exception as e:
            logger.warning(f"[Options-Analyze v2] Premium fetch failed: {e} — using instrument last_price")
            premium_ce = float(ce_inst.get("last_price", 0))
            premium_pe = float(pe_inst.get("last_price", 0))

        entry_premium = premium_ce if opt_type == "CE" else premium_pe
        logger.info(
            f"[Options-Analyze v2] ATM {atm_strike}: CE=₹{premium_ce:.2f} PE=₹{premium_pe:.2f} "
            f"→ using {opt_type} entry=₹{entry_premium:.2f}"
        )

        # ── Step 6: Deterministic premium levels ──────────────────────
        # SL: mapped from the engine's structure-based index SL via ATM delta (≈0.5).
        #     This ties the premium SL to the actual swing structure — not a fixed %.
        #     Hard floor: risk ≤ 25% of entry (sl_premium ≥ entry × 0.75).
        # Target: entry + 2× risk — no upside cap. Remainder runs with trailing SL.
        # Partial: entry + 1× risk — 50% exit at 1R, SL moves to breakeven.
        ATM_DELTA = 0.5
        if engine_result.sl_index_price > 0 and engine_result.entry_index_price > 0:
            if opt_type == "CE":
                index_risk_pts = engine_result.entry_index_price - engine_result.sl_index_price
            else:
                index_risk_pts = engine_result.sl_index_price - engine_result.entry_index_price
            sl_from_structure = round(entry_premium - index_risk_pts * ATM_DELTA, 2)
            # Floor: premium SL must be ≥ 75% of entry (max 25% risk per unit)
            sl_floor    = round(entry_premium * 0.75, 2)
            sl_premium  = max(sl_from_structure, sl_floor, 0.05)
        else:
            # Fallback if engine didn't produce index levels
            sl_premium = round(entry_premium * 0.75, 2)

        sl_premium      = round(sl_premium, 2)
        risk_premium    = round(entry_premium - sl_premium, 2)
        # No upside cap — full trend move captured. Target = 2R.
        target_premium  = round(entry_premium + 2.0 * risk_premium, 2)
        partial_premium = round(entry_premium + 1.0 * risk_premium, 2)  # 1R → 50% exit

        # ── Step 7: Risk-based lot sizing ─────────────────────────────
        # Hard cap: max_risk = 3% of capital. Leverage does not increase risk.
        max_risk_rupees  = round(request.capital_to_use * 0.03, 2)
        risk_per_lot     = round(risk_premium * lot_size, 2)
        if risk_per_lot > 0:
            max_safe_lots = max(1, int(max_risk_rupees / risk_per_lot))
        else:
            max_safe_lots = request.lots
        lots_to_trade = min(request.lots, max_safe_lots)

        if lots_to_trade < request.lots:
            logger.warning(
                f"[Options-Analyze v2] Lots capped: requested={request.lots} → "
                f"{lots_to_trade} (max_risk=₹{max_risk_rupees:.0f} "
                f"risk_per_lot=₹{risk_per_lot:.0f})"
            )

        quantity         = lots_to_trade * lot_size
        total_investment = round(entry_premium * quantity, 2)
        max_loss         = round(risk_premium * quantity, 2)
        max_profit       = round((target_premium - entry_premium) * quantity, 2)
        rr               = round((target_premium - entry_premium) / risk_premium, 2) if risk_premium > 0 else 2.0

        # Suggested hold: proportional to time remaining before NO_TRADE_AFTER (2 PM)
        now_ist = datetime.now(IST).replace(tzinfo=None) if "IST" in dir() else datetime.utcnow()
        try:
            import pytz as _pytz
            _ist = _pytz.timezone("Asia/Kolkata")
            now_ist = datetime.now(_ist).replace(tzinfo=None)
        except Exception:
            pass
        minutes_to_close = max(30, (14 * 60) - (now_ist.hour * 60 + now_ist.minute))
        suggested_hold   = min(90, max(30, minutes_to_close // 2))

        # ── Step 8: GPT narrative summary (non-blocking, does not change signal) ──
        llm_summary = await options_llm_agent.summarize_trade(
            index=index,
            result=engine_result,
            current_price=current_price,
            expiry_date=request.expiry_date,
            entry_premium=entry_premium,
            stop_loss_premium=sl_premium,
            target_premium=target_premium,
            lots=lots_to_trade,
            lot_size=lot_size,
        )

        confidence   = float(llm_summary.get("confidence", 0.70))
        ai_reasoning = (
            llm_summary.get("ai_reasoning") or
            llm_summary.get("summary") or
            f"{engine_result.regime.value} breakout setup. "
            f"ADX={engine_result.adx:.1f} OR={engine_result.or_high:.0f}/"
            f"{engine_result.or_low:.0f}. Entry at ATM {opt_type}."
        )
        hold_reasoning = (
            llm_summary.get("risk_notes") or
            f"Exit by {suggested_hold} min or on SL/target. "
            "Take 50% off at 1R and trail remainder."
        )

        # ── Step 9: Build trade response ──────────────────────────────
        trade = OptionsTrade(
            option_symbol=chosen_inst["tradingsymbol"],
            index=index,
            option_type=opt_type,
            strike_price=atm_strike,
            expiry_date=request.expiry_date,
            lot_size=lot_size,
            lots=lots_to_trade,
            quantity=quantity,
            instrument_token=chosen_inst["instrument_token"],
            entry_premium=entry_premium,
            stop_loss_premium=sl_premium,
            target_premium=target_premium,
            total_investment=total_investment,
            max_loss=max_loss,
            max_profit=max_profit,
            risk_reward_ratio=rr,
            confidence_score=confidence,
            suggested_hold_minutes=suggested_hold,
            hold_reasoning=hold_reasoning,
            ai_reasoning=ai_reasoning,
            current_index_price=current_price,
            signal=engine_result.signal,
        )

        analysis = OptionsAnalysisResponse(
            analysis_id=analysis_id,
            index=index,
            current_index_price=current_price,
            expiry_date=request.expiry_date,
            trade=trade,
            index_indicators=ind,
            status="PENDING_CONFIRMATION",
            regime=engine_result.regime.value,
            signal_reasons=engine_result.reasons,
            failed_filters=engine_result.failed_filters,
            or_high=engine_result.or_high,
            or_low=engine_result.or_low,
            adx=engine_result.adx,
        )

        _options_analyses[analysis_id] = {
            "analysis":   analysis,
            "request":    request,
            "created_at": datetime.utcnow(),
        }

        logger.info(
            f"[Options-Analyze v2] DONE analysis_id={analysis_id} "
            f"signal={engine_result.signal} regime={engine_result.regime.value} "
            f"entry=₹{entry_premium:.2f} SL=₹{sl_premium:.2f} "
            f"target=₹{target_premium:.2f} lots={lots_to_trade} "
            f"confidence={confidence:.2f}"
        )
        return analysis

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[Options-Analyze v2] Unexpected error: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Analysis failed: {e}")


# ── POST /options/{id}/confirm ────────────────────────────────────────────────

@router.post("/{analysis_id}/confirm")
async def confirm_options_trade(
    analysis_id: str,
    confirmation: OptionsConfirmation,
    background_tasks: BackgroundTasks,
):
    """
    Confirm and execute the recommended options trade.
    Places BUY MARKET + SL-M orders on Zerodha NFO.
    """
    cached = _options_analyses.get(analysis_id)
    if not cached:
        raise HTTPException(status_code=404, detail="Analysis not found")

    analysis: OptionsAnalysisResponse = cached["analysis"]

    if not confirmation.confirmed:
        analysis.status = "CANCELLED"
        return {"status": "CANCELLED", "analysis_id": analysis_id}

    if analysis.trade is None:
        raise HTTPException(
            status_code=400,
            detail="No trade recommendation to execute (signal was NEUTRAL or NONE)",
        )

    if analysis.status != "PENDING_CONFIRMATION":
        raise HTTPException(
            status_code=400,
            detail=f"Analysis already in status: {analysis.status}",
        )

    analysis.status = "EXECUTING"
    _options_executions[analysis_id] = []

    async def _update_callback(update: ExecutionUpdate):
        _options_executions[analysis_id].append(update)

    background_tasks.add_task(
        _execute_options_background,
        analysis_id,
        analysis,
        confirmation.api_key,
        confirmation.access_token,
        _update_callback,
    )

    return {
        "status": "EXECUTING",
        "analysis_id": analysis_id,
        "message": (
            f"Executing {analysis.trade.option_type} on {analysis.trade.option_symbol}. "
            "Check status endpoint for updates."
        ),
    }


async def _execute_options_background(
    analysis_id: str,
    analysis: OptionsAnalysisResponse,
    api_key: str,
    access_token: str,
    update_callback,
):
    trade = analysis.trade
    try:
        result = await options_execution_agent.execute_options_trade(
            option_symbol=trade.option_symbol,
            instrument_token=trade.instrument_token,
            quantity=trade.quantity,
            entry_premium=trade.entry_premium,
            stop_loss_premium=trade.stop_loss_premium,
            target_premium=trade.target_premium,
            analysis_id=analysis_id,
            api_key=api_key,
            access_token=access_token,
            update_callback=update_callback,
            analysis_sl=trade.stop_loss_premium,
            analysis_target=trade.target_premium,
        )

        if result["status"] == "COMPLETED" and result.get("fill_price"):
            analysis.status = "MONITORING"

            # Register trade with anti-overtrading guard
            options_engine.register_trade(trade.index)

            # Persist trade to DB
            await db.save_options_trade({
                "analysis_id":   analysis_id,
                "index_name":    trade.index,
                "option_symbol": trade.option_symbol,
                "option_type":   trade.option_type,
                "strike":        float(trade.strike_price),
                "expiry_date":   str(trade.expiry_date),
                "lots":          trade.lots,
                "quantity":      trade.quantity,
                "entry_premium": trade.entry_premium,
                "sl_premium":    trade.stop_loss_premium,
                "target_premium":trade.target_premium,
                "fill_price":    float(result["fill_price"]),
                "sl_order_id":   str(result.get("sl_order_id", "")),
                "target_order_id": str(result.get("target_order_id", "")),
                "regime":        analysis.regime,
                "confidence":    float(trade.confidence_score),
                "signal_reasons": str(analysis.signal_reasons),
                "failed_filters": str(analysis.failed_filters),
            })

            # Build monitoring session from execution result
            session = MonitoringSession(
                analysis_id=analysis_id,
                symbol=trade.option_symbol,
                option_type=trade.option_type,
                quantity=trade.quantity,
                entry_fill_price=float(result["fill_price"]),
                sl_trigger=float(result.get("sl_trigger", trade.stop_loss_premium)),
                sl_limit=float(result.get("sl_limit", trade.stop_loss_premium * 0.98)),
                target_price=float(result.get("target_price", trade.target_premium)),
                sl_order_id=str(result.get("sl_order_id", "")),
                target_order_id=str(result.get("target_order_id", "")),
                api_key=api_key,
                access_token=access_token,
                instrument_token=trade.instrument_token,
                index=trade.index,
                entry_index_price=float(trade.current_index_price),
            )

            async def monitoring_callback(event):
                _options_monitoring_events.setdefault(analysis_id, []).append({
                    "timestamp": event.timestamp,
                    "event_type": event.event_type,
                    "message": event.message,
                    "data": event.data,
                    "alert_level": event.alert_level,
                })
                # Mirror HUMAN_ALERT to execution updates so Flutter polling picks it up
                if event.alert_level == "DANGER":
                    _options_executions.setdefault(analysis_id, []).append(
                        ExecutionUpdate(
                            analysis_id=analysis_id,
                            stock_symbol=trade.option_symbol,
                            update_type="HUMAN_ALERT",
                            message=event.message,
                        )
                    )

            options_monitoring_agent.start_monitoring(session, monitoring_callback)
        else:
            analysis.status = "FAILED"

    except Exception as e:
        logger.error(f"[Options-Execute] Background task error: {e}", exc_info=True)
        analysis.status = "FAILED"


# ── GET /options/{id}/status ──────────────────────────────────────────────────

@router.get("/{analysis_id}/status")
async def get_options_status(analysis_id: str):
    """Poll execution status for a confirmed options trade."""
    cached = _options_analyses.get(analysis_id)
    if not cached:
        raise HTTPException(status_code=404, detail="Analysis not found")

    analysis: OptionsAnalysisResponse = cached["analysis"]
    updates = _options_executions.get(analysis_id, [])

    return {
        "analysis_id": analysis_id,
        "status": analysis.status,
        "trade": analysis.trade.dict() if analysis.trade else None,
        "updates": [u.dict() for u in updates],
        "update_count": len(updates),
    }


# ── GET /options/{id}/monitor ─────────────────────────────────────────────────

@router.get("/{analysis_id}/monitor")
async def get_monitor_state(analysis_id: str):
    """
    Poll monitoring state and events for an active trade.
    Returns current premium, P&L, SL, trailing SL, and all events.
    Clients should poll every 15 seconds while status=MONITORING.
    """
    session = options_monitoring_agent.get_session(analysis_id)
    if not session:
        raise HTTPException(status_code=404, detail="No monitoring session found")

    events = _options_monitoring_events.get(analysis_id, [])

    # If monitoring loop hasn't populated current_premium yet, fetch it directly here
    # so the very first poll shows live data instead of 0.0 / "--"
    current_premium = session.current_premium
    if current_premium <= 0 and session.status == "MONITORING":
        try:
            from app.services.zerodha_service import zerodha_service as zs
            zs.set_credentials(session.api_key, session.access_token)
            nfo_key = f"NFO:{session.symbol}"
            # Try kite.ltp() first, fall back to kite.quote()
            try:
                ltp_data = zs.kite.ltp([nfo_key])
                ltp = ltp_data.get(nfo_key, {}).get("last_price", 0.0)
                if ltp and ltp > 0:
                    current_premium = float(ltp)
                    session.current_premium = current_premium
            except Exception:
                quote_data = zs.kite.quote([nfo_key])
                ltp = quote_data.get(nfo_key, {}).get("last_price", 0.0)
                if ltp and ltp > 0:
                    current_premium = float(ltp)
                    session.current_premium = current_premium
        except Exception:
            pass  # Return 0.0 — will populate on next poll

    # Compute live P&L
    pnl = None
    pnl_pct = None
    if current_premium > 0:
        pnl = round((current_premium - session.entry_fill_price) * session.quantity, 2)
        pnl_pct = round(
            (current_premium - session.entry_fill_price) / session.entry_fill_price * 100, 2
        )

    return {
        "analysis_id": analysis_id,
        "status": session.status,
        "symbol": session.symbol,
        "current_premium": current_premium,
        "entry_fill_price": session.entry_fill_price,
        "sl_trigger": session.sl_trigger,
        "target_price": session.target_price,
        "peak_premium": session.peak_premium if session.peak_premium > 0 else session.entry_fill_price,
        "pnl": pnl,
        "pnl_pct": pnl_pct,
        "poll_count": session.poll_count,
        "events": events[-50:],   # last 50 events
        "event_count": len(events),
        "has_human_alert": any(e.get("alert_level") == "DANGER" for e in events),
    }


# ── POST /options/{id}/monitor/stop ──────────────────────────────────────────

@router.post("/{analysis_id}/monitor/stop")
async def stop_monitoring(analysis_id: str):
    """
    Stop monitoring: cancel the open SL order, place a LIMIT SELL exit, then mark EXITED.
    Pass ?force=true to skip exit order (e.g. position already closed manually on Zerodha).
    """
    session = options_monitoring_agent.get_session(analysis_id)
    if not session:
        raise HTTPException(status_code=404, detail="No monitoring session found")
    await options_monitoring_agent.stop_and_exit(analysis_id)
    return {"status": session.status, "analysis_id": analysis_id}


# ── POST /options/{id}/monitor/resume ─────────────────────────────────────────

@router.post("/{analysis_id}/monitor/resume")
async def resume_monitoring(analysis_id: str, req: MonitorResumeRequest):
    """
    Re-attach AI monitoring to an existing trade after a server restart.

    The client provides position details from Zerodha's order book (fill price,
    SL order ID, target order ID, current SL trigger/limit, target price).
    A new MonitoringSession is created and the monitoring loop is restarted
    from where it logically left off.

    Returns 409 if a monitoring session for this analysis_id is already active.
    """
    existing = options_monitoring_agent.get_session(analysis_id)
    if existing and existing.status == "MONITORING":
        return {
            "status": "ALREADY_MONITORING",
            "analysis_id": analysis_id,
            "message": "Monitoring is already active for this trade.",
        }

    session = MonitoringSession(
        analysis_id=analysis_id,
        symbol=req.symbol,
        option_type=req.option_type.upper(),
        quantity=req.quantity,
        entry_fill_price=req.fill_price,
        sl_trigger=req.sl_trigger,
        sl_limit=req.sl_limit,
        target_price=req.target_price,
        sl_order_id=req.sl_order_id,
        target_order_id=req.target_order_id,
        api_key=req.api_key,
        access_token=req.access_token,
        instrument_token=req.instrument_token,
    )

    async def monitoring_callback(event):
        _options_monitoring_events.setdefault(analysis_id, []).append({
            "timestamp": event.timestamp,
            "event_type": event.event_type,
            "message": event.message,
            "data": event.data,
            "alert_level": event.alert_level,
        })

    options_monitoring_agent.start_monitoring(session, monitoring_callback)

    logger.info(
        f"[Monitor-Resume] Reattached monitoring for {req.symbol} "
        f"analysis_id={analysis_id} fill=₹{req.fill_price} sl=₹{req.sl_trigger}"
    )

    return {
        "status": "MONITORING",
        "analysis_id": analysis_id,
        "symbol": req.symbol,
        "message": f"AI monitoring restarted for {req.symbol}. "
                   f"Fill=₹{req.fill_price} SL=₹{req.sl_trigger} Target=₹{req.target_price}",
    }


# ── GET /options/{id}/pnl ────────────────────────────────────────────────────

@router.get("/{analysis_id}/pnl")
async def get_live_pnl(analysis_id: str):
    """
    Lightweight endpoint returning only live P&L data.
    Poll this every 1 second while status=MONITORING for a Kite-like experience.
    Prefer the SSE stream (/pnl-stream) if your client supports it.
    """
    s = options_monitoring_agent.get_session(analysis_id)
    if s is None:
        raise HTTPException(status_code=404, detail="No monitoring session found")

    pnl = round((s.current_premium - s.entry_fill_price) * s.quantity, 2) if s.current_premium > 0 else 0.0
    pnl_pct = round(
        (s.current_premium - s.entry_fill_price) / s.entry_fill_price * 100, 2
    ) if s.entry_fill_price > 0 and s.current_premium > 0 else 0.0

    return {
        "analysis_id": analysis_id,
        "symbol": s.symbol,
        "status": s.status,
        "premium": round(s.current_premium, 2),
        "entry": round(s.entry_fill_price, 2),
        "pnl": pnl,
        "pnl_pct": pnl_pct,
        "sl_trigger": round(s.sl_trigger, 2),
        "target_price": round(s.target_price, 2),
        "peak_premium": round(s.peak_premium, 2),
    }


# ── GET /options/{id}/pnl-stream (SSE) ───────────────────────────────────────

@router.get("/{analysis_id}/pnl-stream")
async def pnl_stream(analysis_id: str):
    """
    Server-Sent Events stream — pushes live P&L every second.
    The server reads current_premium (updated by KiteTicker or the fast price loop)
    and pushes it to the client without the client needing to poll.

    Flutter usage:
      final request = http.Request('GET', Uri.parse('$baseUrl/options/$id/pnl-stream'));
      final response = await httpClient.send(request);
      response.stream.transform(utf8.decoder).transform(const LineSplitter())
        .where((line) => line.startsWith('data: '))
        .map((line) => jsonDecode(line.substring(6)))
        .listen((data) { setState(() { pnl = data['pnl']; }); });

    Stream closes automatically when the position is exited or the session ends.
    """
    s = options_monitoring_agent.get_session(analysis_id)
    if s is None:
        raise HTTPException(status_code=404, detail="No monitoring session found")

    async def event_generator():
        while True:
            session = options_monitoring_agent.get_session(analysis_id)
            if session is None:
                yield f"data: {json.dumps({'status': 'STOPPED', 'closed': True})}\n\n"
                break

            pnl = round(
                (session.current_premium - session.entry_fill_price) * session.quantity, 2
            ) if session.current_premium > 0 else 0.0
            pnl_pct = round(
                (session.current_premium - session.entry_fill_price) / session.entry_fill_price * 100, 2
            ) if session.entry_fill_price > 0 and session.current_premium > 0 else 0.0

            payload = {
                "symbol":        session.symbol,
                "status":        session.status,
                "premium":       round(session.current_premium, 2),
                "entry":         round(session.entry_fill_price, 2),
                "pnl":           pnl,
                "pnl_pct":       pnl_pct,
                "sl_trigger":    round(session.sl_trigger, 2),
                "target_price":  round(session.target_price, 2),
                "peak_premium":  round(session.peak_premium, 2),
                "closed":        session.status != "MONITORING",
            }
            yield f"data: {json.dumps(payload)}\n\n"

            if session.status != "MONITORING":
                break

            await asyncio.sleep(1)

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",   # disable nginx response buffering
        },
    )


# ── GET /options/{id}/commentary ─────────────────────────────────────────────

@router.get("/{analysis_id}/commentary")
async def get_options_commentary(analysis_id: str):
    """
    Fetch live commentary for an active options monitoring session.
    Returns up to 100 entries, newest first.
    Commentary language is set via POST /options/{id}/set-commentary-language.
    """
    commentary = options_monitoring_agent.get_commentary(analysis_id)
    if commentary is None:
        raise HTTPException(
            status_code=404,
            detail=f"No monitoring session found for analysis_id={analysis_id}",
        )
    return {"analysis_id": analysis_id, "commentary": commentary, "count": len(commentary)}


# ── POST /options/{id}/set-commentary-language ───────────────────────────────

@router.post("/{analysis_id}/set-commentary-language")
async def set_options_commentary_language(
    analysis_id: str,
    language: str = Query(..., description="'english' or 'hinglish'"),
):
    """
    Switch commentary language for an active options monitoring session.
    Options:
      - "english"  — plain English
      - "hinglish" — Hindi + English mix in Roman script
    Change takes effect immediately for all future commentary entries.
    """
    if language not in ("english", "hinglish"):
        raise HTTPException(status_code=400, detail="language must be 'english' or 'hinglish'")
    result = options_monitoring_agent.set_commentary_language(analysis_id, language)
    if result.get("status") == "error":
        raise HTTPException(status_code=404, detail=result["detail"])
    return result
