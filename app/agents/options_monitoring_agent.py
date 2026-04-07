"""
Options Monitoring Agent

Continuously monitors an open options position after execution:
  - Polls live premium every 30 seconds
  - Implements trailing stop-loss (moves SL up as premium rises)
  - Calls GPT-4o every 5 polls (~2.5 min) for exit/hold/tighten decision
  - Handles exceptions: auto-retries transient errors, flags human-needed issues
  - Pushes events to a callback so the route layer can serve them to the client
  - Forces exit at 3:00 PM IST (15 min before auto square-off)

Exception categories:
  AUTO_RETRY  — network/timeout, retry up to 3 times
  AUTO_FIX    — SL order not found, replace it; position closed externally, mark done
  HUMAN_NEEDED — permission errors, order rejected with no recourse, unknown state
"""

import asyncio
import json
from dataclasses import dataclass, field
from datetime import datetime, time as dtime
from typing import Callable, Dict, List, Optional

from openai import AsyncOpenAI
from kiteconnect import exceptions as kite_exc

from app.core.config import get_settings
from app.core.logging import logger
from app.services.zerodha_service import zerodha_service
from app.services.ticker_service import ticker_service

try:
    from kiteconnect import KiteTicker as _KiteTickerCheck
    KITE_TICKER_AVAILABLE = True
except ImportError:
    KITE_TICKER_AVAILABLE = False

settings = get_settings()

# ── Constants ──────────────────────────────────────────────────────────────────
POLL_INTERVAL_SECS = 30
GPT_EVERY_N_POLLS = 5          # call GPT every 5 × 30s = 2.5 minutes
MAX_RETRIES = 3
FORCE_EXIT_TIME = dtime(15, 0) # 3:00 PM IST
NFO_TICK = 0.05

# ── Trailing SL tiers ──────────────────────────────────────────────────────────
# Each tier defines: (min_gain_pct, trailing_distance_as_pct_of_peak)
# When premium gain crosses the threshold, trailing tightens.
# Example with entry=₹100:
#   Gain <20%  (premium <120): trail 30% of peak  → SL at peak×0.70
#   Gain 20–40% (₹120–₹140) : trail 25% of peak  → SL at peak×0.75
#   Gain 40–75% (₹140–₹175) : trail 20% of peak  → SL at peak×0.80
#   Gain 75%+  (premium>₹175): trail 15% of peak  → SL at peak×0.85
# Additionally: once gain ≥ 10%, SL is locked at breakeven (entry price) minimum.
TRAILING_TIERS = [
    (0.75, 0.15),   # gain ≥ 75% → trail 15% from peak  (very tight, lock most profit)
    (0.40, 0.20),   # gain ≥ 40% → trail 20% from peak
    (0.20, 0.25),   # gain ≥ 20% → trail 25% from peak
    (0.00, 0.30),   # gain <  20% → trail 30% from peak  (widest, don't stop out early)
]
BREAKEVEN_LOCK_PCT = 0.10   # lock SL at breakeven once gain reaches 10%
MIN_TRAIL_STEP = 2.0        # minimum ₹ improvement before updating SL order (avoids API spam)


# ── Data structures ────────────────────────────────────────────────────────────

@dataclass
class MonitoringEvent:
    timestamp: str
    event_type: str   # PREMIUM_UPDATE | SL_UPDATED | TRAILING_SL | GPT_DECISION
                      # EXIT_PLACED | POSITION_CLOSED | EXCEPTION | HUMAN_ALERT
    message: str
    data: Dict = field(default_factory=dict)
    alert_level: str = "INFO"   # INFO | WARNING | DANGER


@dataclass
class MonitoringSession:
    analysis_id: str
    symbol: str
    option_type: str          # CE or PE
    quantity: int
    entry_fill_price: float
    sl_trigger: float
    sl_limit: float
    target_price: float
    sl_order_id: str
    target_order_id: str
    api_key: str
    access_token: str
    instrument_token: int = 0   # Zerodha instrument token for WebSocket subscription

    # Trailing SL tracking
    peak_premium: float = 0.0
    initial_sl_distance: float = 0.0   # entry - sl_trigger (for reference only)
    trailing_distance: float = 0.0     # current trailing distance (shrinks as profit grows)
    breakeven_locked: bool = False      # True once SL has been locked at breakeven
    current_trail_tier: int = 0         # index into TRAILING_TIERS (0=widest)

    # State
    status: str = "MONITORING"  # MONITORING | EXITED | HUMAN_NEEDED | STOPPED
    current_premium: float = 0.0
    poll_count: int = 0
    retry_count: int = 0
    events: List[MonitoringEvent] = field(default_factory=list)

    # Live commentary
    commentary: List[Dict] = field(default_factory=list)
    commentary_language: str = "english"  # "english" | "hinglish"

    def __post_init__(self):
        self.peak_premium = self.entry_fill_price
        self.initial_sl_distance = self.entry_fill_price - self.sl_trigger
        self.trailing_distance = self.initial_sl_distance


# ── Agent ──────────────────────────────────────────────────────────────────────

