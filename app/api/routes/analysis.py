from fastapi import APIRouter, HTTPException, BackgroundTasks
from app.models.analysis_models import (
    AnalysisRequest, AnalysisResponse, StockAnalysis,
    OrderConfirmation, ExecutionStatus, ExecutionUpdate
)
from app.services.zerodha_service import zerodha_service
from app.services.analysis_service import analysis_service
from app.services.order_service import order_service, MarketClosedException
from app.agents.llm_agent import llm_agent
from app.agents.execution_agent import execution_agent
from app.engines.risk_engine import risk_engine
from app.core.logging import logger
from typing import List
from datetime import datetime
import uuid
import asyncio

router = APIRouter()

# In-memory stores (lives for server process lifetime — no DB needed)
_analyses: dict = {}          # analysis_id → {status, stocks, hold_duration_days, created_at}
active_executions: dict = {}  # analysis_id → list of ExecutionUpdate


@router.post("/generate", response_model=AnalysisResponse)
async def generate_analysis(request: AnalysisRequest):
    """
    Step 1: Generate AI analysis with trade recommendations.

    Intraday pipeline (hold_duration_days=0):
      1. Zerodha live quotes for Nifty 50 + Next 50
      2. 5-minute candles → VWAP, BB, RSI, MACD, Stochastic, Pivot Points
      3. Strategy engine generates preliminary BUY/SELL signals
      4. LLM picks best N stocks (supports BUY long and SELL short)
      5. Position sizing + balance validation

    Swing pipeline (hold_duration_days > 0):
      Same as before — yfinance daily candles + standard indicators
    """
    try:
        # Log request details
        api_key_mask = f"{request.api_key[:5]}...{request.api_key[-5:]}" if len(request.api_key) > 10 else "SHORT_KEY"
        token_mask = f"{request.access_token[:10]}...{request.access_token[-10:]}" if len(request.access_token) > 20 else "SHORT_TOKEN"

        logger.info(
            f"[ANALYSIS-START] Generating analysis: {request.num_stocks} stocks | "
            f"sectors={request.sectors} | hold={request.hold_duration_days}d | "
            f"user_api_key={api_key_mask} | user_token={token_mask}"
        )

        # ── Fetch real balance from Zerodha ──────────────────────────────
        try:
            from kiteconnect import KiteConnect
            kite = KiteConnect(api_key=request.api_key)
            kite.set_access_token(request.access_token)
            logger.debug(f"[ANALYSIS-BALANCE] Created user-specific KiteConnect instance with token: {token_mask}")
            margins = kite.margins()
            available_balance = margins.get("equity", {}).get("net", 100000)
            logger.info(f"[ANALYSIS-BALANCE] Real balance: ₹{available_balance:,.2f}")
        except Exception as e:
            logger.warning(f"Balance fetch failed, using default: {e}")
            available_balance = 100000

        # Use user-specified capital if provided; otherwise fall back to full balance
        capital_for_sizing = (
            request.capital_to_use
            if request.capital_to_use > 0
            else available_balance
        )
        if request.capital_to_use > 0:
            logger.info(
                f"[ANALYSIS-CAPITAL] Using user-specified capital ₹{capital_for_sizing:,.2f} "
                f"(full balance: ₹{available_balance:,.2f})"
            )

        # ── Stage 1+2: Screen + enrich ────────────────────────────────────
        screen_limit = min(request.num_stocks * 3, 60)
        logger.info(f"[ANALYSIS-SCREEN] Starting screen_and_enrich with limit={screen_limit}, hold={request.hold_duration_days}d")

        stocks_data = await analysis_service.screen_and_enrich(
            limit=screen_limit,
            analysis_date=datetime.combine(request.analysis_date, datetime.min.time()),
            sectors=request.sectors,
            hold_duration_days=request.hold_duration_days,
            user_api_key=request.api_key,
            user_access_token=request.access_token,
        )

        if not stocks_data:
            logger.error(f"[ANALYSIS-SCREEN-FAIL] screen_and_enrich returned EMPTY list. No stocks found for criteria: sectors={request.sectors}, hold={request.hold_duration_days}d")
            raise HTTPException(
                status_code=404,
                detail="No stocks found matching criteria. Try different sectors or dates."
            )

        logger.info(f"[ANALYSIS-SCREEN-OK] Screen returned {len(stocks_data)} enriched candidates for LLM")

        # ── Prepare compact market data for LLM ───────────────────────────
        is_intraday = request.hold_duration_days == 0
        market_data_for_llm = []
        for stock in stocks_data:
            entry = {
                "symbol": stock["symbol"],
                "company_name": stock.get("company_name", stock["symbol"]),
                "last_price": stock["last_price"],
                "volume": stock["volume"],
                "volume_ratio": stock.get("volume_ratio", 1.0),
                "day_change_pct": stock.get("day_change_pct", 0),
                "momentum_5d_pct": stock.get("momentum_5d_pct", 0),
                "volatility_5d": stock.get("volatility_5d", 0),
                "composite_score": stock.get("composite_score", 0),
                "hold_adjusted_score": stock.get("hold_adjusted_score", 0),
                "indicators": stock.get("indicators", {}),
            }
            if is_intraday:
                # Include intraday-specific fields
                entry["intraday_signal"] = stock.get("intraday_signal", "NEUTRAL")
                entry["signal_strength"] = stock.get("signal_strength", 0)
                entry["signal_reasons"] = stock.get("signal_reasons", [])
            market_data_for_llm.append(entry)

        # ── Stage 3: LLM analysis ─────────────────────────────────────────
        llm_response = await llm_agent.analyze_opportunities(
            market_data=market_data_for_llm,
            available_balance=available_balance,
            risk_percent=request.risk_percent,
            hold_duration_days=request.hold_duration_days,
            sectors=request.sectors,
            num_stocks=request.num_stocks,
        )

        # ── Stage 4: Position sizing + validation ──────────────────────────
        preliminary_stocks = []
        total_investment = 0.0
        seen_symbols: set = set()

        for stock_rec in llm_response.get("stocks", []):
            sym = stock_rec.get("stock_symbol", "").upper()
            if sym in seen_symbols:
                logger.warning(f"Duplicate stock symbol {sym} from LLM — skipping")
                continue
            if sym:
                seen_symbols.add(sym)
            entry = float(stock_rec.get("entry_price", 0))
            sl = float(stock_rec.get("stop_loss", 0))
            target = float(stock_rec.get("target_price", 0))
            action = stock_rec.get("action", "BUY").upper()

            if entry <= 0 or sl <= 0 or target <= 0:
                logger.warning(
                    f"Skipping {stock_rec.get('stock_symbol')}: invalid prices "
                    f"entry={entry} sl={sl} target={target}"
                )
                continue

            # ── Price ordering validation (different for BUY vs SELL/short) ──
            if action == "SELL":
                # SHORT: target < entry < stop_loss
                if sl <= entry:
                    # Auto-correct: sl should be ABOVE entry for shorts
                    distance = abs(entry - target) if target < entry else entry * 0.015
                    sl = round(entry + distance * 0.6, 2)
                    logger.warning(
                        f"Auto-correcting {stock_rec.get('stock_symbol')} SHORT: "
                        f"stop_loss adjusted to {sl} (must be above entry {entry})"
                    )
                if target >= entry:
                    # Auto-correct: target should be BELOW entry for shorts
                    distance = abs(sl - entry)
                    target = round(entry - distance * 1.5, 2)
                    logger.warning(
                        f"Auto-correcting {stock_rec.get('stock_symbol')} SHORT: "
                        f"target adjusted to {target} (must be below entry {entry})"
                    )

                risk_amount = (sl - entry) * 1          # per share
                risk_reward_ratio = (entry - target) / (sl - entry) if sl > entry else 1.0

            else:
                # BUY (long): stop_loss < entry < target
                action = "BUY"
                if sl >= entry:
                    logger.warning(
                        f"Auto-correcting {stock_rec.get('stock_symbol')} BUY: "
                        f"stop_loss ({sl}) >= entry ({entry}) — swapping"
                    )
                    entry, sl = sl, entry

                if target <= entry:
                    fixed_target = round(entry + (entry - sl), 2)
                    logger.warning(
                        f"Auto-correcting {stock_rec.get('stock_symbol')} BUY: "
                        f"target ({target}) <= entry ({entry}) — setting to {fixed_target}"
                    )
                    target = fixed_target

                risk_amount = (entry - sl) * 1          # per share
                risk_reward_ratio = (target - entry) / (entry - sl) if entry > sl else 1.0

            # Apply leverage only for intraday MIS trades
            effective_leverage = request.leverage if request.hold_duration_days == 0 else 1
            quantity = risk_engine.calculate_quantity(
                entry_price=entry,
                stop_loss=sl,
                risk_per_trade=request.risk_percent,
                capital=capital_for_sizing,
                action=action,
                leverage=effective_leverage,
            )

            if quantity == 0:
                continue

            investment_needed = entry * quantity
            risk_total = abs(entry - sl) * quantity
            potential_profit = abs(target - entry) * quantity

            preliminary_stocks.append({
                "stock_rec": stock_rec,
                "action": action,
                "entry": entry,
                "sl": sl,
                "target": target,
                "quantity": quantity,
                "investment_needed": investment_needed,
                "risk_amount": risk_total,
                "potential_profit": potential_profit,
                "potential_loss": risk_total,
                "risk_reward_ratio": round(risk_reward_ratio, 2),
            })
            total_investment += investment_needed

        # Scale down if required margin exceeds balance.
        # With MIS leverage, Zerodha only requires (total_investment / leverage) as margin.
        effective_leverage = request.leverage if request.hold_duration_days == 0 else 1
        required_margin = total_investment / effective_leverage
        if required_margin > capital_for_sizing and preliminary_stocks:
            logger.warning(
                f"Required margin ₹{required_margin:,.2f} (investment ₹{total_investment:,.2f} "
                f"/ {effective_leverage}x leverage) exceeds capital ₹{capital_for_sizing:,.2f}. Scaling down…"
            )
            scaling_factor = (capital_for_sizing * 0.95) / required_margin
            total_investment = 0.0
            for stock in preliminary_stocks:
                stock["quantity"] = max(1, int(stock["quantity"] * scaling_factor))
                stock["investment_needed"] = stock["entry"] * stock["quantity"]
                stock["risk_amount"] = abs(stock["entry"] - stock["sl"]) * stock["quantity"]
                stock["potential_profit"] = abs(stock["target"] - stock["entry"]) * stock["quantity"]
                stock["potential_loss"] = stock["risk_amount"]
                total_investment += stock["investment_needed"]

        # Build final StockAnalysis objects
        stock_analyses = []
        total_investment = total_risk = max_profit = max_loss = 0.0
        for stock in preliminary_stocks:
            rec = stock["stock_rec"]
            stock_analyses.append(StockAnalysis(
                stock_symbol=rec.get("stock_symbol", ""),
                company_name=rec.get("company_name"),
                action=stock["action"],
                entry_price=stock["entry"],
                stop_loss=stock["sl"],
                target_price=stock["target"],
                quantity=stock["quantity"],
                risk_amount=round(stock["risk_amount"], 2),
                potential_profit=round(stock["potential_profit"], 2),
                potential_loss=round(stock["potential_loss"], 2),
                risk_reward_ratio=stock["risk_reward_ratio"],
                confidence_score=float(rec.get("confidence_score", 0.5)),
                ai_reasoning=rec.get("reasoning", ""),
                days_to_target=rec.get("days_to_target"),
            ))
            total_investment += stock["investment_needed"]
            total_risk += stock["risk_amount"]
            max_profit += stock["potential_profit"]
            max_loss += stock["potential_loss"]

        if not stock_analyses:
            logger.warning(
                f"No valid trade setups found: All {len(llm_response.get('stocks', []))} LLM-recommended stocks "
                f"failed price validation. Returning empty analysis for user-friendly display."
            )
            # Return empty analysis with special status - let frontend show friendly message
            analysis_id = str(uuid.uuid4())
            analysis = AnalysisResponse(
                analysis_id=analysis_id,
                request=request,
                stocks=[],  # Empty list - no valid stocks found
                portfolio_metrics={
                    "total_investment": 0.0,
                    "total_risk": 0.0,
                    "max_profit": 0.0,
                    "max_loss": 0.0,
                    "num_stocks": 0,
                    "risk_percent": request.risk_percent,
                    "available_balance": available_balance,
                    "sectors": request.sectors,
                    "hold_duration_days": request.hold_duration_days,
                    "universe": "Nifty 50 + Next 50" if is_intraday else "Full NSE Market",
                },
                available_balance=available_balance,
                status="NO_STOCKS_FOUND",  # Special status for frontend to handle
            )
            logger.info(f"Analysis generated: {analysis_id} with 0 stocks (NO_STOCKS_FOUND)")
            return analysis

        if total_investment / effective_leverage > capital_for_sizing:
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Required margin ₹{total_investment / effective_leverage:,.2f} "
                    f"(investment ₹{total_investment:,.2f} / {effective_leverage}x leverage) "
                    f"exceeds capital ₹{capital_for_sizing:,.2f}"
                ),
            )

        analysis_id = str(uuid.uuid4())
        analysis = AnalysisResponse(
            analysis_id=analysis_id,
            request=request,
            stocks=stock_analyses,
            portfolio_metrics={
                "total_investment": round(total_investment, 2),
                "required_margin": round(total_investment / effective_leverage, 2),
                "total_risk": round(total_risk, 2),
                "max_profit": round(max_profit, 2),
                "max_loss": round(max_loss, 2),
                "num_stocks": len(stock_analyses),
                "risk_percent": request.risk_percent,
                "available_balance": available_balance,
                "capital_to_use": round(capital_for_sizing, 2),
                "leverage": effective_leverage,
                "effective_capital": round(capital_for_sizing * effective_leverage, 2),
                "sectors": request.sectors,
                "hold_duration_days": request.hold_duration_days,
                "universe": "Nifty 50 + Next 50" if is_intraday else "Full NSE Market",
            },
            available_balance=available_balance,
            status="PENDING_CONFIRMATION",
        )

        # Store in-memory for confirm/status endpoints
        _analyses[analysis_id] = {
            "analysis_id": analysis_id,
            "status": "PENDING_CONFIRMATION",
            "stocks": [s.dict() for s in stock_analyses],
            "hold_duration_days": request.hold_duration_days,
            "created_at": datetime.utcnow().isoformat(),
        }
        logger.info(f"Analysis generated: {analysis_id} with {len(stock_analyses)} stocks")
        return analysis

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Analysis generation failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Analysis generation failed: {str(e)}")


