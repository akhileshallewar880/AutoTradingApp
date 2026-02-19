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
from app.storage.database import db
from app.core.logging import logger
from typing import List
from datetime import datetime
import uuid
import asyncio

router = APIRouter()

# Store active executions for polling
active_executions = {}


@router.post("/generate", response_model=AnalysisResponse)
async def generate_analysis(request: AnalysisRequest):
    """
    Step 1: Generate AI analysis with trade recommendations.

    New pipeline:
      1. Screen entire NSE market (~1800 stocks) for top movers by volume × momentum
      2. Enrich top candidates with 60-day candle data + full technical indicators
      3. Re-rank by hold-duration-aware composite score
      4. Send to GPT-4o with momentum-focused prompt → picks best N stocks
      5. Calculate position sizing, validate against balance
      6. Return comprehensive analysis for user review
    """
    try:
        logger.info(
            f"Generating analysis: {request.num_stocks} stocks | "
            f"sectors={request.sectors} | hold={request.hold_duration_days}d"
        )

        # ── Fetch real balance from Zerodha ──────────────────────────────
        try:
            zerodha_service.kite.set_access_token(request.access_token)
            margins = await zerodha_service.get_margins()
            available_balance = margins.get("equity", {}).get("net", 100000)
            logger.info(f"Real balance: ₹{available_balance:,.2f}")
        except Exception as e:
            logger.warning(f"Balance fetch failed, using default: {e}")
            available_balance = 100000

        # ── Stage 1+2: Screen NSE universe + enrich ──────────────────────
        # Fetch 3× the requested stocks so LLM has good candidates to pick from
        screen_limit = min(request.num_stocks * 3, 60)
        stocks_data = await analysis_service.screen_and_enrich(
            limit=screen_limit,
            analysis_date=datetime.combine(request.analysis_date, datetime.min.time()),
            sectors=request.sectors,
            hold_duration_days=request.hold_duration_days,
        )

        if not stocks_data:
            raise HTTPException(
                status_code=404,
                detail="No stocks found matching criteria. Try different sectors or dates."
            )

        logger.info(f"Screener returned {len(stocks_data)} enriched candidates for LLM")

        # ── Prepare compact market data for LLM (drop raw DataFrame) ─────
        market_data_for_llm = []
        for stock in stocks_data:
            market_data_for_llm.append({
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
            })

        # ── Stage 3: LLM picks best stocks ───────────────────────────────
        llm_response = await llm_agent.analyze_opportunities(
            market_data=market_data_for_llm,
            available_balance=available_balance,
            risk_percent=request.risk_percent,
            hold_duration_days=request.hold_duration_days,
            sectors=request.sectors,
            num_stocks=request.num_stocks,
        )

        # ── Stage 4: Position sizing + validation ─────────────────────────
        stock_analyses = []
        total_investment = 0.0
        total_risk = 0.0
        max_profit = 0.0
        max_loss = 0.0

        # First pass: calculate all positions
        preliminary_stocks = []
        for stock_rec in llm_response.get("stocks", []):
            entry = float(stock_rec.get("entry_price", 0))
            sl = float(stock_rec.get("stop_loss", 0))
            target = float(stock_rec.get("target_price", 0))

            if entry <= 0 or sl <= 0 or target <= 0:
                logger.warning(
                    f"Skipping {stock_rec.get('stock_symbol')}: invalid prices "
                    f"entry={entry} sl={sl} target={target}"
                )
                continue

            if sl >= entry:
                # LLM confused stop-loss and entry — swap them
                logger.warning(
                    f"Auto-correcting {stock_rec.get('stock_symbol')}: "
                    f"stop_loss ({sl}) >= entry ({entry}) — swapping to fix ordering"
                )
                entry, sl = sl, entry

            if target <= entry:
                # LLM gave a bad target — set minimum 1:1 R:R
                fixed_target = round(entry + (entry - sl), 2)
                logger.warning(
                    f"Auto-correcting {stock_rec.get('stock_symbol')}: "
                    f"target ({target}) <= entry ({entry}) — setting to {fixed_target} (1:1 R:R)"
                )
                target = fixed_target

            quantity = risk_engine.calculate_quantity(
                entry_price=entry,
                stop_loss=sl,
                risk_per_trade=request.risk_percent,
                capital=available_balance,
            )

            if quantity == 0:
                continue

            investment_needed = entry * quantity
            risk_amount = abs(entry - sl) * quantity
            potential_profit = abs(target - entry) * quantity
            risk_reward_ratio = (target - entry) / (entry - sl)

            preliminary_stocks.append({
                "stock_rec": stock_rec,
                "entry": entry,
                "sl": sl,
                "target": target,
                "quantity": quantity,
                "investment_needed": investment_needed,
                "risk_amount": risk_amount,
                "potential_profit": potential_profit,
                "potential_loss": risk_amount,
                "risk_reward_ratio": risk_reward_ratio,
            })
            total_investment += investment_needed

        # Scale down if total investment exceeds balance
        if total_investment > available_balance and preliminary_stocks:
            logger.warning(
                f"Total investment ₹{total_investment:,.2f} exceeds balance "
                f"₹{available_balance:,.2f}. Scaling down…"
            )
            scaling_factor = (available_balance * 0.95) / total_investment
            total_investment = 0.0
            for stock in preliminary_stocks:
                stock["quantity"] = max(1, int(stock["quantity"] * scaling_factor))
                stock["investment_needed"] = stock["entry"] * stock["quantity"]
                stock["risk_amount"] = abs(stock["entry"] - stock["sl"]) * stock["quantity"]
                stock["potential_profit"] = abs(stock["target"] - stock["entry"]) * stock["quantity"]
                stock["potential_loss"] = stock["risk_amount"]
                total_investment += stock["investment_needed"]
            logger.info(f"Scaled total investment to ₹{total_investment:,.2f}")

        # Second pass: build final StockAnalysis objects
        total_investment = total_risk = max_profit = max_loss = 0.0
        for stock in preliminary_stocks:
            rec = stock["stock_rec"]
            stock_analyses.append(StockAnalysis(
                stock_symbol=rec.get("stock_symbol", ""),
                company_name=rec.get("company_name"),
                action=rec.get("action", "BUY"),
                entry_price=stock["entry"],
                stop_loss=stock["sl"],
                target_price=stock["target"],
                quantity=stock["quantity"],
                risk_amount=round(stock["risk_amount"], 2),
                potential_profit=round(stock["potential_profit"], 2),
                potential_loss=round(stock["potential_loss"], 2),
                risk_reward_ratio=round(stock["risk_reward_ratio"], 2),
                confidence_score=float(rec.get("confidence_score", 0.5)),
                ai_reasoning=rec.get("reasoning", ""),
                days_to_target=rec.get("days_to_target"),
            ))
            total_investment += stock["investment_needed"]
            total_risk += stock["risk_amount"]
            max_profit += stock["potential_profit"]
            max_loss += stock["potential_loss"]

        if not stock_analyses:
            logger.error(
                f"All {len(llm_response.get('stocks', []))} LLM-recommended stocks failed "
                f"price validation. Check WARNING logs above for per-stock reasons."
            )
            raise HTTPException(
                status_code=503,
                detail=(
                    "No valid trade setups found in this scan — the LLM recommendations "
                    "did not pass price validation (stop-loss above entry or target below entry). "
                    "Please try again; the screener will fetch fresh market data."
                )
            )

        # Final balance check
        if total_investment > available_balance:
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Total investment ₹{total_investment:,.2f} exceeds "
                    f"available balance ₹{available_balance:,.2f}"
                ),
            )

        # ── Build response ────────────────────────────────────────────────
        analysis_id = str(uuid.uuid4())
        analysis = AnalysisResponse(
            analysis_id=analysis_id,
            request=request,
            stocks=stock_analyses,
            portfolio_metrics={
                "total_investment": round(total_investment, 2),
                "total_risk": round(total_risk, 2),
                "max_profit": round(max_profit, 2),
                "max_loss": round(max_loss, 2),
                "num_stocks": len(stock_analyses),
                "risk_percent": request.risk_percent,
                "available_balance": available_balance,
                "sectors": request.sectors,
                "hold_duration_days": request.hold_duration_days,
                "universe": "Full NSE Market",
            },
            available_balance=available_balance,
            status="PENDING_CONFIRMATION",
        )

        await db.save_analysis(analysis)
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
    Starts trade execution in the background.

    Returns HTTP 423 immediately if NSE market is closed so the
    client can surface a clear, actionable message to the user.
    """
    try:
        analysis_data = await db.get_analysis(analysis_id)
        if not analysis_data:
            raise HTTPException(status_code=404, detail="Analysis not found")

        if not confirmation.confirmed:
            await db.update_analysis_status(analysis_id, "CANCELLED")
            return {"status": "cancelled", "message": "Analysis cancelled by user"}

        # ── Market hours guard ────────────────────────────────────────────
        # Check BEFORE starting background execution so the user gets an
        # immediate, clear response instead of a silent background failure.
        if not order_service.is_market_open():
            market_msg = order_service.market_status_message()
            logger.warning(f"Execution blocked — market closed: {market_msg}")
            raise HTTPException(
                status_code=423,  # 423 Locked — semantically: resource temporarily unavailable
                detail=market_msg,
            )
        # ─────────────────────────────────────────────────────────────────

        await db.update_analysis_status(analysis_id, "EXECUTING")

        background_tasks.add_task(
            execute_trades,
            analysis_id,
            analysis_data,
            confirmation.access_token,
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
    hold_duration_days: int = 0,
    stock_overrides: list = None,
):
    """Background task: execute all trades for an analysis."""
    try:
        zerodha_service.kite.set_access_token(access_token)

        try:
            margins = await zerodha_service.get_margins()
            available_balance = margins.get("equity", {}).get("net", 100000)
            logger.info(f"Real account balance: ₹{available_balance:,.2f}")
        except Exception as e:
            logger.error(f"Balance fetch failed: {e}")
            available_balance = 100000

        stocks = analysis_data.get("stocks", [])

        # Apply user-edited quantity overrides (keyed by stock_symbol)
        if stock_overrides:
            override_map = {
                o["stock_symbol"]: o["quantity"]
                for o in stock_overrides
                if "stock_symbol" in o and "quantity" in o
            }
            for stock in stocks:
                sym = stock.get("stock_symbol")
                if sym in override_map:
                    original_qty = stock["quantity"]
                    stock["quantity"] = override_map[sym]
                    logger.info(
                        f"Quantity override applied for {sym}: "
                        f"{original_qty} → {override_map[sym]}"
                    )

        async def update_callback(update: ExecutionUpdate):
            await db.save_execution_update(update)
            if analysis_id not in active_executions:
                active_executions[analysis_id] = []
            active_executions[analysis_id].append(update)

        for stock in stocks:
            if stock["action"] == "BUY":
                await execution_agent.execute_trade_with_gtt(
                    stock_symbol=stock["stock_symbol"],
                    quantity=stock["quantity"],
                    entry_price=stock["entry_price"],
                    stop_loss=stock["stop_loss"],
                    target=stock["target_price"],
                    analysis_id=analysis_id,
                    update_callback=update_callback,
                    access_token=access_token,
                )

        await db.update_analysis_status(analysis_id, "COMPLETED")

    except Exception as e:
        logger.error(f"Trade execution failed: {e}")
        await db.update_analysis_status(analysis_id, "FAILED")


@router.get("/{analysis_id}/status", response_model=ExecutionStatus)
async def get_execution_status(analysis_id: str):
    """Get real-time execution status for an analysis."""
    try:
        analysis_data = await db.get_analysis(analysis_id)
        if not analysis_data:
            raise HTTPException(status_code=404, detail="Analysis not found")

        updates = await db.get_execution_updates(analysis_id)
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
    """Get recent analysis history."""
    try:
        return await db.get_all_analyses(limit=limit)
    except Exception as e:
        logger.error(f"History fetch failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))