class OptionsMonitoringAgent:

    def __init__(self):
        self.client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
        self._sessions: Dict[str, MonitoringSession] = {}
        self._sl_locks: Dict[str, asyncio.Lock] = {}  # per-session SL modification lock

    # ── Public API ─────────────────────────────────────────────────────────────

    def start_monitoring(
        self,
        session: MonitoringSession,
        event_callback: Callable,
    ):
        """Launch monitoring as a fire-and-forget background task."""
        self._sessions[session.analysis_id] = session
        self._sl_locks[session.analysis_id] = asyncio.Lock()
        asyncio.create_task(
            self._monitor_loop(session, event_callback),
            name=f"monitor-{session.analysis_id}",
        )
        logger.info(
            f"[Monitor] Started for {session.symbol} entry=₹{session.entry_fill_price:.2f} "
            f"sl=₹{session.sl_trigger:.2f} target=₹{session.target_price:.2f}"
        )
        self._add_commentary(
            session,
            "STARTED",
            f"Monitoring started for {session.symbol} ({session.option_type}). "
            f"Entry ₹{session.entry_fill_price:.2f} | SL ₹{session.sl_trigger:.2f} | "
            f"Target ₹{session.target_price:.2f}. AI will review every ~2.5 minutes.",
            f"{session.symbol} ({session.option_type}) ka monitoring shuru ho gaya. "
            f"Entry ₹{session.entry_fill_price:.2f} | SL ₹{session.sl_trigger:.2f} | "
            f"Target ₹{session.target_price:.2f}. AI har ~2.5 minute mein review karega.",
        )

    def stop_monitoring(self, analysis_id: str):
        """Mark session stopped (no exit order). Use stop_and_exit() for user-initiated stops."""
        session = self._sessions.get(analysis_id)
        if session:
            session.status = "STOPPED"

    async def stop_and_exit(self, analysis_id: str):
        """
        Called when the user taps 'Stop Monitoring':
          1. Cancel the open SL order on Zerodha
          2. Place a LIMIT SELL to exit the position
          3. Mark session as EXITED
        """
        session = self._sessions.get(analysis_id)
        if not session:
            return
        if session.status != "MONITORING":
            # Already exited/stopped — nothing to do
            return

        loop = asyncio.get_event_loop()

        async def _noop_cb(event):
            pass  # Events emitted during exit are stored on the session; no SSE push needed

        await self._exit_position(session, _noop_cb, loop, reason="MANUAL_STOP")

    def get_session(self, analysis_id: str) -> Optional[MonitoringSession]:
        return self._sessions.get(analysis_id)

    # ── Main loop ──────────────────────────────────────────────────────────────

    async def _monitor_loop(self, s: MonitoringSession, cb: Callable):
        loop = asyncio.get_event_loop()
        sl_lock = self._sl_locks.get(s.analysis_id, asyncio.Lock())

        # ── WebSocket tick callback ───────────────────────────────────────────────
        # Called on every LTP tick from KiteTicker (sub-second latency).
        async def on_tick(ltp: float):
            if s.status != "MONITORING":
                return
            s.current_premium = ltp
            s.poll_count += 1

            pnl = (ltp - s.entry_fill_price) * s.quantity
            pnl_pct = (ltp - s.entry_fill_price) / s.entry_fill_price * 100
            await self._emit(s, cb, "PREMIUM_UPDATE",
                             f"Premium=₹{ltp:.2f} | P&L=₹{pnl:+.0f} ({pnl_pct:+.1f}%)",
                             {"premium": ltp, "pnl": round(pnl, 2), "pnl_pct": round(pnl_pct, 2)},
                             "INFO")

            # Force exit at 3:00 PM
            if datetime.now().time() >= FORCE_EXIT_TIME:
                await self._emit(s, cb, "GPT_DECISION",
                                 "3:00 PM reached — force exiting.", {}, "WARNING")
                self._add_commentary(
                    s, "GPT_DECISION",
                    f"{s.symbol}: 3:00 PM reached — force exiting to avoid auto square-off. "
                    f"Current premium ₹{s.current_premium:.2f}.",
                    f"{s.symbol}: 3:00 PM aa gaya — auto square-off se bachne ke liye force exit ho raha hai. "
                    f"Current premium ₹{s.current_premium:.2f}.",
                )
                await self._exit_position(s, cb, loop, "TIME_EXIT")
                return

            # Target hit check — cancels SL first, then places single exit SELL
            await self._check_target_hit(s, cb, loop, ltp)
            if s.status != "MONITORING":
                return

            # Trailing SL (non-blocking — skip if SL lock held)
            if not sl_lock.locked():
                await self._apply_trailing_sl(s, cb, loop, ltp, sl_lock)

        # ── WebSocket order update callback ───────────────────────────────────────
        # Called when any order status changes — detect fills in real-time.
        async def on_order_update(data: dict):
            if s.status != "MONITORING":
                return
            oid = str(data.get("order_id", ""))
            status = str(data.get("status", "")).upper()
            avg = float(data.get("average_price") or data.get("price") or 0)

            if oid == str(s.sl_order_id) and status == "COMPLETE":
                s.current_premium = avg
                pnl = round((avg - s.entry_fill_price) * s.quantity, 2)
                await self._emit(s, cb, "POSITION_CLOSED",
                                 f"SL hit. Exit @ ₹{avg:.2f} P&L=₹{pnl:+.0f}",
                                 {"final_premium": avg, "pnl": pnl, "reason": "SL hit."}, "WARNING")
                self._add_commentary(
                    s, "POSITION_CLOSED",
                    f"{s.symbol}: Stop-loss triggered. Exited at ₹{avg:.2f}. "
                    f"P&L: ₹{pnl:+.0f}. The SL protected you from a larger loss.",
                    f"{s.symbol}: Stop-loss trigger hua. ₹{avg:.2f} pe exit ho gaya. "
                    f"P&L: ₹{pnl:+.0f}. SL ne bade nuksan se bacha liya.",
                )
                # Cancel target order
                try:
                    await loop.run_in_executor(
                        None, lambda: zerodha_service.kite.cancel_order(
                            variety=zerodha_service.kite.VARIETY_REGULAR,
                            order_id=s.target_order_id))
                except Exception as e:
                    logger.warning(f"[Monitor] Cancel target after SL fill failed: {e}")
                s.status = "EXITED"

            elif s.target_order_id and oid == str(s.target_order_id) and status == "COMPLETE":
                s.current_premium = avg
                pnl = round((avg - s.entry_fill_price) * s.quantity, 2)
                await self._emit(s, cb, "POSITION_CLOSED",
                                 f"Target hit. Exit @ ₹{avg:.2f} P&L=₹{pnl:+.0f}",
                                 {"final_premium": avg, "pnl": pnl, "reason": "Target hit."}, "INFO")
                self._add_commentary(
                    s, "POSITION_CLOSED",
                    f"{s.symbol}: Target hit! Exited at ₹{avg:.2f}. "
                    f"P&L: ₹{pnl:+.0f}. Excellent trade!",
                    f"{s.symbol}: Target lag gaya! ₹{avg:.2f} pe exit ho gaya. "
                    f"P&L: ₹{pnl:+.0f}. Zabardast trade!",
                )
                # Cancel SL order
                try:
                    await loop.run_in_executor(
                        None, lambda: zerodha_service.kite.cancel_order(
                            variety=zerodha_service.kite.VARIETY_REGULAR,
                            order_id=s.sl_order_id))
                except Exception as e:
                    logger.warning(f"[Monitor] Cancel SL after target fill failed: {e}")
                s.status = "EXITED"

        # ── Subscribe to WebSocket if instrument_token is available ──────────────
        ws_active = False
        if s.instrument_token and KITE_TICKER_AVAILABLE:
            try:
                zerodha_service.set_credentials(s.api_key, s.access_token)
                subscribed = ticker_service.subscribe_monitoring(
                    s.api_key, s.access_token, s.instrument_token, on_tick, loop
                )
                ticker_service.add_order_callback(s.api_key, s.access_token, on_order_update)
                ws_active = subscribed
                logger.info(
                    f"[Monitor] WebSocket subscribed — token={s.instrument_token} "
                    f"symbol={s.symbol}"
                )
            except Exception as e:
                logger.warning(f"[Monitor] WebSocket subscribe failed, falling back to poll: {e}")
                ws_active = False

        # ── GPT timer task (runs every 5 minutes regardless of tick count) ───────
        async def gpt_timer():
            while s.status == "MONITORING":
                await asyncio.sleep(GPT_EVERY_N_POLLS * POLL_INTERVAL_SECS)
                if s.status != "MONITORING":
                    break
                if s.current_premium <= 0:
                    continue
                try:
                    decision = await self._ask_gpt(s, s.current_premium)
                    await self._act_on_gpt(s, cb, loop, decision, s.current_premium, sl_lock)
                except Exception as e:
                    logger.warning(f"[Monitor] GPT timer error: {e}")

        gpt_task = asyncio.create_task(gpt_timer())

        # ── Main wait loop ────────────────────────────────────────────────────────
        if ws_active:
            # WebSocket drives everything — just keep alive and check status
            while s.status == "MONITORING":
                await asyncio.sleep(5)
                # Fallback position check every 60s in case WebSocket missed something
                if s.poll_count > 0 and s.poll_count % 12 == 0:
                    try:
                        zerodha_service.set_credentials(s.api_key, s.access_token)
                        closed, reason = await self._check_position_closed(s, loop)
                        if closed:
                            pnl = round((s.current_premium - s.entry_fill_price) * s.quantity, 2)
                            await self._emit(s, cb, "POSITION_CLOSED",
                                             f"{reason} Exit @ ₹{s.current_premium:.2f} P&L=₹{pnl:+.0f}",
                                             {"final_premium": s.current_premium, "pnl": pnl, "reason": reason},
                                             "INFO")
                            self._add_commentary(
                                s, "POSITION_CLOSED",
                                f"{s.symbol}: Position closed — {reason} "
                                f"Exit ₹{s.current_premium:.2f} | P&L: ₹{pnl:+.0f}.",
                                f"{s.symbol}: Position band hua — {reason} "
                                f"Exit ₹{s.current_premium:.2f} | P&L: ₹{pnl:+.0f}.",
                            )
                            s.status = "EXITED"
                    except Exception:
                        pass
        else:
            # ── REST fallback: fast price loop + slow monitoring loop ─────────────
            # fast_price_loop (every 2s): fetches LTP → keeps current_premium fresh
            #   so the SSE /pnl-stream always has up-to-date data.
            # slow loop (every 30s): position-close check, target hit, trailing SL,
            #   force-exit, GPT actions — avoids hammering the Zerodha API.
            logger.info(f"[Monitor] Using REST poll fallback for {s.symbol} (fast+slow split)")

            async def fast_price_loop():
                """Update current_premium every 2 seconds via kite.ltp()."""
                while s.status == "MONITORING":
                    await asyncio.sleep(2)
                    if s.status != "MONITORING":
                        break
                    try:
                        ltp = await self._fetch_ltp_only(s.symbol)
                        if ltp and ltp > 0:
                            s.current_premium = ltp
                            s.poll_count += 1
                    except Exception:
                        pass  # slow loop handles persistent errors

            fast_task = asyncio.create_task(fast_price_loop())

            try:
                while s.status == "MONITORING":
                    await asyncio.sleep(POLL_INTERVAL_SECS)  # heavy checks every 30s

                    try:
                        zerodha_service.set_credentials(s.api_key, s.access_token)

                        closed, close_reason = await self._check_position_closed(s, loop)
                        if closed:
                            pnl = round((s.current_premium - s.entry_fill_price) * s.quantity, 2)
                            await self._emit(s, cb, "POSITION_CLOSED",
                                             f"{close_reason} Exit @ ₹{s.current_premium:.2f} P&L=₹{pnl:+.0f}",
                                             {"final_premium": s.current_premium, "pnl": pnl, "reason": close_reason},
                                             "INFO")
                            self._add_commentary(
                                s, "POSITION_CLOSED",
                                f"{s.symbol}: Position closed — {close_reason} "
                                f"Exit ₹{s.current_premium:.2f} | P&L: ₹{pnl:+.0f}.",
                                f"{s.symbol}: Position band hua — {close_reason} "
                                f"Exit ₹{s.current_premium:.2f} | P&L: ₹{pnl:+.0f}.",
                            )
                            s.status = "EXITED"
                            break

                        premium = s.current_premium  # already kept fresh by fast_price_loop
                        if premium <= 0:
                            continue

                        s.retry_count = 0
                        pnl = (premium - s.entry_fill_price) * s.quantity
                        pnl_pct = ((premium - s.entry_fill_price) / s.entry_fill_price) * 100
                        await self._emit(s, cb, "PREMIUM_UPDATE",
                                         f"Premium=₹{premium:.2f} | P&L=₹{pnl:+.0f} ({pnl_pct:+.1f}%)",
                                         {"premium": premium, "pnl": round(pnl, 2), "pnl_pct": round(pnl_pct, 2)},
                                         "INFO")

                        if datetime.now().time() >= FORCE_EXIT_TIME:
                            await self._emit(s, cb, "GPT_DECISION",
                                             "3:00 PM reached — force exiting.", {}, "WARNING")
                            self._add_commentary(
                                s, "GPT_DECISION",
                                f"{s.symbol}: 3:00 PM reached — force exiting to avoid auto square-off. "
                                f"Current premium ₹{s.current_premium:.2f}.",
                                f"{s.symbol}: 3:00 PM aa gaya — auto square-off se bachne ke liye force exit ho raha hai. "
                                f"Current premium ₹{s.current_premium:.2f}.",
                            )
                            await self._exit_position(s, cb, loop, "TIME_EXIT")
                            break

                        # Target hit check — cancels SL first, then places single exit SELL
                        await self._check_target_hit(s, cb, loop, premium)
                        if s.status != "MONITORING":
                            break

                        async with sl_lock:
                            await self._apply_trailing_sl(s, cb, loop, premium, sl_lock)

                    except kite_exc.PermissionException as e:
                        await self._human_alert(s, cb,
                            f"Permission denied — access token may have expired: {e}",
                            {"error": str(e), "action_needed": "Re-login and provide new access token"})
                        break
                    except Exception as e:
                        await self._handle_unexpected(s, cb, e)
                        if s.status != "MONITORING":
                            break
            finally:
                fast_task.cancel()
                try:
                    await fast_task
                except asyncio.CancelledError:
                    pass

        # ── Cleanup ───────────────────────────────────────────────────────────────
        gpt_task.cancel()
        if ws_active:
            try:
                ticker_service.unsubscribe_monitoring(s.api_key, s.instrument_token, on_tick)
                ticker_service.remove_order_callback(s.api_key, on_order_update)
            except Exception as e:
                logger.warning(f"[Monitor] WebSocket cleanup error: {e}")

        logger.info(f"[Monitor] Loop ended for {s.symbol} status={s.status}")

    # ── Step helpers ───────────────────────────────────────────────────────────

    async def _check_position_closed(
        self, s: MonitoringSession, loop
    ) -> tuple[bool, str]:
        """
        Return (True, reason) if the position has been closed by any means:
          1. SL or target order filled by exchange (normal exit)
          2. Net position quantity is 0 (manual exit via Kite app)
        Returns (False, "") if position is still open.
        """
        # ── Check 1: SL or target order filled ───────────────────────────────
        try:
            orders = await loop.run_in_executor(None, zerodha_service.kite.orders)
            for order in orders:
                oid = str(order.get("order_id", ""))
                status = order.get("status", "").upper()
                if oid in (str(s.sl_order_id), str(s.target_order_id)):
                    if status == "COMPLETE":
                        avg = float(order.get("average_price", 0))
                        s.current_premium = avg
                        is_sl = oid == str(s.sl_order_id)
                        reason = "SL hit." if is_sl else "Target hit."
                        logger.info(
                            f"[Monitor] {s.symbol} {reason} order {oid} "
                            f"@ ₹{avg:.2f}"
                        )
                        return True, reason
        except Exception as e:
            logger.warning(f"[Monitor] order check failed: {e}")

        # ── Check 2: Manual exit — net position qty dropped to 0 ─────────────
        try:
            positions = await loop.run_in_executor(
                None, zerodha_service.kite.positions
            )
            net_positions = positions.get("net", [])
            for pos in net_positions:
                if pos.get("tradingsymbol") == s.symbol:
                    net_qty = int(pos.get("quantity", s.quantity))
                    if net_qty == 0:
                        logger.info(
                            f"[Monitor] {s.symbol} manual exit detected (net qty=0). "
                            "Cancelling pending SL/target orders."
                        )
                        await self._cancel_pending_orders(s, loop)
                        s.current_premium = float(
                            pos.get("last_price", s.current_premium)
                        )
                        return True, "Manually exited via Kite app."
                    break
        except Exception as e:
            logger.warning(f"[Monitor] position check failed: {e}")

        return False, ""

    async def _cancel_pending_orders(self, s: MonitoringSession, loop):
        """Cancel SL and target orders after a manual exit."""
        for oid in [s.sl_order_id, s.target_order_id]:
            if not oid:
                continue
            try:
                await loop.run_in_executor(
                    None,
                    lambda o=oid: zerodha_service.kite.cancel_order(
                        variety=zerodha_service.kite.VARIETY_REGULAR,
                        order_id=o,
                    ),
                )
                logger.info(f"[Monitor] Cancelled order {oid} after manual exit")
            except Exception as e:
                logger.warning(f"[Monitor] Cancel order {oid} failed: {e}")

    async def _fetch_ltp_only(self, option_symbol: str) -> Optional[float]:
        """
        Lightweight single-attempt LTP fetch — used by the fast price loop (every 2s).
        No retries, no logging on failure. Falls back silently so the loop keeps running.
        """
        try:
            loop = asyncio.get_event_loop()
            nfo_key = f"NFO:{option_symbol}"
            ltp_data = await loop.run_in_executor(
                None, lambda: zerodha_service.kite.ltp([nfo_key])
            )
            ltp = ltp_data.get(nfo_key, {}).get("last_price", 0.0)
            return float(ltp) if ltp else None
        except Exception:
            return None

    async def _fetch_live_premium(
        self, s: MonitoringSession, loop
    ) -> Optional[float]:
        """Fetch LTP for the option. Retries up to MAX_RETRIES on transient errors."""
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                nfo_key = f"NFO:{s.symbol}"
                ltp_data = await loop.run_in_executor(
                    None, lambda: zerodha_service.kite.ltp([nfo_key])
                )
                key = list(ltp_data.keys())[0]
                return float(ltp_data[key]["last_price"])
            except (ConnectionError, TimeoutError, OSError) as e:
                if attempt == MAX_RETRIES:
                    await self._human_alert(s, None,
                        f"Network error fetching premium after {MAX_RETRIES} retries: {e}",
                        {"error": str(e), "action_needed": "Check internet connectivity on server"})
                    return None
                await asyncio.sleep(5 * attempt)
            except kite_exc.DataException as e:
                # Transient data error — skip this poll
                logger.warning(f"[Monitor] DataException on premium fetch: {e}")
                return None
            except Exception as e:
                logger.warning(f"[Monitor] premium fetch attempt {attempt} failed: {e}")
                if attempt == MAX_RETRIES:
                    return None
                await asyncio.sleep(5)
        return None

    async def _check_target_hit(
        self, s: MonitoringSession, cb: Callable, loop, premium: float
    ):
        """
        Check if premium has reached or exceeded the target price.
        If so, cancel the SL order first (to avoid two open SELL orders) and
        then place a LIMIT SELL exit order at the current premium.
        This replaces the second simultaneous SELL order that Zerodha rejects.
        """
        if premium < s.target_price:
            return
        if s.status != "MONITORING":
            return

        await self._emit(s, cb, "GPT_DECISION",
            f"Target ₹{s.target_price:.2f} reached (premium=₹{premium:.2f}) — exiting.",
            {"reason": "TARGET_HIT", "premium": premium, "target": s.target_price},
            "INFO")
        self._add_commentary(
            s, "GPT_DECISION",
            f"{s.symbol}: Target ₹{s.target_price:.2f} reached! "
            f"Placing exit sell at ₹{premium:.2f}.",
            f"{s.symbol}: Target ₹{s.target_price:.2f} lag gaya! "
            f"₹{premium:.2f} pe exit sell lag raha hai.",
        )
        await self._exit_position(s, cb, loop, reason="TARGET_HIT")

    def _get_trail_pct(self, gain_pct: float) -> tuple:
        """
        Return (trail_pct, tier_index) for the current gain level.
        Picks the tightest tier that applies (highest gain threshold first).
        """
        for i, (min_gain, trail_pct) in enumerate(TRAILING_TIERS):
            if gain_pct >= min_gain:
                return trail_pct, i
        return TRAILING_TIERS[-1][1], len(TRAILING_TIERS) - 1

    async def _apply_trailing_sl(
        self, s: MonitoringSession, cb: Callable, loop, premium: float,
        sl_lock: Optional[asyncio.Lock] = None,
    ):
        """
        Tiered trailing SL:
          - Trail distance tightens automatically as profit grows
          - Locks SL at breakeven once gain ≥ 10%
          - Minimum ₹2 step to avoid spamming the SL order API
          - Never moves SL downward
        """
        # Only trail on new highs
        if premium <= s.peak_premium:
            return

        s.peak_premium = premium
        entry = s.entry_fill_price

        # ── Determine trailing percentage based on gain tier ─────────────
        gain_pct = (premium - entry) / entry if entry > 0 else 0.0
        trail_pct, tier_idx = self._get_trail_pct(gain_pct)
        trail_distance = self._snap_tick(premium * trail_pct)

        # ── Compute new SL trigger ─────────────────────────────────────────
        new_trigger = self._snap_tick(premium - trail_distance)

        # ── Breakeven lock: SL must be ≥ entry once gain ≥ 10% ───────────
        if gain_pct >= BREAKEVEN_LOCK_PCT:
            new_trigger = max(new_trigger, self._snap_tick(entry))
            if not s.breakeven_locked and new_trigger >= entry:
                s.breakeven_locked = True
                logger.info(
                    f"[Monitor] {s.symbol} SL locked at breakeven ₹{entry:.2f} "
                    f"(gain={gain_pct*100:.1f}%)"
                )

        # ── Never move SL down ────────────────────────────────────────────
        new_trigger = max(new_trigger, s.sl_trigger)

        # ── Minimum step filter — avoid API spam for tiny moves ──────────
        if new_trigger - s.sl_trigger < MIN_TRAIL_STEP:
            return

        new_limit = self._snap_tick(new_trigger * 0.98)

        # ── Apply the SL modification ─────────────────────────────────────
        if sl_lock:
            async with sl_lock:
                updated = await self._modify_sl_order(s, cb, loop, new_trigger, new_limit)
        else:
            updated = await self._modify_sl_order(s, cb, loop, new_trigger, new_limit)

        if updated:
            old_sl = s.sl_trigger
            old_tier = s.current_trail_tier
            s.sl_trigger = new_trigger
            s.sl_limit = new_limit
            s.trailing_distance = trail_distance
            s.current_trail_tier = tier_idx

            locked_pnl = round((new_trigger - entry) * s.quantity, 2)
            tier_changed = tier_idx < old_tier  # tier_idx lower = tighter tier

            tier_labels = ["30%", "25%", "20%", "15%"]
            tier_label = tier_labels[tier_idx] if tier_idx < len(tier_labels) else "15%"

            # Build context-aware message
            if s.breakeven_locked and old_sl < entry <= new_trigger:
                action_note = "Breakeven locked — no loss possible"
            elif tier_changed:
                action_note = f"Trail tightened to {tier_label} (gain={gain_pct*100:.0f}%)"
            else:
                action_note = f"Trail={tier_label} of peak"

            await self._emit(s, cb, "TRAILING_SL",
                f"Trailing SL ₹{old_sl:.2f} → ₹{new_trigger:.2f} "
                f"({action_note}, peak=₹{premium:.2f}, locked=₹{locked_pnl:+.0f})",
                {"old_sl": old_sl, "new_sl": new_trigger, "peak": premium,
                 "locked_pnl": locked_pnl, "trail_pct": trail_pct,
                 "breakeven_locked": s.breakeven_locked,
                 "tier": tier_label}, "INFO")

            self._add_commentary(
                s, "TRAILING_SL",
                f"{s.symbol}: Trailing SL moved to ₹{new_trigger:.2f} "
                f"(was ₹{old_sl:.2f}). {action_note}. "
                f"₹{abs(locked_pnl):.0f} profit now protected.",
                f"{s.symbol}: Trailing SL ₹{new_trigger:.2f} pe aa gaya "
                f"(pehle ₹{old_sl:.2f} tha). {action_note}. "
                f"₹{abs(locked_pnl):.0f} ka profit ab safe hai.",
            )

    async def _modify_sl_order(
        self, s: MonitoringSession, cb: Optional[Callable], loop,
        new_trigger: float, new_limit: float
    ) -> bool:
        """Try modify_order first; fall back to cancel + replace."""
        try:
            await loop.run_in_executor(
                None,
                lambda: zerodha_service.kite.modify_order(
                    variety=zerodha_service.kite.VARIETY_REGULAR,
                    order_id=s.sl_order_id,
                    trigger_price=new_trigger,
                    price=new_limit,
                    order_type=zerodha_service.kite.ORDER_TYPE_SL,
                ),
            )
            logger.info(f"[Monitor] SL modified to trigger=₹{new_trigger:.2f}")
            return True
        except Exception as e:
            err = str(e)
            if self._is_transient(err):
                # Exchange is mid-processing — skip this trailing SL update,
                # the next poll will try again when the order is settled.
                logger.warning(f"[Monitor] SL modify skipped (transient): {err}")
                return False
            logger.warning(f"[Monitor] modify_order failed ({e}) — trying cancel+replace")

        # Cancel existing + place new
        try:
            await loop.run_in_executor(
                None,
                lambda: zerodha_service.kite.cancel_order(
                    variety=zerodha_service.kite.VARIETY_REGULAR,
                    order_id=s.sl_order_id,
                ),
            )
        except Exception as e:
            logger.warning(f"[Monitor] cancel SL failed: {e}")

        try:
            new_order_id = await loop.run_in_executor(
                None,
                lambda: zerodha_service.kite.place_order(
                    variety=zerodha_service.kite.VARIETY_REGULAR,
                    exchange=zerodha_service.kite.EXCHANGE_NFO,
                    tradingsymbol=s.symbol,
                    transaction_type=zerodha_service.kite.TRANSACTION_TYPE_SELL,
                    quantity=s.quantity,
                    product=zerodha_service.kite.PRODUCT_MIS,
                    order_type=zerodha_service.kite.ORDER_TYPE_SL,
                    trigger_price=new_trigger,
                    price=new_limit,
                ),
            )
            s.sl_order_id = str(new_order_id)
            return True
        except Exception as e:
            if cb:
                await self._human_alert(s, cb,
                    f"Cannot update SL order: {e}. Manual intervention required.",
                    {"error": str(e), "action_needed": f"Manually set SL at ₹{new_trigger:.2f}"})
            return False

    async def _exit_position(
        self, s: MonitoringSession, cb: Callable, loop, reason: str
    ):
        """
        Exit the position safely:
          1. Cancel SL order and wait for confirmation — placing a SELL while an SL
             order is still OPEN causes Zerodha to reject with "existing sell order".
          2. Cancel target order.
          3. Place LIMIT SELL at current_premium × 0.99 for quick fill.
        """
        await self._emit(s, cb, "EXIT_PLACING",
            f"Preparing exit (reason={reason}): cancelling SL order first…",
            {"reason": reason}, "WARNING")

        # ── Step 1: Cancel SL order and WAIT for it to reach terminal state ──
        if s.sl_order_id:
            try:
                await loop.run_in_executor(
                    None,
                    lambda: zerodha_service.kite.cancel_order(
                        variety=zerodha_service.kite.VARIETY_REGULAR,
                        order_id=s.sl_order_id,
                    ),
                )
                confirmed = await self._wait_for_order_cancel(s.sl_order_id, loop)
                if not confirmed:
                    logger.warning(
                        f"[Monitor] SL order {s.sl_order_id} did not confirm cancel "
                        "within 6s — proceeding to place exit anyway"
                    )
            except Exception as e:
                logger.warning(f"[Monitor] Cancel SL {s.sl_order_id} failed: {e}")

        # ── Step 2: Cancel target order (best-effort, no wait needed) ────────
        if s.target_order_id:
            try:
                await loop.run_in_executor(
                    None,
                    lambda: zerodha_service.kite.cancel_order(
                        variety=zerodha_service.kite.VARIETY_REGULAR,
                        order_id=s.target_order_id,
                    ),
                )
            except Exception as e:
                logger.warning(f"[Monitor] Cancel target {s.target_order_id} failed: {e}")

        # ── Step 3: Place LIMIT SELL exit order ───────────────────────────────
        exit_price = self._snap_tick(s.current_premium * 0.99)
        try:
            exit_order_id = await loop.run_in_executor(
                None,
                lambda: zerodha_service.kite.place_order(
                    variety=zerodha_service.kite.VARIETY_REGULAR,
                    exchange=zerodha_service.kite.EXCHANGE_NFO,
                    tradingsymbol=s.symbol,
                    transaction_type=zerodha_service.kite.TRANSACTION_TYPE_SELL,
                    quantity=s.quantity,
                    product=zerodha_service.kite.PRODUCT_MIS,
                    order_type=zerodha_service.kite.ORDER_TYPE_LIMIT,
                    price=exit_price,
                ),
            )
            pnl = (exit_price - s.entry_fill_price) * s.quantity
            await self._emit(s, cb, "EXIT_PLACED",
                f"Exit order placed @ ₹{exit_price:.2f} (reason={reason}). "
                f"Est. P&L=₹{pnl:+.0f}",
                {"exit_price": exit_price, "order_id": str(exit_order_id),
                 "pnl": round(pnl, 2), "reason": reason}, "WARNING")
            _reason_label = {
                "TIME_EXIT": "3:00 PM time exit",
                "GPT_EXIT": "AI recommended exit",
                "MANUAL_STOP": "Manual stop by user",
            }.get(reason, reason)
            self._add_commentary(
                s, "EXIT_PLACED",
                f"{s.symbol}: Exit order placed at ₹{exit_price:.2f} ({_reason_label}). "
                f"Estimated P&L: ₹{pnl:+.0f}.",
                f"{s.symbol}: Exit order ₹{exit_price:.2f} pe lagaya ({_reason_label}). "
                f"Estimated P&L: ₹{pnl:+.0f}.",
            )
            s.status = "EXITED"
        except Exception as e:
            await self._human_alert(s, cb,
                f"CRITICAL: Cannot place exit order: {e}. Close position manually NOW.",
                {"error": str(e), "action_needed": "Manually sell position on Zerodha app",
                 "symbol": s.symbol, "quantity": s.quantity})

    async def _wait_for_order_cancel(
        self, order_id: str, loop, timeout: float = 6.0
    ) -> bool:
        """
        Poll order status until CANCELLED / REJECTED / COMPLETE or timeout.
        Returns True when the order reaches a terminal state.
        Called before placing an exit SELL to ensure the active SL order
        (also a SELL) is gone — Zerodha rejects duplicate open SELL orders.
        """
        deadline = loop.time() + timeout
        while loop.time() < deadline:
            try:
                orders = await loop.run_in_executor(None, zerodha_service.kite.orders)
                order = next(
                    (o for o in orders if str(o.get("order_id", "")) == str(order_id)),
                    None,
                )
                if order:
                    status = order.get("status", "").upper()
                    if status in ("CANCELLED", "REJECTED", "COMPLETE"):
                        logger.info(f"[Monitor] Order {order_id} confirmed {status}")
                        return True
            except Exception as e:
                logger.warning(f"[Monitor] Cancel poll error: {e}")
            await asyncio.sleep(0.5)
        return False

    # ── GPT decision ───────────────────────────────────────────────────────────

    async def _ask_gpt(self, s: MonitoringSession, premium: float) -> Dict:
        elapsed = s.poll_count * POLL_INTERVAL_SECS // 60
        now = datetime.now()
        mins_to_close = max(0, (FORCE_EXIT_TIME.hour * 60 + FORCE_EXIT_TIME.minute)
                            - (now.hour * 60 + now.minute))
        pnl_pct = ((premium - s.entry_fill_price) / s.entry_fill_price) * 100

        prompt = f"""You are monitoring an open intraday options trade.

Position:
- Symbol: {s.symbol} ({s.option_type})
- Entry fill: ₹{s.entry_fill_price:.2f}
- Current premium: ₹{premium:.2f}
- SL trigger: ₹{s.sl_trigger:.2f}  (trailing, currently at peak={s.peak_premium:.2f})
- Target: ₹{s.target_price:.2f}
- P&L: {pnl_pct:+.1f}%
- Held: {elapsed} minutes | Minutes to forced close: {mins_to_close}

Decide ONE action:
1. HOLD — momentum intact, keep position
2. TIGHTEN_SL:<price> — move SL to this price (must be > current SL ₹{s.sl_trigger:.2f})
3. EXIT_NOW — exit immediately (momentum reversed, risk outweighs reward)

Rules:
- If P&L > +40% and momentum slowing, tighten SL to lock gains
- If P&L < -15% and no recovery signs, EXIT_NOW
- If < 20 min to forced close and P&L > 0, TIGHTEN_SL aggressively
- If < 10 min to forced close, EXIT_NOW regardless

Respond ONLY with valid JSON:
{{"action": "HOLD" | "TIGHTEN_SL" | "EXIT_NOW", "new_sl": <float or null>, "reasoning": "<one sentence>"}}"""

        try:
            resp = await self.client.chat.completions.create(
                model="gpt-4o",
                messages=[
                    {"role": "system", "content": "You are an options trade monitor. Respond ONLY with valid JSON."},
                    {"role": "user", "content": prompt},
                ],
                response_format={"type": "json_object"},
                temperature=0.1,
                max_tokens=150,
            )
            return json.loads(resp.choices[0].message.content)
        except Exception as e:
            logger.error(f"[Monitor] GPT call failed ({type(e).__name__}): {e}")
            return {"action": "HOLD", "new_sl": None, "reasoning": f"Holding (AI check skipped: {type(e).__name__})"}

    async def _act_on_gpt(
        self, s: MonitoringSession, cb: Callable, loop, decision: Dict, premium: float,
        sl_lock: Optional[asyncio.Lock] = None,
    ):
        action = decision.get("action", "HOLD").upper()
        reasoning = decision.get("reasoning", "")

        await self._emit(s, cb, "GPT_DECISION",
            f"AI decision: {action} — {reasoning}",
            {"action": action, "reasoning": reasoning, "premium": premium},
            "INFO" if action == "HOLD" else "WARNING")
        _action_label = {"HOLD": "Hold", "EXIT_NOW": "Exit now", "TIGHTEN_SL": "Tighten SL"}.get(action, action)
        self._add_commentary(
            s, "GPT_DECISION",
            f"{s.symbol}: AI says '{_action_label}' — {reasoning} "
            f"(premium ₹{premium:.2f})",
            f"{s.symbol}: AI ne kaha '{_action_label}' — {reasoning} "
            f"(premium ₹{premium:.2f})",
        )

        if action == "EXIT_NOW":
            await self._exit_position(s, cb, loop, reason="GPT_EXIT")

        elif action == "TIGHTEN_SL":
            new_sl_raw = decision.get("new_sl")
            if new_sl_raw and float(new_sl_raw) > s.sl_trigger:
                new_trigger = self._snap_tick(float(new_sl_raw))
                new_limit = self._snap_tick(new_trigger * 0.98)
                if sl_lock:
                    async with sl_lock:
                        updated = await self._modify_sl_order(s, cb, loop, new_trigger, new_limit)
                else:
                    updated = await self._modify_sl_order(s, cb, loop, new_trigger, new_limit)
                if updated:
                    old_sl = s.sl_trigger
                    s.sl_trigger = new_trigger
                    s.sl_limit = new_limit
                    await self._emit(s, cb, "SL_UPDATED",
                        f"AI tightened SL: ₹{old_sl:.2f} → ₹{new_trigger:.2f}",
                        {"old_sl": old_sl, "new_sl": new_trigger}, "INFO")
                    self._add_commentary(
                        s, "SL_UPDATED",
                        f"{s.symbol}: AI tightened SL from ₹{old_sl:.2f} to ₹{new_trigger:.2f} "
                        f"to lock in more profit.",
                        f"{s.symbol}: AI ne SL ₹{old_sl:.2f} se ₹{new_trigger:.2f} kar diya — "
                        f"aur zyada profit lock karne ke liye.",
                    )

    # ── Exception handling ─────────────────────────────────────────────────────

    # Zerodha error substrings that are transient and safe to retry silently
    _TRANSIENT_ERRORS = (
        "being processed",      # order mid-processing by exchange
        "try later",            # exchange rate-limit
        "too many requests",    # API rate-limit
        "gateway timeout",
        "service unavailable",
        "temporarily unavailable",
    )

    def _is_transient(self, err: str) -> bool:
        low = err.lower()
        return any(t in low for t in self._TRANSIENT_ERRORS)

    async def _handle_unexpected(
        self, s: MonitoringSession, cb: Callable, exc: Exception
    ):
        s.retry_count += 1
        err = str(exc)

        # Transient network errors
        if isinstance(exc, (ConnectionError, TimeoutError, OSError)):
            await self._emit(s, cb, "EXCEPTION",
                f"Network error (attempt {s.retry_count}/{MAX_RETRIES}): {err}",
                {"error": err}, "WARNING")
            if s.retry_count <= MAX_RETRIES:
                return
            # Exceeded retries — human needed
            await self._human_alert(s, cb,
                f"Persistent network error after {MAX_RETRIES} retries: {err}",
                {"error": err, "action_needed": "Check server connectivity"})
            s.status = "HUMAN_NEEDED"
            return

        # Transient Zerodha exchange errors — skip this poll, keep monitoring
        if self._is_transient(err):
            s.retry_count = 0  # reset so one bad poll doesn't accumulate toward limit
            await self._emit(s, cb, "EXCEPTION",
                f"Transient exchange error (skipping poll): {err}",
                {"error": err}, "WARNING")
            return

        # Order not found — SL may have been manually cancelled; replace it
        if "order" in err.lower() and "not found" in err.lower():
            await self._emit(s, cb, "EXCEPTION",
                "SL order not found — replacing with new SL order.",
                {"error": err}, "WARNING")
            await self._modify_sl_order(s, cb, asyncio.get_event_loop(),
                                        s.sl_trigger, s.sl_limit)
            s.retry_count = 0
            return

        # Unknown / persistent — human needed
        await self._human_alert(s, cb,
            f"Unexpected monitoring error: {err}",
            {"error": err, "action_needed": "Review position on Zerodha and decide manually"})
        s.status = "HUMAN_NEEDED"

    async def _human_alert(
        self, s: MonitoringSession, cb: Optional[Callable],
        message: str, data: Dict
    ):
        logger.error(f"[Monitor][HUMAN_ALERT] {s.symbol}: {message}")
        self._add_commentary(
            s, "HUMAN_ALERT",
            f"{s.symbol}: ATTENTION NEEDED — {message} Please check your Zerodha app immediately.",
            f"{s.symbol}: DHYAN DO — {message} Zerodha app pe turant check karo.",
        )
        if cb:
            await self._emit(s, cb, "HUMAN_ALERT", message, data, "DANGER")

    # ── Commentary ────────────────────────────────────────────────────────────

    def _add_commentary(
        self,
        s: MonitoringSession,
        event_type: str,
        message_en: str,
        message_hi: str,
    ):
        """Append a human-readable commentary entry in the session's chosen language."""
        text = message_hi if s.commentary_language == "hinglish" else message_en
        entry = {
            "event": event_type,
            "text": text,
            "timestamp": datetime.utcnow().strftime("%H:%M:%S"),
        }
        s.commentary.insert(0, entry)
        if len(s.commentary) > 100:
            s.commentary = s.commentary[:100]

    def set_commentary_language(self, analysis_id: str, language: str) -> Dict:
        s = self._sessions.get(analysis_id)
        if s is None:
            return {"status": "error", "detail": "No monitoring session found"}
        if language in ("english", "hinglish"):
            s.commentary_language = language
        return {"status": "ok", "language": language}

    def get_commentary(self, analysis_id: str) -> Optional[List[Dict]]:
        s = self._sessions.get(analysis_id)
        return s.commentary if s else None

    # ── Utilities ──────────────────────────────────────────────────────────────

    async def _emit(
        self, s: MonitoringSession, cb: Optional[Callable],
        event_type: str, message: str, data: Dict, alert_level: str = "INFO"
    ):
        event = MonitoringEvent(
            timestamp=datetime.utcnow().isoformat(),
            event_type=event_type,
            message=message,
            data=data,
            alert_level=alert_level,
        )
        s.events.append(event)
        logger.info(f"[Monitor][{event_type}][{s.symbol}] {message}")
        if cb:
            try:
                await cb(event)
            except Exception as e:
                logger.warning(f"[Monitor] callback error: {e}")

    def _snap_tick(self, price: float) -> float:
        """Round to nearest NFO tick (0.05)."""
        return round(round(price / NFO_TICK) * NFO_TICK, 2)


options_monitoring_agent = OptionsMonitoringAgent()
