"""
Options Session Agent

Runs a continuous live trading session:
  - Scans the market every SCAN_INTERVAL_SECS using the options engine
  - If a BUY_CE / BUY_PE signal is found, auto-executes immediately
  - After execution, starts the monitoring agent (trailing SL, partial exit, etc.)
  - Emits live commentary events throughout (streamed to client via SSE)
  - Session ends on manual stop or fatal error

No user confirmation required — the engine is the sole authority.
"""

import asyncio
import uuid
from dataclasses import dataclass, field
from datetime import datetime, date
from typing import Dict, List, Optional

import pytz

from app.core.logging import logger
from app.engines.options_engine import options_engine, ATM_DELTA
from app.services.options_service import options_service
from app.services.zerodha_service import zerodha_service
from app.agents.options_llm_agent import options_llm_agent
from app.agents.options_execution_agent import options_execution_agent
from app.agents.options_monitoring_agent import (
    options_monitoring_agent,
    MonitoringSession,
)
from app.storage.database import db
from app.models.analysis_models import ExecutionUpdate

IST = pytz.timezone("Asia/Kolkata")

SCAN_INTERVAL_SECS = 180      # 3-minute scan cycle
MIN_CANDLES        = 10       # minimum candles needed by engine
MAX_TRADE_PER_DAY  = 1        # anti-overtrading: 1 trade per session per index


# ── Session state ──────────────────────────────────────────────────────────────

@dataclass
class TradingSession:
    session_id: str
    index: str
    expiry_date: date
    capital: float
    lots: int
    risk_percent: float
    api_key: str
    access_token: str
    user_id: Optional[str] = None

    # Runtime state
    running: bool = True
    phase: str = "SCANNING"      # SCANNING | EXECUTING | MONITORING | STOPPED | ERROR
    scan_count: int = 0
    trades_today: int = 0
    session_pnl: float = 0.0
    active_analysis_id: Optional[str] = None

    # Timestamps
    started_at: datetime = field(default_factory=datetime.utcnow)
    last_scan_at: Optional[datetime] = None
    next_scan_at: Optional[datetime] = None

    # Last engine output (for UI display)
    last_signal: str = ""
    last_regime: str = ""
    last_no_trade_reason: str = ""
    last_scan_indicators: dict = field(default_factory=dict)

    # Event queue — SSE reads from this
    events: asyncio.Queue = field(default_factory=asyncio.Queue)


# ── Session Agent ──────────────────────────────────────────────────────────────