@router.post("/{analysis_id}/confirm")
async def confirm_analysis(
    analysis_id: str,
    confirmation: OrderConfirmation,
    background_tasks: BackgroundTasks,
):
    """
    Step 2: User confirms the analysis and triggers execution.
    Returns HTTP 423 immediately if NSE market is closed.
    """
    try:
        analysis_data = _analyses.get(analysis_id)
        if not analysis_data:
            raise HTTPException(status_code=404, detail="Analysis not found")

        if not confirmation.confirmed:
            _analyses[analysis_id]["status"] = "CANCELLED"
            return {"status": "cancelled", "message": "Analysis cancelled by user"}

        if not order_service.is_market_open():
            market_msg = order_service.market_status_message()
            logger.warning(f"Execution blocked — market closed: {market_msg}")
            raise HTTPException(status_code=423, detail=market_msg)

        _analyses[analysis_id]["status"] = "IN_PROGRESS"

        background_tasks.add_task(
            execute_trades,
            analysis_id,
            analysis_data,
            confirmation.access_token,
            confirmation.api_key,
            confirmation.hold_duration_days,
            confirmation.stock_overrides,
        )

        return {
            "status": "executing",
            "message": "Trade execution started",
            "analysis_id": analysis_id,
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Confirmation failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


async def execute_trades(
    analysis_id: str,
    analysis_data: dict,
    access_token: str,
    api_key: str,
    hold_duration_days: int = 0,
    stock_overrides: list = None,
):
    """Background task: execute all trades for an analysis (supports BUY and SELL/short)."""
    try:
        # Set user-specific credentials before any Zerodha API call
        zerodha_service.set_credentials(api_key, access_token)

        try:
            margins = await zerodha_service.get_margins()
            available_balance = margins.get("equity", {}).get("net", 100000)
            logger.info(f"Real account balance: ₹{available_balance:,.2f}")
        except Exception as e:
            logger.error(f"Balance fetch failed: {e}")
            available_balance = 100000

        stocks = analysis_data.get("stocks", [])

        # stock_overrides = list of {stock_symbol, quantity} for SELECTED stocks only.
        # Use it both to filter which stocks to execute AND to apply quantity edits.
        if stock_overrides:
            override_map = {
                o["stock_symbol"]: o["quantity"]
                for o in stock_overrides
                if "stock_symbol" in o and "quantity" in o
            }
            # Filter to selected stocks only — deselected stocks are absent from override_map
            all_count = len(stocks)
            stocks = [s for s in stocks if s.get("stock_symbol") in override_map]
            logger.info(
                f"Stock selection: {len(stocks)}/{all_count} stocks selected for execution"
            )
            # Apply quantity overrides
            for stock in stocks:
                sym = stock.get("stock_symbol")
                original_qty = stock["quantity"]
                stock["quantity"] = override_map[sym]
                if original_qty != override_map[sym]:
                    logger.info(f"Quantity override for {sym}: {original_qty} → {override_map[sym]}")

        async def update_callback(update: ExecutionUpdate):
            if analysis_id not in active_executions:
                active_executions[analysis_id] = []
            active_executions[analysis_id].append(update)

        for stock in stocks:
            action = stock.get("action", "BUY").upper()
            if action not in ("BUY", "SELL"):
                logger.warning(f"Skipping {stock.get('stock_symbol')}: unsupported action {action}")
                continue

            await execution_agent.execute_trade_with_gtt(
                stock_symbol=stock["stock_symbol"],
                quantity=stock["quantity"],
                entry_price=stock["entry_price"],
                stop_loss=stock["stop_loss"],
                target=stock["target_price"],
                analysis_id=analysis_id,
                update_callback=update_callback,
                access_token=access_token,
                api_key=api_key,
                hold_duration_days=hold_duration_days,
                action=action,
            )

        if analysis_id in _analyses:
            _analyses[analysis_id]["status"] = "COMPLETED"

    except Exception as e:
        logger.error(f"Trade execution failed: {e}")
        if analysis_id in _analyses:
            _analyses[analysis_id]["status"] = "FAILED"


@router.get("/{analysis_id}/status", response_model=ExecutionStatus)
async def get_execution_status(analysis_id: str):
    """Get real-time execution status for an analysis."""
    try:
        analysis_data = _analyses.get(analysis_id)
        if not analysis_data:
            raise HTTPException(status_code=404, detail="Analysis not found")

        updates = active_executions.get(analysis_id, [])
        stocks = analysis_data.get("stocks", [])
        total_stocks = len(stocks)
        completed_stocks = len([u for u in updates if u.update_type == "COMPLETED"])
        failed_stocks = len([u for u in updates if u.update_type == "ERROR"])

        return ExecutionStatus(
            analysis_id=analysis_id,
            overall_status=analysis_data["status"],
            total_stocks=total_stocks,
            completed_stocks=completed_stocks,
            failed_stocks=failed_stocks,
            updates=updates,
            created_at=datetime.fromisoformat(analysis_data["created_at"]),
            updated_at=datetime.utcnow(),
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Status fetch failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/history", response_model=List[dict])
async def get_analysis_history(limit: int = 20):
    """Get recent analysis history (current session only — no DB persistence)."""
    recent = sorted(
        _analyses.values(),
        key=lambda x: x.get("created_at", ""),
        reverse=True,
    )
    return recent[:limit]
