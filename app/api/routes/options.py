"""
Options Trading API Routes

GET  /options/expiries              — Available expiry dates for NIFTY/BANKNIFTY
POST /options/analyze               — Run AI options analysis + generate trade recommendation
POST /options/{id}/confirm          — Execute the recommended options trade
GET  /options/{id}/status           — Execution status (polling)
GET  /options/{id}/monitor          — Monitoring state + events (polling)
POST /options/{id}/monitor/stop     — Stop monitoring for an analysis
POST /options/{id}/monitor/resume   — Re-attach AI monitoring to an existing trade after restart
"""

from fastapi import APIRouter, HTTPException, BackgroundTasks, Query
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


# ── POST /options/analyze ─────────────────────────────────────────────────────

@router.post("/analyze", response_model=OptionsAnalysisResponse)
async def analyze_options(request: OptionsRequest):
    """
    Full options analysis pipeline:
      1. Fetch live index price
      2. Fetch 5-min candles → calculate indicators
      3. OptionsEngine votes BUY_CE / BUY_PE / NEUTRAL
      4. LLM confirms direction and sets premium levels
      5. Select ATM option contract from Zerodha instruments
      6. Return trade recommendation

    Only NIFTY and BANKNIFTY supported. Only MIS (Intraday) product.
    """
    index = request.index.upper()
    if index not in ("NIFTY", "BANKNIFTY"):
        raise HTTPException(status_code=400, detail="index must be NIFTY or BANKNIFTY")

    logger.info(
        f"[Options-Analyze] START index={index} expiry={request.expiry_date} "
        f"lots={request.lots} capital={request.capital_to_use}"
    )

    analysis_id = str(uuid.uuid4())

    try:
        loop = asyncio.get_event_loop()

        # ── Step 1: Live index price ────────────────────────────────────
        current_price: float = await loop.run_in_executor(
            None,
            lambda: options_service.get_index_price(
                index, request.api_key, request.access_token
            ),
        )
        logger.info(f"[Options-Analyze] {index} price: ₹{current_price:.2f}")

        # ── Step 2: 5-min candles + indicators ─────────────────────────
        candles = await options_service.get_index_candles(
            index, request.api_key, request.access_token
        )

        if len(candles) < 5:
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Not enough candle data ({len(candles)}) for {index}. "
                    "Could not fetch historical data from Zerodha."
                ),
            )

        indicators = options_engine.calculate_indicators(candles)
        if indicators is None:
            raise HTTPException(
                status_code=400,
                detail="Failed to calculate technical indicators. Check candle data.",
            )

        # ── Step 3: Engine signal ────────────────────────────────────
        engine_signal = options_engine.generate_signal(
            indicators, expiry_date=request.expiry_date
        )

        logger.info(
            f"[Options-Analyze] Engine signal: {engine_signal['signal']} "
            f"strength={engine_signal['strength']}/5"
        )

        # ── Step 4: ATM strike selection ─────────────────────────────
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
                    "Check that the expiry date is valid."
                ),
            )

        atm_strike = atm_data["atm_strike"]
        ce_inst = atm_data["ce"]
        pe_inst = atm_data["pe"]
        # Prefer the actual lot_size from Zerodha's instrument data (updates automatically
        # when SEBI changes contract sizes). Fall back to hardcoded only if missing.
        lot_size = int(ce_inst.get("lot_size") or options_service.get_lot_size(index))

        # ── Step 5: Fetch live premiums for CE and PE ─────────────────
        try:
            premium_ce: float = await loop.run_in_executor(
                None,
                lambda: options_service.get_option_premium(
                    ce_inst["tradingsymbol"],
                    request.api_key,
                    request.access_token,
                ),
            )
            premium_pe: float = await loop.run_in_executor(
                None,
                lambda: options_service.get_option_premium(
                    pe_inst["tradingsymbol"],
                    request.api_key,
                    request.access_token,
                ),
            )
        except Exception as e:
            logger.warning(f"[Options-Analyze] Premium fetch failed: {e} — using last_price from instruments")
            premium_ce = float(ce_inst.get("last_price", 0))
            premium_pe = float(pe_inst.get("last_price", 0))

        logger.info(
            f"[Options-Analyze] ATM {atm_strike}: CE=₹{premium_ce:.2f}, PE=₹{premium_pe:.2f}"
        )

        # ── Step 6: Pre-compute risk budget for LLM constraint ───────
        max_risk_rupees = round(request.capital_to_use * request.risk_percent / 100, 2)
        # Max SL distance per unit so that (entry-sl) × lot_size × lots ≤ max_risk
        max_sl_distance_per_unit = round(
            max_risk_rupees / (request.lots * lot_size), 2
        ) if request.lots * lot_size > 0 else 999.0

        logger.info(
            f"[Options-Analyze] Risk budget: capital=₹{request.capital_to_use} "
            f"risk={request.risk_percent}% → max_loss=₹{max_risk_rupees} "
            f"max_sl_dist_per_unit=₹{max_sl_distance_per_unit} "
            f"(lots={request.lots} lot_size={lot_size})"
        )

        # ── Step 7: LLM analysis ──────────────────────────────────────
        llm_result = await options_llm_agent.analyze_options_opportunity(
            index=index,
            current_price=current_price,
            expiry_date=request.expiry_date,
            indicators=indicators,
            engine_signal=engine_signal,
            atm_strike=atm_strike,
            entry_premium_ce=premium_ce,
            entry_premium_pe=premium_pe,
            lots=request.lots,
            lot_size=lot_size,
            capital=request.capital_to_use,
            risk_percent=request.risk_percent,
            max_risk_rupees=max_risk_rupees,
            max_sl_distance_per_unit=max_sl_distance_per_unit,
        )

        # ── Step 8: Build OptionsTrade response ───────────────────────
        trade: Optional[OptionsTrade] = None
        opt_type = llm_result.get("option_type", "NONE")

        if opt_type in ("CE", "PE"):
            chosen_inst = ce_inst if opt_type == "CE" else pe_inst
            entry = float(llm_result["entry_premium"])
            sl = float(llm_result["stop_loss_premium"])
            target = float(llm_result["target_premium"])

            # ── Risk-based position sizing ─────────────────────────────
            # Max rupee risk = capital × risk_percent / 100
            # Risk per lot   = (entry - sl) × lot_size
            # Max safe lots  = floor(max_risk_rupees / risk_per_lot)
            # This is enforced regardless of what GPT recommended.
            risk_per_lot = (entry - sl) * lot_size
            max_risk_rupees = request.capital_to_use * (request.risk_percent / 100)

            if risk_per_lot > 0:
                max_safe_lots = max(1, int(max_risk_rupees / risk_per_lot))
            else:
                max_safe_lots = request.lots

            lots_recommended = min(
                int(llm_result.get("lots_recommended", request.lots)),
                request.lots,
                max_safe_lots,
            )

            if lots_recommended < int(llm_result.get("lots_recommended", request.lots)):
                logger.warning(
                    f"[Options-Analyze] Lots capped by risk engine: "
                    f"GPT={llm_result.get('lots_recommended')} → {lots_recommended} "
                    f"(max_risk=₹{max_risk_rupees:.0f}, risk_per_lot=₹{risk_per_lot:.0f})"
                )

            quantity = lots_recommended * lot_size
            total_investment = round(entry * quantity, 2)
            max_loss = round((entry - sl) * quantity, 2)
            max_profit = round((target - entry) * quantity, 2)
            rr = round((target - entry) / (entry - sl), 2) if entry > sl else 2.0

            trade = OptionsTrade(
                option_symbol=chosen_inst["tradingsymbol"],
                index=index,
                option_type=opt_type,
                strike_price=atm_strike,
                expiry_date=request.expiry_date,
                lot_size=lot_size,
                lots=lots_recommended,
                quantity=quantity,
                instrument_token=chosen_inst["instrument_token"],
                entry_premium=entry,
                stop_loss_premium=sl,
                target_premium=target,
                total_investment=total_investment,
                max_loss=max_loss,
                max_profit=max_profit,
                risk_reward_ratio=rr,
                confidence_score=float(llm_result.get("confidence_score", 0.5)),
                suggested_hold_minutes=int(llm_result.get("suggested_hold_minutes", 30)),
                hold_reasoning=llm_result.get("hold_reasoning", ""),
                ai_reasoning=llm_result.get("ai_reasoning", ""),
                current_index_price=current_price,
                signal=engine_signal["signal"],
            )

        analysis = OptionsAnalysisResponse(
            analysis_id=analysis_id,
            index=index,
            current_index_price=current_price,
            expiry_date=request.expiry_date,
            trade=trade,
            index_indicators={
                k: v for k, v in indicators.items()
                if k not in ("candle_count",)
            },
            status="PENDING_CONFIRMATION" if trade else "NO_TRADE",
        )

        # Cache for confirmation step
        _options_analyses[analysis_id] = {
            "analysis": analysis,
            "request": request,
            "created_at": datetime.utcnow(),
        }

        logger.info(
            f"[Options-Analyze] DONE analysis_id={analysis_id} "
            f"trade={opt_type} confidence={llm_result.get('confidence_score')}"
        )
        return analysis

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[Options-Analyze] Unexpected error: {e}", exc_info=True)
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

    # Compute live P&L if we have a current premium
    pnl = None
    pnl_pct = None
    if session.current_premium > 0:
        pnl = round((session.current_premium - session.entry_fill_price) * session.quantity, 2)
        pnl_pct = round(
            (session.current_premium - session.entry_fill_price) / session.entry_fill_price * 100, 2
        )

    return {
        "analysis_id": analysis_id,
        "status": session.status,
        "symbol": session.symbol,
        "current_premium": session.current_premium,
        "entry_fill_price": session.entry_fill_price,
        "sl_trigger": session.sl_trigger,
        "target_price": session.target_price,
        "peak_premium": session.peak_premium,
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
    """Manually stop the monitoring agent (e.g. after manual exit on Zerodha)."""
    session = options_monitoring_agent.get_session(analysis_id)
    if not session:
        raise HTTPException(status_code=404, detail="No monitoring session found")
    options_monitoring_agent.stop_monitoring(analysis_id)
    return {"status": "STOPPED", "analysis_id": analysis_id}


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