class OptionsSessionAgent:

    def __init__(self):
        self._sessions: Dict[str, TradingSession] = {}

    # ── Public API ─────────────────────────────────────────────────────────────

    def start_session(self, session: TradingSession) -> None:
        """Launch continuous scan loop as a fire-and-forget background task."""
        self._sessions[session.session_id] = session
        asyncio.create_task(
            self._session_loop(session),
            name=f"session-{session.session_id}",
        )
        self._emit(session, "SESSION_STARTED", "INFO",
                   f"Live trading session started for {session.index}. "
                   f"Scanning every {SCAN_INTERVAL_SECS // 60} minutes. "
                   f"Capital: ₹{session.capital:,.0f} | Lots: {session.lots} | "
                   f"Risk: {session.risk_percent}%.",
                   {"index": session.index, "expiry": str(session.expiry_date),
                    "capital": session.capital, "lots": session.lots,
                    "risk_percent": session.risk_percent})

    def stop_session(self, session_id: str) -> bool:
        s = self._sessions.get(session_id)
        if not s:
            return False
        s.running = False
        s.phase = "STOPPED"
        self._emit(s, "SESSION_STOPPED", "INFO",
                   f"Session stopped manually. "
                   f"Scans: {s.scan_count} | Trades: {s.trades_today} | "
                   f"Session P&L: ₹{s.session_pnl:,.2f}.",
                   {"scans": s.scan_count, "trades": s.trades_today,
                    "session_pnl": s.session_pnl})
        return True

    def get_session(self, session_id: str) -> Optional[TradingSession]:
        return self._sessions.get(session_id)

    async def get_events_stream(self, session_id: str):
        """
        Async generator yielding SSE-formatted event strings.
        Yields heartbeat every 20 s to keep connection alive.
        Exits when session stops and queue is drained.
        """
        s = self._sessions.get(session_id)
        if not s:
            yield "data: {\"type\":\"ERROR\",\"message\":\"Session not found\"}\n\n"
            return

        while s.running or not s.events.empty():
            try:
                event = await asyncio.wait_for(s.events.get(), timeout=20.0)
                import json
                yield f"data: {json.dumps(event)}\n\n"
            except asyncio.TimeoutError:
                # Heartbeat to keep the connection alive
                yield "data: {\"type\":\"PING\"}\n\n"

        # Final flush — drain any remaining events
        import json
        while not s.events.empty():
            event = s.events.get_nowait()
            yield f"data: {json.dumps(event)}\n\n"

        yield "data: {\"type\":\"STREAM_END\"}\n\n"

    # ── Core scan loop ─────────────────────────────────────────────────────────

    async def _session_loop(self, s: TradingSession) -> None:
        """Main session loop: scan → signal check → execute → monitor → repeat."""
        loop = asyncio.get_event_loop()

        while s.running:
            try:
                now_ist = datetime.now(IST).replace(tzinfo=None)

                # ── Market hours guard ────────────────────────────────────────
                if not self._is_market_open(now_ist):
                    self._emit(s, "WAITING", "INFO",
                               f"Market is closed (IST {now_ist.strftime('%H:%M')}). "
                               "Waiting for market to open (9:30 AM).",
                               {})
                    await asyncio.sleep(60)
                    continue

                # ── Skip if a trade is already being monitored ────────────────
                if s.phase == "MONITORING":
                    monitor_session = (
                        options_monitoring_agent.get_session(s.active_analysis_id)
                        if s.active_analysis_id else None
                    )
                    if monitor_session and monitor_session.status == "MONITORING":
                        await asyncio.sleep(30)
                        continue
                    else:
                        # Trade closed — reset to scanning
                        if monitor_session:
                            pnl = (
                                (monitor_session.current_premium - monitor_session.entry_fill_price)
                                * monitor_session.quantity
                            )
                            s.session_pnl += pnl
                        s.phase = "SCANNING"
                        s.active_analysis_id = None

                # ── Step 1: Fetch live data ───────────────────────────────────
                s.last_scan_at = datetime.utcnow()
                s.scan_count += 1
                self._emit(s, "SCAN_START", "INFO",
                           f"Scan #{s.scan_count} — fetching live data for {s.index}...",
                           {"scan_count": s.scan_count})

                try:
                    current_price: float = await loop.run_in_executor(
                        None,
                        lambda: options_service.get_index_price(
                            s.index, s.api_key, s.access_token
                        ),
                    )
                except Exception as e:
                    self._emit(s, "SCAN_ERROR", "WARNING",
                               f"Could not fetch {s.index} price: {e}. Retrying in 60s.", {})
                    await asyncio.sleep(60)
                    continue

                # Parallel: candles + prev-day OHLC + futures volume ratio
                candles_task   = asyncio.create_task(
                    options_service.get_index_candles(s.index, s.api_key, s.access_token)
                )
                prev_day_task  = asyncio.create_task(
                    options_service.get_prev_day_ohlc(s.index, s.api_key, s.access_token)
                )
                fut_vol_task   = asyncio.create_task(
                    options_service.get_fut_volume_ratio(s.index, s.api_key, s.access_token)
                )
                candles, prev_day_ohlc, fut_volume_ratio = await asyncio.gather(
                    candles_task, prev_day_task, fut_vol_task, return_exceptions=True
                )

                if isinstance(candles, Exception) or not candles:
                    self._emit(s, "SCAN_ERROR", "WARNING",
                               f"Candle fetch failed: {candles}. Retrying in 60s.", {})
                    await asyncio.sleep(60)
                    continue

                prev_day_high = prev_day_ohlc.get("high", 0.0) if isinstance(prev_day_ohlc, dict) else 0.0
                prev_day_low  = prev_day_ohlc.get("low",  0.0) if isinstance(prev_day_ohlc, dict) else 0.0
                fvr = float(fut_volume_ratio) if isinstance(fut_volume_ratio, (int, float)) else 0.0

                if len(candles) < MIN_CANDLES:
                    self._emit(s, "SCAN_RESULT", "INFO",
                               f"Only {len(candles)} candles available — need ≥{MIN_CANDLES}. "
                               "Waiting for more price history.",
                               {"candles": len(candles)})
                    await asyncio.sleep(60)
                    continue

                # ── Step 2: Engine — regime + breakout ────────────────────────
                engine_result = options_engine.generate_signal(
                    candles=candles,
                    index=s.index,
                    expiry_date=s.expiry_date,
                    prev_day_high=prev_day_high,
                    prev_day_low=prev_day_low,
                    fut_volume_ratio=fvr,
                )
                ind = engine_result.indicators
                s.last_regime    = engine_result.regime.value
                s.last_signal    = engine_result.signal
                s.last_scan_indicators = ind

                if engine_result.signal == "NO_TRADE":
                    reason = (
                        engine_result.failed_filters[0]
                        if engine_result.failed_filters
                        else f"Regime: {engine_result.regime.value}"
                    )
                    s.last_no_trade_reason = reason
                    next_secs = SCAN_INTERVAL_SECS
                    s.next_scan_at = datetime.utcnow().__class__.fromtimestamp(
                        datetime.utcnow().timestamp() + next_secs
                    )
                    self._emit(s, "SCAN_RESULT", "INFO",
                               f"NO TRADE — {reason} "
                               f"(ADX: {engine_result.adx:.1f} | "
                               f"RSI: {ind.get('rsi', 0):.0f} | "
                               f"OR: {engine_result.or_high:.0f}/{engine_result.or_low:.0f}). "
                               f"Next scan in {next_secs // 60} min.",
                               {"signal": "NO_TRADE", "regime": engine_result.regime.value,
                                "reason": reason, "adx": engine_result.adx,
                                "indicators": ind})
                    await asyncio.sleep(next_secs)
                    continue

                # ── SIGNAL FOUND ─────────────────────────────────────────────
                opt_type = "CE" if engine_result.signal == "BUY_CE" else "PE"
                self._emit(s, "SIGNAL_FOUND", "INFO",
                           f"SIGNAL: {engine_result.signal} | Regime: {engine_result.regime.value} | "
                           f"ADX: {engine_result.adx:.1f} | {s.index} @ ₹{current_price:.0f}. "
                           f"Fetching ATM {opt_type} strike...",
                           {"signal": engine_result.signal,
                            "regime": engine_result.regime.value,
                            "adx": engine_result.adx,
                            "index_price": current_price,
                            "indicators": ind})

                # ── Step 3: ATM strike + live premiums ────────────────────────
                try:
                    atm_data = await loop.run_in_executor(
                        None,
                        lambda: options_service.select_atm_strike(
                            s.index, s.expiry_date, current_price,
                            s.api_key, s.access_token,
                        ),
                    )
                except Exception as e:
                    self._emit(s, "SCAN_ERROR", "WARNING",
                               f"ATM strike fetch failed: {e}. Skipping this scan.", {})
                    await asyncio.sleep(SCAN_INTERVAL_SECS)
                    continue

                if atm_data is None:
                    self._emit(s, "SCAN_ERROR", "WARNING",
                               f"No option contracts found for {s.index} expiry={s.expiry_date}. "
                               "Verify expiry date is still valid.", {})
                    await asyncio.sleep(SCAN_INTERVAL_SECS)
                    continue

                atm_strike  = atm_data["atm_strike"]
                ce_inst     = atm_data["ce"]
                pe_inst     = atm_data["pe"]
                lot_size    = int(ce_inst.get("lot_size") or options_service.get_lot_size(s.index))
                chosen_inst = ce_inst if opt_type == "CE" else pe_inst

                try:
                    premium_raw = await loop.run_in_executor(
                        None,
                        lambda: options_service.get_option_premium(
                            chosen_inst["tradingsymbol"], s.api_key, s.access_token
                        ),
                    )
                    entry_premium = float(premium_raw)
                except Exception:
                    entry_premium = float(chosen_inst.get("last_price", 0))

                if entry_premium <= 0:
                    self._emit(s, "SCAN_ERROR", "WARNING",
                               "Could not fetch live premium (returned 0). Skipping.", {})
                    await asyncio.sleep(SCAN_INTERVAL_SECS)
                    continue

                # ── Step 4: Compute premium levels ────────────────────────────
                if engine_result.sl_index_price > 0 and engine_result.entry_index_price > 0:
                    if opt_type == "CE":
                        index_risk_pts = engine_result.entry_index_price - engine_result.sl_index_price
                    else:
                        index_risk_pts = engine_result.sl_index_price - engine_result.entry_index_price
                    sl_from_structure = round(entry_premium - index_risk_pts * ATM_DELTA, 2)
                    sl_floor          = round(entry_premium * 0.75, 2)
                    sl_premium        = max(sl_from_structure, sl_floor, 0.05)
                else:
                    sl_premium = round(entry_premium * 0.75, 2)

                sl_premium     = round(sl_premium, 2)
                risk_premium   = round(entry_premium - sl_premium, 2)
                target_premium = round(entry_premium + 2.0 * risk_premium, 2)

                # Risk-based lot sizing (max 3% capital risk)
                max_risk_rupees = round(s.capital * 0.03, 2)
                risk_per_lot    = round(risk_premium * lot_size, 2)
                if risk_per_lot > 0:
                    max_safe_lots = max(1, int(max_risk_rupees / risk_per_lot))
                else:
                    max_safe_lots = s.lots
                lots_to_trade = min(s.lots, max_safe_lots)
                quantity      = lots_to_trade * lot_size

                # ── Step 5: GPT narrative (non-blocking) ──────────────────────
                try:
                    llm_summary = await options_llm_agent.summarize_trade(
                        index=s.index,
                        result=engine_result,
                        current_price=current_price,
                        expiry_date=s.expiry_date,
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
                        f"{engine_result.regime.value} breakout. ADX={engine_result.adx:.1f}"
                    )
                except Exception:
                    confidence   = 0.70
                    ai_reasoning = f"{engine_result.regime.value} breakout setup."

                # ── Step 6: Announce trade and execute ────────────────────────
                option_symbol = chosen_inst["tradingsymbol"]
                analysis_id   = str(uuid.uuid4())
                s.active_analysis_id = analysis_id
                s.phase = "EXECUTING"
                s.trades_today += 1

                self._emit(s, "TRADE_EXECUTING", "INFO",
                           f"Executing {opt_type} trade — {option_symbol} | "
                           f"Entry: ₹{entry_premium:.2f} | SL: ₹{sl_premium:.2f} | "
                           f"Target: ₹{target_premium:.2f} | Lots: {lots_to_trade} | "
                           f"Max loss: ₹{risk_premium * quantity:.0f}. "
                           f"AI: {ai_reasoning}",
                           {"option_symbol": option_symbol, "option_type": opt_type,
                            "entry_premium": entry_premium, "sl_premium": sl_premium,
                            "target_premium": target_premium, "lots": lots_to_trade,
                            "quantity": quantity, "confidence": confidence,
                            "ai_reasoning": ai_reasoning,
                            "strike": atm_strike, "lot_size": lot_size})

                # ── Execute ────────────────────────────────────────────────────
                execution_updates: List[ExecutionUpdate] = []

                async def _exec_callback(update: ExecutionUpdate):
                    execution_updates.append(update)
                    self._emit(s, "EXECUTION_UPDATE", "INFO",
                               update.message,
                               {"update_type": update.update_type})

                try:
                    result = await options_execution_agent.execute_options_trade(
                        option_symbol=option_symbol,
                        instrument_token=int(chosen_inst["instrument_token"]),
                        quantity=quantity,
                        entry_premium=entry_premium,
                        stop_loss_premium=sl_premium,
                        target_premium=target_premium,
                        analysis_id=analysis_id,
                        api_key=s.api_key,
                        access_token=s.access_token,
                        update_callback=_exec_callback,
                        analysis_sl=sl_premium,
                        analysis_target=target_premium,
                    )
                except Exception as e:
                    self._emit(s, "EXECUTION_FAILED", "DANGER",
                               f"Execution error: {e}. Reverting to SCANNING.",
                               {"error": str(e)})
                    s.phase = "SCANNING"
                    s.active_analysis_id = None
                    s.trades_today -= 1
                    await asyncio.sleep(SCAN_INTERVAL_SECS)
                    continue

                if result.get("status") != "COMPLETED" or not result.get("fill_price"):
                    self._emit(s, "EXECUTION_FAILED", "WARNING",
                               f"Order not filled — {result.get('message', 'unknown reason')}. "
                               "Reverting to SCANNING.",
                               result)
                    s.phase = "SCANNING"
                    s.active_analysis_id = None
                    s.trades_today -= 1
                    await asyncio.sleep(SCAN_INTERVAL_SECS)
                    continue

                fill_price = float(result["fill_price"])
                self._emit(s, "TRADE_PLACED", "INFO",
                           f"FILLED at ₹{fill_price:.2f}! SL order placed. "
                           f"Monitoring started — trailing SL active.",
                           {"fill_price": fill_price,
                            "sl_order_id": result.get("sl_order_id", ""),
                            "analysis_id": analysis_id})

                # Register trade with anti-overtrading guard
                options_engine.register_trade(s.index)

                # Persist to DB
                try:
                    await db.save_options_trade({
                        "analysis_id":    analysis_id,
                        "index_name":     s.index,
                        "option_symbol":  option_symbol,
                        "option_type":    opt_type,
                        "strike":         float(atm_strike),
                        "expiry_date":    str(s.expiry_date),
                        "lots":           lots_to_trade,
                        "quantity":       quantity,
                        "entry_premium":  entry_premium,
                        "sl_premium":     sl_premium,
                        "target_premium": target_premium,
                        "fill_price":     fill_price,
                        "sl_order_id":    str(result.get("sl_order_id", "")),
                        "target_order_id": str(result.get("target_order_id", "")),
                        "regime":         engine_result.regime.value,
                        "confidence":     confidence,
                        "signal_reasons": str(engine_result.reasons),
                        "failed_filters": str(engine_result.failed_filters),
                    })
                except Exception as e:
                    logger.warning(f"[SessionAgent] DB save failed: {e}")

                # ── Start monitoring ───────────────────────────────────────────
                monitor_session = MonitoringSession(
                    analysis_id=analysis_id,
                    symbol=option_symbol,
                    option_type=opt_type,
                    quantity=quantity,
                    entry_fill_price=fill_price,
                    sl_trigger=float(result.get("sl_trigger", sl_premium)),
                    sl_limit=float(result.get("sl_limit", sl_premium * 0.98)),
                    target_price=float(result.get("target_price", target_premium)),
                    sl_order_id=str(result.get("sl_order_id", "")),
                    target_order_id=str(result.get("target_order_id", "")),
                    api_key=s.api_key,
                    access_token=s.access_token,
                    instrument_token=int(chosen_inst["instrument_token"]),
                    index=s.index,
                    entry_index_price=current_price,
                )

                def _make_monitor_callback(sess: TradingSession):
                    async def _cb(event):
                        # Forward all monitoring events to session SSE stream
                        sess.events.put_nowait({
                            "type":        event.event_type,
                            "timestamp":   event.timestamp,
                            "message":     event.message,
                            "alert_level": event.alert_level,
                            "data":        event.data,
                        })
                    return _cb

                options_monitoring_agent.start_monitoring(
                    monitor_session,
                    _make_monitor_callback(s),
                )
                s.phase = "MONITORING"

                # Wait for monitoring to complete before rescanning
                while s.running:
                    ms = options_monitoring_agent.get_session(analysis_id)
                    if ms is None or ms.status not in ("MONITORING",):
                        break
                    await asyncio.sleep(30)

                # Capture final P&L when done
                final_ms = options_monitoring_agent.get_session(analysis_id)
                if final_ms:
                    trade_pnl = (
                        (final_ms.current_premium - final_ms.entry_fill_price)
                        * final_ms.quantity
                    )
                    s.session_pnl += trade_pnl
                    self._emit(s, "TRADE_CLOSED", "INFO",
                               f"Trade closed — {final_ms.symbol} | "
                               f"Exit premium: ₹{final_ms.current_premium:.2f} | "
                               f"P&L: ₹{trade_pnl:+,.2f} | "
                               f"Session total: ₹{s.session_pnl:+,.2f}.",
                               {"pnl": trade_pnl, "session_pnl": s.session_pnl,
                                "exit_premium": final_ms.current_premium,
                                "symbol": final_ms.symbol})

                s.phase = "SCANNING"
                s.active_analysis_id = None

                # Cooldown before next scan after a trade
                await asyncio.sleep(SCAN_INTERVAL_SECS)

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"[SessionAgent] Unhandled error in session {s.session_id}: {e}",
                             exc_info=True)
                self._emit(s, "ERROR", "WARNING",
                           f"Unexpected error: {e}. Resuming scan in 60s.", {})
                await asyncio.sleep(60)

        s.phase = "STOPPED"
        s.running = False
        logger.info(f"[SessionAgent] Session {s.session_id} ended. "
                    f"Scans: {s.scan_count} | Trades: {s.trades_today} | "
                    f"P&L: ₹{s.session_pnl:+,.2f}")

    # ── Helpers ────────────────────────────────────────────────────────────────

    @staticmethod
    def _is_market_open(now_ist: datetime) -> bool:
        if now_ist.weekday() >= 5:
            return False
        t = now_ist.time()
        from datetime import time as dtime
        return dtime(9, 30) <= t <= dtime(14, 0)

    def _emit(
        self,
        s: TradingSession,
        event_type: str,
        alert_level: str,
        message: str,
        data: dict,
    ) -> None:
        payload = {
            "type":        event_type,
            "timestamp":   datetime.utcnow().isoformat(),
            "alert_level": alert_level,
            "message":     message,
            "phase":       s.phase,
            "scan_count":  s.scan_count,
            "trades_today": s.trades_today,
            "session_pnl": s.session_pnl,
            "data":        data,
        }
        try:
            s.events.put_nowait(payload)
        except asyncio.QueueFull:
            pass
        logger.info(f"[SessionAgent/{s.session_id[:8]}] [{event_type}] {message}")


options_session_agent = OptionsSessionAgent()
