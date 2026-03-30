"""
Options Trading API Routes

GET  /options/expiries          — Available expiry dates for NIFTY/BANKNIFTY
POST /options/analyze           — Run AI options analysis + generate trade recommendation
POST /options/{id}/confirm      — Execute the recommended options trade
GET  /options/{id}/status       — Execution status (polling)
"""

from fastapi import APIRouter, HTTPException, BackgroundTasks, Query
from app.models.options_models import (
    OptionsRequest,
    OptionsAnalysisResponse,
    OptionsTrade,
    OptionsConfirmation,
    OptionsExpiriesResponse,
)
from app.models.analysis_models import ExecutionUpdate
from app.services.options_service import options_service
from app.engines.options_engine import options_engine
from app.agents.options_llm_agent import options_llm_agent
from app.agents.options_execution_agent import options_execution_agent
from app.core.logging import logger
from datetime import datetime, date
from typing import List, Optional
import uuid
import asyncio

router = APIRouter()

# In-memory store for options analyses (same pattern as analysis.py)
_options_analyses: dict = {}        # analysis_id → OptionsAnalysisResponse dict
_options_executions: dict = {}      # analysis_id → list of ExecutionUpdate


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
        lot_size = options_service.get_lot_size(index)

        # ── Step 5: Fetch live premiums for CE and PE ─────────────────
        try:
            premium_ce: float = await loop.run_in_executor(
                None,
                lambda: options_service.get_option_premium(
                    ce_inst["instrument_token"],
                    request.api_key,
                    request.access_token,
                ),
            )
            premium_pe: float = await loop.run_in_executor(
                None,
                lambda: options_service.get_option_premium(
                    pe_inst["instrument_token"],
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

        # ── Step 6: LLM analysis ──────────────────────────────────────
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
        )

        # ── Step 7: Build OptionsTrade response ───────────────────────
        trade: Optional[OptionsTrade] = None
        opt_type = llm_result.get("option_type", "NONE")

        if opt_type in ("CE", "PE"):
            chosen_inst = ce_inst if opt_type == "CE" else pe_inst
            lots_recommended = int(llm_result.get("lots_recommended", request.lots))
            quantity = lots_recommended * lot_size
            entry = float(llm_result["entry_premium"])
            sl = float(llm_result["stop_loss_premium"])
            target = float(llm_result["target_premium"])
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
        )
        analysis.status = "COMPLETED" if result["status"] == "COMPLETED" else "FAILED"
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
