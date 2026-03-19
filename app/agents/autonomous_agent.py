"""
Autonomous Live Trading Agent
------------------------------
Phase 1 - SCANNING:  Scan market once → find all qualifying stocks → execute all positions
Phase 2 - MONITORING: Stop scanning. Monitor open positions only.
  - Continuous trailing stop-loss adjustment (every 30 s)
  - GTT fill detection (every 30 s)
  - P&L updates (every 5 s)
  - Auto squareoff at 3:10 PM IST

Stop behaviour:
  - If market is open → squareoff all open positions (MARKET order) + cancel GTTs
  - If market is closed → cancel GTTs only
  - Agent removed from memory after stop → clean slate on next start
"""
import asyncio
import os
import threading
import uuid
from datetime import datetime
from typing import Dict, IO, List, Optional
import pytz

from app.core.logging import logger
from app.services.analysis_service import AnalysisService
from app.engines.strategy_engine import strategy_engine
from app.agents.execution_agent import ExecutionAgent
from kiteconnect import KiteConnect

IST = pytz.timezone("Asia/Kolkata")


def _ist_now() -> datetime:
    return datetime.now(IST)


def _is_market_open() -> bool:
    now = _ist_now()
    if now.weekday() >= 5:  # Sat/Sun
        return False
    t = now.hour * 60 + now.minute
    return 9 * 60 + 15 <= t <= 15 * 60 + 30


def _minutes_until_squareoff() -> int:
    now = _ist_now()
    sq = now.replace(hour=15, minute=10, second=0, microsecond=0)
    return int((sq - now).total_seconds() / 60)


# ── Price cache (thread-safe, updated by KiteTicker callbacks) ────────────────

class PriceCache:
    """Thread-safe store for latest tick data from KiteTicker."""

    def __init__(self):
        self._lock = threading.Lock()
        self._cache: Dict[int, Dict] = {}          # token → tick dict
        self._symbol_to_token: Dict[str, int] = {}  # symbol → instrument_token

    def register_symbol(self, symbol: str, token: int):
        with self._lock:
            self._symbol_to_token[symbol] = token

    def remove_symbol(self, symbol: str):
        with self._lock:
            token = self._symbol_to_token.pop(symbol, None)
            if token is not None:
                self._cache.pop(token, None)

    def update(self, ticks: list):
        with self._lock:
            for tick in ticks:
                self._cache[tick["instrument_token"]] = tick

    def get_ltp(self, symbol: str) -> Optional[float]:
        with self._lock:
            token = self._symbol_to_token.get(symbol)
            if token is None:
                return None
            tick = self._cache.get(token)
            if tick is None:
                return None
            return tick.get("last_price")

    def subscribed_tokens(self) -> List[int]:
        with self._lock:
            return list(self._symbol_to_token.values())


# ── KiteTicker manager ────────────────────────────────────────────────────────

class _TickerManager:
    """
    Wraps KiteTicker WebSocket lifecycle for a single user session.

    Rules:
    - Only starts when market is open (avoids 403 Forbidden from Zerodha)
    - Auto-reconnect is DISABLED on the ticker; reconnect is managed by the
      monitor loop so it respects market hours and doesn't spam the log
    - 403 error → stops immediately, marks _forbidden=True so callers know
      not to retry until the next session
    """

    def __init__(self, api_key: str, access_token: str, price_cache: PriceCache):
        self._api_key = api_key
        self._access_token = access_token
        self._cache = price_cache
        self._ticker = None
        self._connected = False
        self._forbidden = False   # True after a 403 — don't retry same session
        self._started = False     # True once connect() has been called — Twisted reactor cannot restart
        self._subscribed: set = set()

    def start(self):
        """Connect to KiteTicker. Should only be called when market is open."""
        if self._forbidden:
            logger.warning("[Ticker] Start skipped — 403 was received, access token may lack WebSocket permissions")
            return
        if self._started:
            # Twisted reactor is a per-process singleton — once started it cannot be
            # restarted. Calling connect(threaded=True) again raises ReactorNotRestartable.
            # Fall back to REST API polling for prices instead.
            logger.debug("[Ticker] Start skipped — reactor already started (reconnect not possible in same process)")
            return

        from kiteconnect import KiteTicker  # local import to avoid top-level noise

        # reconnect=False: we manage reconnect ourselves so we can check market hours
        self._ticker = KiteTicker(self._api_key, self._access_token, reconnect=False)

        def on_ticks(ws, ticks):
            self._cache.update(ticks)

        def on_connect(ws, response):
            self._connected = True
            logger.info("[Ticker] WebSocket connected — live price streaming active")
            if self._subscribed:
                tokens = list(self._subscribed)
                ws.subscribe(tokens)
                ws.set_mode(ws.MODE_QUOTE, tokens)
                logger.info(f"[Ticker] Re-subscribed to {len(tokens)} token(s) after connect")

        def on_close(ws, code, reason):
            self._connected = False
            logger.info(f"[Ticker] WebSocket closed: {code} {reason}")

        def on_error(ws, code, reason):
            reason_str = str(reason) if reason else ""
            is_forbidden = (code == 403) or (str(code) == "1006" and "403" in reason_str)
            if is_forbidden:
                # 403 = Forbidden. This usually means market is closed or the
                # access token doesn't have WebSocket permission. Stop the ticker
                # immediately — don't let KiteConnect's internal thread retry.
                self._forbidden = True
                self._connected = False
                logger.warning(
                    "[Ticker] 403 Forbidden — WebSocket not allowed. "
                    "Will fall back to REST API polling. "
                    "(Expected outside market hours)"
                )
                try:
                    ws.stop()
                except Exception:
                    pass
            else:
                logger.warning(f"[Ticker] Error {code}: {reason}")

        self._ticker.on_ticks = on_ticks
        self._ticker.on_connect = on_connect
        self._ticker.on_close = on_close
        self._ticker.on_error = on_error

        # Runs in a background thread — non-blocking.
        # Mark _started before connect() so any re-entry attempt is blocked.
        self._started = True
        self._ticker.connect(threaded=True)

    def stop(self):
        if self._ticker:
            try:
                self._ticker.stop()
            except Exception:
                pass
        self._connected = False
        self._ticker = None

    def subscribe(self, token: int):
        self._subscribed.add(token)
        if self._ticker and self._connected:
            self._ticker.subscribe([token])
            self._ticker.set_mode(self._ticker.MODE_QUOTE, [token])

    def unsubscribe(self, token: int):
        self._subscribed.discard(token)
        if self._ticker and self._connected:
            try:
                self._ticker.unsubscribe([token])
            except Exception:
                pass

    @property
    def is_connected(self) -> bool:
        return self._connected


# ── Position state ────────────────────────────────────────────────────────────

class PositionState:
    def __init__(
        self,
        symbol: str,
        action: str,
        quantity: int,
        entry_price: float,
        stop_loss: float,
        target: float,
        gtt_id: Optional[str],
        entry_order_id: str,
        analysis_id: str,
        instrument_token: Optional[int] = None,
        atr: float = 0.0,
    ):
        self.symbol = symbol
        self.action = action
        self.quantity = quantity
        self.entry_price = entry_price
        self.stop_loss = stop_loss
        self.target = target
        self.gtt_id = gtt_id
        self.entry_order_id = entry_order_id
        self.analysis_id = analysis_id
        self.instrument_token = instrument_token
        self.atr = atr
        # Watermark: tracks highest (BUY) or lowest (SELL) price seen — for trailing SL
        self.watermark = entry_price
        self.trail_count = 0
        self.original_target = target     # preserved for reference
        self.target_adjusted = False      # True once target is revised down on reversal
        self.entered_at = _ist_now().isoformat()
        self.trail_activated = False
        self.current_pnl = 0.0
        # Multi-target (scaling-out) strategy
        self.targets: List[Dict] = []     # [{label, price, qty, hit, new_sl}]
        self.remaining_quantity: int = quantity  # decrements on each partial exit

    def to_dict(self) -> Dict:
        return {
            "symbol": self.symbol,
            "action": self.action,
            "quantity": self.quantity,
            "entry_price": self.entry_price,
            "stop_loss": self.stop_loss,
            "target": self.target,
            "original_target": self.original_target,
            "gtt_id": self.gtt_id,
            "entry_order_id": self.entry_order_id,
            "entered_at": self.entered_at,
            "trail_activated": self.trail_activated,
            "trail_count": self.trail_count,
            "target_adjusted": self.target_adjusted,
            "current_pnl": round(self.current_pnl, 2),
            "remaining_quantity": self.remaining_quantity,
            "targets": self.targets,
        }


class AgentLog:
    def __init__(self, event: str, message: str, symbol: str = None):
        self.event = event
        self.message = message
        self.symbol = symbol
        self.timestamp = _ist_now().strftime("%H:%M:%S")

    def to_dict(self) -> Dict:
        return {
            "event": self.event,
            "message": self.message,
            "symbol": self.symbol,
            "timestamp": self.timestamp,
        }


# ── Per-user agent ────────────────────────────────────────────────────────────

class UserTradingAgent:
    MAX_LOGS = 200

    def __init__(
        self,
        user_id: str,
        api_key: str,
        access_token: str,
        max_positions: int = 2,
        risk_percent: float = 1.0,
        scan_interval_minutes: int = 5,
        max_trades_per_day: int = 3,
        max_daily_loss_pct: float = 2.0,
        capital_to_use: float = 0.0,
        leverage: int = 1,
    ):
        self.user_id = user_id
        self.api_key = api_key
        self.access_token = access_token
        self.max_positions = max_positions
        self.risk_percent = risk_percent
        self.scan_interval_minutes = scan_interval_minutes
        self.max_trades_per_day = max_trades_per_day
        self.max_daily_loss_pct = max_daily_loss_pct
        self.capital_to_use = capital_to_use
        self.leverage = max(1, min(5, leverage))

        self.is_running = False
        self.status = "STOPPED"
        self.positions: Dict[str, PositionState] = {}
        self.trade_count_today = 0
        self.daily_pnl = 0.0
        self.starting_capital = 0.0
        self.daily_loss_limit_hit = False
        self.logs: List[AgentLog] = []
        self.last_scan_at: Optional[str] = None
        self.started_at: Optional[str] = None

        # Phase flag: True once we've entered positions — no more scanning
        self._scanning_done = False

        self._scan_task: Optional[asyncio.Task] = None
        self._monitor_task: Optional[asyncio.Task] = None
        self._analysis_svc = AnalysisService()
        self._exec_agent = ExecutionAgent()
        self._price_cache = PriceCache()
        self._ticker_manager: Optional[_TickerManager] = None
        self._trade_log: Optional[IO] = None   # daily trade journal file handle

    # ── Trade journal (daily .txt file) ───────────────────────────────────────

    def _init_trade_log(self):
        """Open (or append to) today's trade journal file and write session header."""
        try:
            now = _ist_now()
            date_str = now.strftime("%Y-%m-%d")
            uid_short = self.user_id[:8]

            # Use abspath to guarantee an absolute path regardless of CWD or
            # whether __file__ is relative (happens with some uvicorn setups).
            _agents_dir = os.path.dirname(os.path.abspath(__file__))
            log_dir = os.path.abspath(
                os.path.join(_agents_dir, "..", "..", "logs", "trades")
            )
            os.makedirs(log_dir, exist_ok=True)

            log_path = os.path.join(log_dir, f"trade_{uid_short}_{date_str}.txt")
            self._trade_log = open(log_path, "a", encoding="utf-8")  # default buffering

            sep = "=" * 80
            self._trade_log.write(f"\n{sep}\n")
            self._trade_log.write(f"  VANTRADE LIVE TRADING SESSION\n")
            self._trade_log.write(f"{sep}\n")
            self._trade_log.write(f"  Date          : {date_str}\n")
            self._trade_log.write(f"  User          : {self.user_id}\n")
            self._trade_log.write(f"  Started at    : {now.strftime('%H:%M:%S')} IST\n")
            self._trade_log.write(f"  Max positions : {self.max_positions}\n")
            self._trade_log.write(f"  Risk / trade  : {self.risk_percent}%\n")
            self._trade_log.write(f"  Max trades/day: {self.max_trades_per_day}\n")
            self._trade_log.write(f"  Daily loss cap: {self.max_daily_loss_pct}%\n")
            self._trade_log.write(f"  Leverage      : {self.leverage}x\n")
            self._trade_log.write(f"  Scan interval : {self.scan_interval_minutes} min\n")
            if self.capital_to_use > 0:
                self._trade_log.write(f"  Capital cap   : ₹{self.capital_to_use:,.2f}\n")
            self._trade_log.write(f"{sep}\n\n")
            self._trade_log.flush()

            logger.info(f"[Agent:{self.user_id}] Trade journal opened: {log_path}")
        except Exception as e:
            logger.error(
                f"[Agent:{self.user_id}] Could not open trade journal: {e}",
                exc_info=True,
            )
            self._trade_log = None

    def _write_trade_log(self, event: str, message: str):
        """Append one line to the daily trade journal."""
        if self._trade_log is None:
            return
        try:
            ts = _ist_now().strftime("%H:%M:%S")
            self._trade_log.write(f"[{ts}] [{event:<14}] {message}\n")
            self._trade_log.flush()
        except Exception:
            pass  # never let logging crash the agent

    def _close_trade_log(self):
        """Write session summary footer and close the journal file."""
        if self._trade_log is None:
            return
        try:
            now = _ist_now()
            sep = "=" * 80
            self._trade_log.write(f"\n{sep}\n")
            self._trade_log.write(f"  SESSION SUMMARY\n")
            self._trade_log.write(f"{sep}\n")
            self._trade_log.write(f"  Stopped at    : {now.strftime('%H:%M:%S')} IST\n")
            self._trade_log.write(f"  Trades today  : {self.trade_count_today}\n")
            self._trade_log.write(f"  Realised P&L  : ₹{self.daily_pnl:+,.2f}\n")
            open_pos = list(self.positions.keys())
            if open_pos:
                self._trade_log.write(f"  Open at stop  : {', '.join(open_pos)}\n")
            self._trade_log.write(f"{sep}\n\n")
            self._trade_log.flush()
            self._trade_log.close()
        except Exception:
            pass
        finally:
            self._trade_log = None

    # ── Logging ───────────────────────────────────────────────────────────────

    def _log(self, event: str, message: str, symbol: str = None):
        entry = AgentLog(event, message, symbol)
        self.logs.insert(0, entry)
        if len(self.logs) > self.MAX_LOGS:
            self.logs = self.logs[: self.MAX_LOGS]
        logger.info(f"[Agent:{self.user_id}][{event}] {message}")
        self._write_trade_log(event, message)

    def _get_kite(self) -> KiteConnect:
        kite = KiteConnect(api_key=self.api_key, timeout=15)
        kite.set_access_token(self.access_token)
        return kite

    # ── Lifecycle ─────────────────────────────────────────────────────────────

    async def start(self):
        if self.is_running:
            logger.warning(f"[Agent:{self.user_id}] start() called but agent is already running")
            return
        self.is_running = True
        self.status = "SCANNING"
        self.started_at = _ist_now().isoformat()
        self.trade_count_today = 0
        self.daily_pnl = 0.0
        self.daily_loss_limit_hit = False
        self._scanning_done = False  # fresh start — enable scanning

        self._init_trade_log()

        self._log(
            "STARTED",
            f"Agent started — max_positions={self.max_positions}, "
            f"risk={self.risk_percent}%, max_trades={self.max_trades_per_day}, "
            f"leverage={self.leverage}x, scan_interval={self.scan_interval_minutes}min",
        )

        # Fetch starting capital
        try:
            kite = self._get_kite()
            loop = asyncio.get_running_loop()
            margins = await loop.run_in_executor(None, kite.margins)
            equity = margins.get("equity", {})
            available = float(
                equity.get("available", {}).get("live_balance")
                or equity.get("net", 0)
            )
            self.starting_capital = (
                min(self.capital_to_use, available) if self.capital_to_use > 0 else available
            )
            self._log(
                "CAPITAL",
                f"Zerodha balance: ₹{available:,.2f} | "
                f"Using: ₹{self.starting_capital:,.2f}"
                + (f" (capped from ₹{self.capital_to_use:,.2f} setting)" if self.capital_to_use > 0 else ""),
            )
        except Exception as e:
            logger.exception(f"[Agent:{self.user_id}] Capital fetch failed")
            self._log("WARN", f"Could not fetch starting capital: {e}")

        # Prepare KiteTicker — only connect when market is actually open to
        # avoid Zerodha 403 Forbidden errors that spam the log outside hours.
        self._ticker_manager = _TickerManager(
            self.api_key, self.access_token, self._price_cache
        )
        if _is_market_open():
            try:
                self._ticker_manager.start()
                self._log("TICKER", "KiteTicker WebSocket started — real-time prices active")
            except Exception as e:
                logger.exception(f"[Agent:{self.user_id}] KiteTicker start failed")
                self._log("WARN", f"KiteTicker failed to start (will fall back to API polling): {e}")
        else:
            self._log("TICKER", "Market closed — KiteTicker will connect when market opens")

        logger.info(f"[Agent:{self.user_id}] Launching scan_task and monitor_task")
        self._scan_task = asyncio.create_task(self._scan_loop())
        self._monitor_task = asyncio.create_task(self._monitor_loop())

    async def stop(self):
        """
        Stop the agent gracefully:
        - If market is open: squareoff all positions (MARKET) + cancel GTTs
        - If market is closed: cancel GTTs only
        - Then halt scan/monitor loops and KiteTicker
        """
        if not self.is_running:
            logger.warning(f"[Agent:{self.user_id}] stop() called but agent is not running")
            return

        logger.info(f"[Agent:{self.user_id}] Stop requested — open positions: {list(self.positions.keys())}")
        self.is_running = False  # halt loops at next iteration

        if self.positions:
            pos_summary = ", ".join(
                f"{sym}({p.action} ₹{p.current_pnl:+.2f})" for sym, p in self.positions.items()
            )
            if _is_market_open():
                self.status = "SQUARING_OFF"
                self._log(
                    "SQUAREOFF",
                    f"Squaring off {len(self.positions)} position(s): {pos_summary}",
                )
                await self._force_squareoff()
            else:
                self._log(
                    "GTT_CANCEL",
                    f"Market closed — cancelling GTTs for {len(self.positions)} position(s): {pos_summary}",
                )
                await self._cancel_all_gtts()
        else:
            logger.info(f"[Agent:{self.user_id}] No open positions to close")

        self.status = "STOPPED"

        # Cancel tasks and await them so they fully terminate before we return.
        tasks_to_cancel = [
            t for t in [self._scan_task, self._monitor_task]
            if t and not t.done()
        ]
        logger.info(f"[Agent:{self.user_id}] Cancelling {len(tasks_to_cancel)} background task(s)")
        for t in tasks_to_cancel:
            t.cancel()
        if tasks_to_cancel:
            await asyncio.gather(*tasks_to_cancel, return_exceptions=True)
        logger.info(f"[Agent:{self.user_id}] All tasks cancelled")

        # Stop KiteTicker
        if self._ticker_manager:
            try:
                self._ticker_manager.stop()
                logger.info(f"[Agent:{self.user_id}] KiteTicker stopped")
            except Exception:
                pass
            self._ticker_manager = None

        self._log(
            "STOPPED",
            f"Agent stopped — total P&L today: ₹{self.daily_pnl:+.2f}, "
            f"trades: {self.trade_count_today}",
        )
        self._close_trade_log()

    # ── Scan loop ─────────────────────────────────────────────────────────────

    async def _scan_loop(self):
        """
        Scans market at configured interval until stocks are selected and entered.
        Once positions are open (_scanning_done = True), this loop becomes a no-op
        and the agent switches to pure monitoring mode.
        """
        while self.is_running:
            try:
                if not _is_market_open():
                    self._log("WAIT", "Market closed — waiting for market open (60s sleep)")
                    await asyncio.sleep(60)
                    continue

                # Phase 2: scanning complete — only monitoring
                if self._scanning_done:
                    await asyncio.sleep(60)
                    continue

                if self.daily_loss_limit_hit:
                    self._log("PAUSED", "Daily loss limit hit — no new scan until tomorrow")
                    self._scanning_done = True
                    await asyncio.sleep(300)
                    continue

                # Avoid opening-hour volatility — wait until 10:00 AM IST
                # (first 45 min of market are erratic; 10:00–11:30 AM is the prime window)
                now = _ist_now()
                mins_since_open = (now.hour * 60 + now.minute) - (9 * 60 + 15)
                if mins_since_open < 45:
                    wait_mins = 45 - mins_since_open
                    self._log(
                        "WAIT",
                        f"Opening-hour cooldown — {wait_mins} min until 10:00 AM trading window. "
                        f"Avoiding first 45 min volatility.",
                    )
                    await asyncio.sleep(60)
                    continue

                mins_left = _minutes_until_squareoff()
                if mins_left <= 20:
                    self._log(
                        "SCAN_SKIP",
                        f"Only {mins_left} min until 3:10 PM squareoff — will not open new positions",
                    )
                    self._scanning_done = True
                    await asyncio.sleep(60)
                    continue

                if self.trade_count_today >= self.max_trades_per_day:
                    self._log(
                        "SCAN_SKIP",
                        f"Max trades/day ({self.max_trades_per_day}) reached — no more entries today",
                    )
                    self._scanning_done = True
                    await asyncio.sleep(300)
                    continue

                await self._run_scan()

            except asyncio.CancelledError:
                logger.info(f"[Agent:{self.user_id}] Scan loop cancelled")
                break
            except Exception as e:
                logger.exception(f"[Agent:{self.user_id}] Scan loop unhandled error")
                self._log("ERROR", f"Scan loop error: {e}")
                await asyncio.sleep(60)

            if not self._scanning_done:
                next_scan = self.scan_interval_minutes
                self._log("WAIT", f"Next scan in {next_scan} min — sleeping")
                await asyncio.sleep(next_scan * 60)

    async def _get_nifty_trend(self) -> str:
        """
        Returns 'UP', 'DOWN', or 'NEUTRAL' based on Nifty 50 vs today's open.
        Used to ensure trades are aligned with the broader market direction.
        >+0.2% above open → UP (favour BUY trades)
        <-0.2% below open → DOWN (favour SELL/short trades)
        """
        try:
            from app.services.zerodha_service import ZerodhaService
            svc = ZerodhaService()
            svc.set_credentials(self.api_key, self.access_token)
            ohlc_data = await svc.get_ohlc(["NIFTY 50"])
            nifty = ohlc_data.get("NSE:NIFTY 50", {})
            last_price = float(nifty.get("last_price", 0))
            today_open = float(nifty.get("ohlc", {}).get("open", last_price))
            if last_price <= 0 or today_open <= 0:
                return "NEUTRAL"
            change_pct = (last_price - today_open) / today_open * 100
            if change_pct >= 0.2:
                return "UP"
            elif change_pct <= -0.2:
                return "DOWN"
            return "NEUTRAL"
        except Exception as e:
            logger.debug(f"[Agent:{self.user_id}] Nifty trend check failed: {e}")
            return "NEUTRAL"  # don't block trades if check fails

    async def _run_scan(self):
        """
        Scan market → score all signals → execute top-N positions in one pass.
        After this call completes (regardless of result), _scanning_done is set
        to True once at least one position is open, preventing further scans.
        """
        self.status = "SCANNING"
        self._log(
            "SCAN_START",
            f"Market scan started — open={len(self.positions)}/{self.max_positions}, "
            f"trades_today={self.trade_count_today}/{self.max_trades_per_day}, "
            f"mins_to_squareoff={_minutes_until_squareoff()}",
        )
        self.last_scan_at = _ist_now().isoformat()

        try:
            logger.info(f"[Agent:{self.user_id}] Calling screen_and_enrich_intraday(limit=20)")
            candidates = await self._analysis_svc.screen_and_enrich_intraday(
                limit=20,
                user_api_key=self.api_key,
                user_access_token=self.access_token,
            )
            logger.info(f"[Agent:{self.user_id}] Screener returned {len(candidates) if candidates else 0} candidates")

            if not candidates:
                self._log("SCAN_EMPTY", "Screener returned no candidates this cycle")
                return

            # Skip stocks already in an open position
            open_symbols = set(self.positions.keys())
            fresh = [c for c in candidates if c["symbol"] not in open_symbols]

            if not fresh:
                self._log(
                    "SCAN_SKIP",
                    f"All {len(candidates)} candidate(s) already in open positions: {list(open_symbols)}",
                )
                return

            # Score each candidate
            qualified = []
            for c in fresh:
                indicators = c.get("indicators", {})
                if not indicators:
                    continue
                sig = strategy_engine.generate_intraday_signal(indicators)
                logger.debug(
                    f"[Agent:{self.user_id}] {c['symbol']}: signal={sig['signal']} "
                    f"strength={sig['strength']} score={sig.get('score', 0)}"
                )
                if sig["strength"] >= 2 and sig["signal"] != "NEUTRAL":
                    qualified.append({**c, "sig": sig})

            if not qualified:
                self._log(
                    "SCAN_NONE",
                    f"Screened {len(fresh)} stocks — none reached signal strength ≥ 2 "
                    f"(best candidates had strength < 2)",
                )
                return

            # Sort best first and take up to available position slots
            qualified.sort(key=lambda x: x["sig"]["score"], reverse=True)
            slots_available = self.max_positions - len(self.positions)
            to_trade = qualified[:slots_available]

            top_summary = " | ".join(
                f"{x['symbol']}({x['sig']['signal']} str={x['sig']['strength']})"
                for x in qualified[:5]
            )
            self._log(
                "SCAN_RESULT",
                f"Found {len(qualified)} qualifying signal(s), entering {len(to_trade)} "
                f"(slots={slots_available}). Top: {top_summary}",
            )

            # Get available capital once for this scan cycle
            try:
                kite = self._get_kite()
                loop = asyncio.get_running_loop()
                margins = await loop.run_in_executor(None, kite.margins)
                equity = margins.get("equity", {})
                available = float(
                    equity.get("available", {}).get("live_balance")
                    or equity.get("net", 0)
                )
                capital = (
                    min(available, self.capital_to_use)
                    if self.capital_to_use > 0
                    else available
                )
                logger.info(
                    f"[Agent:{self.user_id}] Capital check — available: ₹{available:,.2f}, "
                    f"using: ₹{capital:,.2f}, effective (×{self.leverage}): ₹{capital * self.leverage:,.2f}"
                )
            except Exception as e:
                logger.warning(f"[Agent:{self.user_id}] Capital fetch failed, using starting_capital: {e}")
                capital = self.starting_capital

            if capital < 1000:
                self._log("SKIP", f"Insufficient capital ₹{capital:.0f} (min ₹1,000) — skipping all entries")
                return

            # Fetch Nifty 50 trend once for this scan cycle — trade only with the market
            nifty_trend = await self._get_nifty_trend()
            self._log(
                "MARKET",
                f"Nifty 50 trend: {nifty_trend} — "
                + ("favouring BUY signals" if nifty_trend == "UP"
                   else "favouring SELL/short signals" if nifty_trend == "DOWN"
                   else "NEUTRAL — accepting both directions"),
            )

            # Execute each qualifying stock
            for best in to_trade:
                if not self.is_running:
                    logger.info(f"[Agent:{self.user_id}] Agent stopped mid-scan — aborting remaining entries")
                    break
                if self.trade_count_today >= self.max_trades_per_day:
                    self._log("SCAN_SKIP", f"Max trades/day ({self.max_trades_per_day}) reached during entry loop")
                    break

                symbol = best["symbol"]
                sig = best["sig"]
                ltp = float(best["last_price"])

                # Position sizing: ATR-based SL/target, risk% of capital
                indicators = best.get("indicators", {})
                atr = float(indicators.get("atr_14", ltp * 0.01) or ltp * 0.01)
                action = sig["signal"]  # BUY or SELL

                if action == "BUY":
                    stop_loss = round(ltp - (1.5 * atr), 2)
                    t1 = round(ltp + (1.5 * atr), 2)      # 1:1 R:R — first partial exit
                    target = round(ltp + (3.0 * atr), 2)  # 2:1 R:R — T2 / runner level
                    if not (stop_loss < ltp < t1 < target):
                        stop_loss = round(ltp * 0.985, 2)
                        t1 = round(ltp * 1.015, 2)
                        target = round(ltp * 1.03, 2)
                        logger.debug(f"[Agent:{self.user_id}] {symbol}: ATR SL/target invalid, using % fallback")
                else:  # SELL (short)
                    stop_loss = round(ltp + (1.5 * atr), 2)
                    t1 = round(ltp - (1.5 * atr), 2)      # 1:1 R:R
                    target = round(ltp - (3.0 * atr), 2)  # 2:1 R:R — T2 / runner level
                    if not (target < t1 < ltp < stop_loss):
                        stop_loss = round(ltp * 1.015, 2)
                        t1 = round(ltp * 0.985, 2)
                        target = round(ltp * 0.97, 2)
                        logger.debug(f"[Agent:{self.user_id}] {symbol}: ATR SL/target invalid, using % fallback")

                # ── Multi-target quantity split (scaling-out) ──────────────
                # T1 (1:1 R:R): exit 50% → move SL to breakeven
                # T2 (2:1 R:R): exit 25% → move SL to T1
                # Runner: remaining 25% trails with SL until squareoff
                t1_qty = max(1, quantity // 2)
                t2_qty = max(1, (quantity - t1_qty) // 2) if (quantity - t1_qty) >= 2 else 0

                # ── Principle: Follow the trend ───────────────────────────
                # Skip trade if it goes against the Nifty 50 direction.
                # NEUTRAL trend allows both BUY and SELL.
                if nifty_trend == "UP" and action == "SELL":
                    self._log(
                        "SKIP",
                        f"{symbol}: Skipping SHORT — Nifty is trending UP (trade with market, not against it)",
                        symbol=symbol,
                    )
                    continue
                if nifty_trend == "DOWN" and action == "BUY":
                    self._log(
                        "SKIP",
                        f"{symbol}: Skipping BUY — Nifty is trending DOWN (trade with market, not against it)",
                        symbol=symbol,
                    )
                    continue

                # ── Principle: Minimum 1:2 Risk-Reward ────────────────────
                # T2 (full move) must be at least 2:1 vs risk
                risk = abs(ltp - stop_loss)
                reward_t2 = abs(target - ltp)
                rr_ratio = reward_t2 / risk if risk > 0 else 0
                if rr_ratio < 2.0:
                    self._log(
                        "SKIP",
                        f"{symbol}: R:R {rr_ratio:.1f}:1 below minimum 1:2 — skipping",
                        symbol=symbol,
                    )
                    continue

                risk_per_share = abs(ltp - stop_loss)
                effective_capital = capital * self.leverage
                max_risk = effective_capital * (self.risk_percent / 100)
                quantity = max(1, int(max_risk / risk_per_share)) if risk_per_share > 0 else 1

                # Cap: no more than 10% of capital per trade
                max_by_capital = int((capital * 0.10) / ltp) if ltp > 0 else 1
                quantity = min(quantity, max(1, max_by_capital))

                runner_qty = quantity - t1_qty - t2_qty
                self._log(
                    "SIGNAL",
                    f"{symbol}: {action} | strength={sig['strength']} score={sig.get('score',0)} | "
                    f"LTP=₹{ltp:.2f} ATR=₹{atr:.2f} | "
                    f"SL=₹{stop_loss:.2f} T1=₹{t1:.2f}({t1_qty}sh) "
                    f"T2=₹{target:.2f}({t2_qty}sh) Runner={runner_qty}sh | "
                    f"Risk=₹{max_risk:.0f} RiskPerShare=₹{risk_per_share:.2f}",
                    symbol=symbol,
                )

                # Execute trade — SL-only GTT (targets managed by agent)
                analysis_id = str(uuid.uuid4())
                logger.info(
                    f"[Agent:{self.user_id}] Placing order — {symbol} {action} "
                    f"qty={quantity} entry=₹{ltp:.2f} sl=₹{stop_loss:.2f} "
                    f"t1=₹{t1:.2f} t2=₹{target:.2f}"
                )
                try:
                    result = await self._exec_agent.execute_trade_with_gtt(
                        stock_symbol=symbol,
                        quantity=quantity,
                        entry_price=ltp,
                        stop_loss=stop_loss,
                        target=target,
                        analysis_id=analysis_id,
                        access_token=self.access_token,
                        api_key=self.api_key,
                        hold_duration_days=0,
                        action=action,
                        sl_only=True,   # T1/T2 exits are agent-managed via MARKET orders
                    )
                except Exception as e:
                    logger.exception(f"[Agent:{self.user_id}] {symbol}: execute_trade_with_gtt raised")
                    self._log("TRADE_FAIL", f"{symbol}: Execution error — {e}", symbol=symbol)
                    continue

                if result["status"] == "COMPLETED":
                    pos = PositionState(
                        symbol=symbol,
                        action=action,
                        quantity=quantity,
                        entry_price=ltp,
                        stop_loss=stop_loss,
                        target=target,
                        gtt_id=result.get("gtt_order_id"),
                        entry_order_id=result.get("entry_order_id", ""),
                        analysis_id=analysis_id,
                        atr=atr,
                    )
                    # Set up multi-target (scaling-out) plan
                    pos.remaining_quantity = quantity
                    if action == "BUY":
                        pos.targets = [
                            {"label": "T1", "price": t1, "qty": t1_qty, "hit": False, "new_sl": ltp},  # SL → breakeven
                            *([{"label": "T2", "price": target, "qty": t2_qty, "hit": False, "new_sl": t1}] if t2_qty > 0 else []),
                        ]
                    else:  # SELL short
                        pos.targets = [
                            {"label": "T1", "price": t1, "qty": t1_qty, "hit": False, "new_sl": ltp},
                            *([{"label": "T2", "price": target, "qty": t2_qty, "hit": False, "new_sl": t1}] if t2_qty > 0 else []),
                        ]
                    self.positions[symbol] = pos
                    self.trade_count_today += 1
                    target_plan = f"T1=₹{t1:.2f}({t1_qty}sh)"
                    if t2_qty > 0:
                        target_plan += f" T2=₹{target:.2f}({t2_qty}sh)"
                    target_plan += f" Runner={runner_qty}sh"
                    self._log(
                        "TRADE_OPEN",
                        f"{symbol}: ✓ Order placed — entry_order={result.get('entry_order_id')} "
                        f"GTT={result.get('gtt_order_id')} | "
                        f"SL=₹{stop_loss:.2f} | {target_plan}",
                        symbol=symbol,
                    )

                    # Subscribe to KiteTicker for real-time price streaming
                    await self._subscribe_ticker(symbol)
                else:
                    self._log(
                        "TRADE_FAIL",
                        f"{symbol}: ✗ Trade failed — {result.get('error', result['status'])}",
                        symbol=symbol,
                    )

        except Exception as e:
            logger.exception(f"[Agent:{self.user_id}] _run_scan unhandled error")
            self._log("ERROR", f"Scan error: {e}")
        finally:
            # Switch to monitoring mode once we have open positions
            if self.positions:
                self._scanning_done = True
                pos_list = ", ".join(
                    f"{sym}({p.action} qty={p.quantity} @₹{p.entry_price:.2f})"
                    for sym, p in self.positions.items()
                )
                self._log(
                    "SCAN_DONE",
                    f"Scanning complete — {len(self.positions)} position(s): {pos_list}. Now monitoring only.",
                )
            else:
                self._log("SCAN_DONE", "Scan complete — no positions entered this cycle")
            self.status = "MONITORING"

    async def _execute_partial_exit(
        self,
        symbol: str,
        pos: "PositionState",
        target_info: Dict,
        ltp: float,
        kite,
        loop,
    ):
        """
        Exit a portion of the position at a target level:
          1. Place MARKET order for target_info['qty'] shares
          2. Cancel existing SL GTT
          3. Place new single-leg SL GTT for remaining shares at new_sl
          4. Update PositionState
        """
        exit_qty = target_info["qty"]
        close_txn = "SELL" if pos.action == "BUY" else "BUY"

        # Place MARKET exit order for the partial quantity
        try:
            order_id = await loop.run_in_executor(
                None,
                lambda: kite.place_order(
                    variety="regular",
                    exchange="NSE",
                    tradingsymbol=symbol,
                    transaction_type=close_txn,
                    quantity=exit_qty,
                    product="MIS",
                    order_type="MARKET",
                ),
            )
        except Exception as e:
            self._log("ERROR", f"{symbol}: Partial exit order failed: {e}", symbol=symbol)
            return

        # Mark target hit and update remaining quantity
        target_info["hit"] = True
        pos.remaining_quantity -= exit_qty

        partial_pnl = (
            (ltp - pos.entry_price) * exit_qty
            if pos.action == "BUY"
            else (pos.entry_price - ltp) * exit_qty
        )
        self.daily_pnl += partial_pnl

        self._log(
            "TARGET_HIT",
            f"{symbol}: {target_info['label']} hit ₹{target_info['price']:.2f} — "
            f"Exited {exit_qty} shares @ MARKET | "
            f"Partial P&L=₹{partial_pnl:+.2f} | "
            f"Remaining={pos.remaining_quantity} shares | order_id={order_id}",
            symbol=symbol,
        )

        # If fully closed, clean up and return
        if pos.remaining_quantity <= 0:
            if pos.gtt_id:
                try:
                    gtt_id = pos.gtt_id
                    await loop.run_in_executor(None, lambda: kite.delete_gtt(gtt_id))
                except Exception:
                    pass
            if pos.instrument_token and self._ticker_manager:
                self._ticker_manager.unsubscribe(pos.instrument_token)
            self._price_cache.remove_symbol(symbol)
            self.positions.pop(symbol, None)
            self._log("POSITION_CLOSED", f"{symbol}: All targets hit — position fully closed", symbol=symbol)
            return

        # Move SL to new level (breakeven after T1, T1 price after T2)
        new_sl = target_info["new_sl"]
        pos.stop_loss = new_sl

        # Cancel old SL GTT and replace with new one for remaining quantity
        if pos.gtt_id:
            try:
                gtt_id = pos.gtt_id
                await loop.run_in_executor(None, lambda: kite.delete_gtt(gtt_id))
                pos.gtt_id = None
            except Exception:
                pass

        is_short = pos.action == "SELL"
        sl_orders = [
            {
                "transaction_type": "BUY" if is_short else "SELL",
                "quantity": pos.remaining_quantity,
                "order_type": "LIMIT",
                "product": "MIS",
                "price": new_sl,
            }
        ]
        try:
            new_gtt_id = await loop.run_in_executor(
                None,
                lambda: kite.place_gtt(
                    trigger_type="single",
                    tradingsymbol=symbol,
                    exchange="NSE",
                    trigger_values=[new_sl],
                    last_price=ltp,
                    orders=sl_orders,
                ),
            )
            pos.gtt_id = new_gtt_id
            self._log(
                "GTT_UPDATED",
                f"{symbol}: SL moved to ₹{new_sl:.2f} "
                f"({'breakeven' if target_info['label'] == 'T1' else 'T1-lock'}) | "
                f"New GTT {new_gtt_id} for {pos.remaining_quantity} shares",
                symbol=symbol,
            )
        except Exception as e:
            self._log("WARN", f"{symbol}: Could not place new SL GTT after partial exit: {e}", symbol=symbol)

    async def _check_targets(self, pos: "PositionState", symbol: str, ltp: float, kite, loop):
        """
        Check if current price has reached any pre-defined target level.
        Processes one target per call (lowest/nearest first) to avoid
        chain-reacting through multiple targets in a single 5-second tick.
        """
        for target_info in pos.targets:
            if target_info["hit"]:
                continue
            price_hit = (
                (pos.action == "BUY" and ltp >= target_info["price"]) or
                (pos.action == "SELL" and ltp <= target_info["price"])
            )
            if price_hit:
                await self._execute_partial_exit(symbol, pos, target_info, ltp, kite, loop)
                break  # one target per cycle

    async def _subscribe_ticker(self, symbol: str):
        """Fetch instrument token for symbol and subscribe to KiteTicker."""
        if not self._ticker_manager:
            return
        try:
            from app.services.zerodha_service import ZerodhaService
            svc = ZerodhaService()
            svc.set_credentials(self.api_key, self.access_token)
            token = None

            # Primary: kite.ltp() — fast, returns instrument_token + last_price
            try:
                ltp_data = await svc.get_ltp([symbol])
                token = ltp_data.get(f"NSE:{symbol}", {}).get("instrument_token")
            except Exception:
                pass

            # Fallback: kite.positions() also returns instrument_token for open positions
            if not token:
                try:
                    kite = self._get_kite()
                    loop = asyncio.get_running_loop()
                    pos_data = await loop.run_in_executor(None, kite.positions)
                    all_pos = pos_data.get("day", []) + pos_data.get("net", [])
                    for p in all_pos:
                        if p.get("tradingsymbol") == symbol and p.get("exchange") == "NSE":
                            token = p.get("instrument_token")
                            break
                except Exception:
                    pass

            if token:
                pos = self.positions.get(symbol)
                if pos:
                    pos.instrument_token = token
                self._price_cache.register_symbol(symbol, token)
                self._ticker_manager.subscribe(token)
                self._log(
                    "TICKER_SUB",
                    f"{symbol}: Subscribed to live price feed (token: {token})",
                    symbol=symbol,
                )
            else:
                self._log(
                    "WARN",
                    f"{symbol}: Could not resolve instrument token — will use positions API for prices",
                    symbol=symbol,
                )
        except Exception as e:
            self._log("WARN", f"{symbol}: Ticker subscription failed (will use API): {e}", symbol=symbol)

    # ── Monitor loop ──────────────────────────────────────────────────────────

    async def _monitor_loop(self):
        """
        Runs every 5 seconds.
        - Price updates: reads from KiteTicker cache (no API call), falls back to kite.quote() on cache miss
        - GTT fill detection + trailing SL: API call every 30 seconds (every 6th iteration)
        """
        gtt_check_counter = 0
        while self.is_running:
            try:
                await asyncio.sleep(5)

                # Lazily connect KiteTicker once market opens (if not already connected
                # and no 403 was received)
                if (
                    self._ticker_manager
                    and not self._ticker_manager.is_connected
                    and not self._ticker_manager._forbidden
                    and not self._ticker_manager._started
                    and _is_market_open()
                ):
                    logger.info(f"[Agent:{self.user_id}] Market opened — connecting KiteTicker")
                    try:
                        self._ticker_manager.start()
                        # Re-subscribe any existing positions
                        for sym, pos in self.positions.items():
                            if pos.instrument_token:
                                self._ticker_manager.subscribe(pos.instrument_token)
                    except Exception as e:
                        logger.warning(f"[Agent:{self.user_id}] KiteTicker lazy-start failed: {e}")

                if not self.positions or not _is_market_open():
                    continue

                mins = _minutes_until_squareoff()
                if mins <= 2:
                    pos_list = ", ".join(self.positions.keys())
                    self._log(
                        "SQUAREOFF",
                        f"3:10 PM auto-squareoff — closing {len(self.positions)} position(s): {pos_list}",
                    )
                    await self._force_squareoff()
                    continue

                gtt_check_counter += 1
                check_gtts = (gtt_check_counter % 6 == 0)  # every ~30 seconds
                await self._monitor_positions(check_gtts=check_gtts)

            except asyncio.CancelledError:
                logger.info(f"[Agent:{self.user_id}] Monitor loop cancelled")
                break
            except Exception as e:
                logger.exception(f"[Agent:{self.user_id}] Monitor loop unhandled error")
                self._log("ERROR", f"Monitor loop error: {e}")

    async def _monitor_positions(self, check_gtts: bool = False):
        """
        Check live prices → update P&L → trail SL continuously → detect GTT fills.
        Trailing SL and GTT operations only happen when check_gtts=True (every 30s)
        to avoid hammering the Zerodha API.
        """
        symbols = list(self.positions.keys())
        if not symbols:
            return

        try:
            # Step 1: Get prices — prefer KiteTicker cache, fall back to kite.quote()
            prices: Dict[str, float] = {}
            cache_miss_symbols = []

            for symbol in symbols:
                ltp = self._price_cache.get_ltp(symbol)
                if ltp is not None:
                    prices[symbol] = ltp
                else:
                    cache_miss_symbols.append(symbol)

            # Fetch cache misses via API
            if cache_miss_symbols:
                kite = self._get_kite()
                loop = asyncio.get_running_loop()

                # Attempt 1: kite.quote() — requires market data plan
                quote_ok = False
                try:
                    quotes = await loop.run_in_executor(
                        None, lambda: kite.quote([f"NSE:{s}" for s in cache_miss_symbols])
                    )
                    for symbol in cache_miss_symbols:
                        ltp = quotes.get(f"NSE:{symbol}", {}).get("last_price")
                        if ltp is not None:
                            prices[symbol] = float(ltp)
                    quote_ok = True
                    logger.debug(
                        f"[Agent:{self.user_id}] API price fetch OK — "
                        + ", ".join(f"{s}=₹{prices.get(s, 'N/A')}" for s in cache_miss_symbols)
                    )
                except Exception as e:
                    logger.debug(f"[Agent:{self.user_id}] kite.quote() unavailable ({e}) — trying positions fallback")

                # Attempt 2: kite.positions() — available on all plans, returns last_price
                if not quote_ok:
                    still_missing = [s for s in cache_miss_symbols if s not in prices]
                    if still_missing:
                        try:
                            pos_data = await loop.run_in_executor(None, kite.positions)
                            all_pos = pos_data.get("day", []) + pos_data.get("net", [])
                            pos_map = {
                                p["tradingsymbol"]: p.get("last_price")
                                for p in all_pos
                                if p.get("exchange") == "NSE" and p.get("last_price")
                            }
                            for symbol in still_missing:
                                if symbol in pos_map:
                                    prices[symbol] = float(pos_map[symbol])
                            logger.debug(
                                f"[Agent:{self.user_id}] Positions price fetch — "
                                + ", ".join(f"{s}=₹{prices.get(s, 'N/A')}" for s in still_missing)
                            )
                        except Exception as e2:
                            logger.warning(f"[Agent:{self.user_id}] Positions price fallback failed: {e2}")
                            self._log("WARN", f"Price fetch failed (quote + positions both failed): {e2}")

            # Step 2: Fetch active GTT IDs (only every 30s to limit API calls)
            active_gtt_ids: set = set()
            if check_gtts:
                try:
                    kite = self._get_kite()
                    loop = asyncio.get_running_loop()
                    gtts = await loop.run_in_executor(None, kite.get_gtts)
                    active_gtt_ids = {
                        str(g.get("id"))
                        for g in gtts
                        if g.get("status", "").lower() in ("active",)
                    }
                    logger.info(
                        f"[Agent:{self.user_id}] GTT poll — {len(active_gtt_ids)} active GTT(s): {active_gtt_ids}"
                    )
                except Exception as e:
                    logger.warning(f"[Agent:{self.user_id}] GTT fetch failed: {e}")

            # ── Multi-target check (every 5 s) ────────────────────────────
            # Must run before P&L update so remaining_quantity is already correct.
            if prices:
                kite_for_targets = self._get_kite()
                loop_for_targets = asyncio.get_running_loop()
                for symbol, pos in list(self.positions.items()):
                    if symbol not in self.positions:  # may have been removed above
                        continue
                    ltp_t = prices.get(symbol)
                    if ltp_t and pos.targets:
                        await self._check_targets(pos, symbol, ltp_t, kite_for_targets, loop_for_targets)

            filled_symbols = []

            for symbol, pos in list(self.positions.items()):
                ltp = prices.get(symbol, pos.entry_price)

                # ── P&L update (use remaining_quantity after partial exits) ──
                if pos.action == "BUY":
                    pos.current_pnl = (ltp - pos.entry_price) * pos.remaining_quantity
                else:
                    pos.current_pnl = (pos.entry_price - ltp) * pos.remaining_quantity

                # Log position update at reduced frequency (every 30s)
                if check_gtts:
                    move_done = (ltp - pos.entry_price) if pos.action == "BUY" else (pos.entry_price - ltp)
                    move_total = (pos.target - pos.entry_price) if pos.action == "BUY" else (pos.entry_price - pos.target)
                    progress = (move_done / move_total * 100) if move_total > 0 else 0
                    self._log(
                        "POS_UPDATE",
                        f"{symbol}: LTP=₹{ltp:.2f} entry=₹{pos.entry_price:.2f} "
                        f"P&L=₹{pos.current_pnl:+.2f} ({progress:.0f}% to TGT) "
                        f"SL=₹{pos.stop_loss:.2f} TGT=₹{pos.target:.2f}"
                        + (f" [trail×{pos.trail_count}]" if pos.trail_activated else ""),
                        symbol=symbol,
                    )

                # ── Continuous Trailing Stop-Loss (every 30s only) ────────
                # Only trail when price has moved favourably by at least 1 ATR.
                # New SL trails 1.5 ATR behind the best price seen (watermark).
                if check_gtts and pos.atr > 0:
                    if pos.action == "BUY":
                        # Update high watermark
                        if ltp > pos.watermark:
                            pos.watermark = ltp
                        profit_from_peak = pos.watermark - pos.entry_price
                        if profit_from_peak >= pos.atr:
                            new_sl = round(pos.watermark - 1.5 * pos.atr, 2)
                            if new_sl > pos.stop_loss + 0.05:  # meaningful improvement
                                old_sl = pos.stop_loss
                                pos.stop_loss = new_sl
                                pos.trail_activated = True
                                pos.trail_count += 1
                                await self._update_gtt_exits(pos, new_sl, pos.target, ltp, reason="trail SL")
                                self._log(
                                    "TRAIL_SL",
                                    f"{symbol}: SL trailed ₹{old_sl:.2f} → ₹{new_sl:.2f} "
                                    f"(peak: ₹{pos.watermark:.2f}, trail #{pos.trail_count})",
                                    symbol=symbol,
                                )
                    else:  # SELL (short)
                        # Update low watermark
                        if ltp < pos.watermark:
                            pos.watermark = ltp
                        profit_from_trough = pos.entry_price - pos.watermark
                        if profit_from_trough >= pos.atr:
                            new_sl = round(pos.watermark + 1.5 * pos.atr, 2)
                            if new_sl < pos.stop_loss - 0.05:  # meaningful improvement (lower = tighter)
                                old_sl = pos.stop_loss
                                pos.stop_loss = new_sl
                                pos.trail_activated = True
                                pos.trail_count += 1
                                await self._update_gtt_exits(pos, new_sl, pos.target, ltp, reason="trail SL")
                                self._log(
                                    "TRAIL_SL",
                                    f"{symbol}: SL trailed ₹{old_sl:.2f} → ₹{new_sl:.2f} "
                                    f"(trough: ₹{pos.watermark:.2f}, trail #{pos.trail_count})",
                                    symbol=symbol,
                                )

                # ── Dynamic Target Adjustment on Trend Reversal (every 30s) ──
                # Skipped for multi-target positions — exit levels are fixed (T1/T2/runner).
                # When a position was moving favourably but price has since reversed
                # by ≥ 0.5 ATR from the watermark (and we're still in profit), lower
                # the target so the GTT fires sooner and locks in the remaining gain.
                # Only done once per position to avoid GTT-churn.
                if check_gtts and pos.atr > 0 and not pos.target_adjusted and not pos.targets:
                    if pos.action == "BUY":
                        reversal = pos.watermark - ltp  # how far price has dropped from peak
                        in_profit = ltp > pos.entry_price
                        if reversal >= 0.5 * pos.atr and in_profit:
                            # Set new target just above current price (+0.3 ATR) so GTT fires quickly
                            new_target = round(ltp + 0.3 * pos.atr, 2)
                            # Only lower — and must still be profitable (above entry)
                            if new_target < pos.target and new_target > pos.entry_price:
                                old_target = pos.target
                                pos.target = new_target
                                pos.target_adjusted = True
                                await self._update_gtt_exits(pos, pos.stop_loss, new_target, ltp, reason="target revision")
                                self._log(
                                    "TARGET_ADJ",
                                    f"{symbol}: Target revised ₹{old_target:.2f} → ₹{new_target:.2f} "
                                    f"(bearish reversal — price dropped ₹{reversal:.2f} from peak ₹{pos.watermark:.2f})",
                                    symbol=symbol,
                                )
                    else:  # SELL (short)
                        reversal = ltp - pos.watermark  # how far price has risen from trough
                        in_profit = ltp < pos.entry_price
                        if reversal >= 0.5 * pos.atr and in_profit:
                            # Set new target just below current price (−0.3 ATR)
                            new_target = round(ltp - 0.3 * pos.atr, 2)
                            # Only raise (closer to entry) — must still be profitable (below entry)
                            if new_target > pos.target and new_target < pos.entry_price:
                                old_target = pos.target
                                pos.target = new_target
                                pos.target_adjusted = True
                                await self._update_gtt_exits(pos, pos.stop_loss, new_target, ltp, reason="target revision")
                                self._log(
                                    "TARGET_ADJ",
                                    f"{symbol}: Target revised ₹{old_target:.2f} → ₹{new_target:.2f} "
                                    f"(bullish reversal on short — price rose ₹{reversal:.2f} from trough ₹{pos.watermark:.2f})",
                                    symbol=symbol,
                                )

                # ── GTT fill detection (only when we fetched GTTs this iteration) ──
                if check_gtts and pos.gtt_id and str(pos.gtt_id) not in active_gtt_ids:
                    self._log(
                        "POSITION_CLOSED",
                        f"{symbol}: GTT {pos.gtt_id} triggered — position closed | "
                        f"P&L ≈ ₹{pos.current_pnl:+.2f} | "
                        f"entry=₹{pos.entry_price:.2f} exit≈₹{ltp:.2f}",
                        symbol=symbol,
                    )
                    self.daily_pnl += pos.current_pnl
                    logger.info(
                        f"[Agent:{self.user_id}] {symbol} closed — "
                        f"P&L=₹{pos.current_pnl:+.2f}, daily_pnl=₹{self.daily_pnl:+.2f}"
                    )
                    filled_symbols.append(symbol)
                    continue

                # ── Check daily loss limit ────────────────────────────────
                if self.starting_capital > 0:
                    total_unrealised = sum(p.current_pnl for p in self.positions.values())
                    loss_pct = abs(min(self.daily_pnl + total_unrealised, 0)) / self.starting_capital * 100
                    if loss_pct >= self.max_daily_loss_pct and not self.daily_loss_limit_hit:
                        self.daily_loss_limit_hit = True
                        self._log(
                            "DAILY_LIMIT",
                            f"Daily loss limit {self.max_daily_loss_pct}% hit — no more new trades today",
                        )

            # Clean up closed positions and unsubscribe from ticker
            for sym in filled_symbols:
                pos = self.positions.pop(sym, None)
                if pos and pos.instrument_token and self._ticker_manager:
                    self._ticker_manager.unsubscribe(pos.instrument_token)
                self._price_cache.remove_symbol(sym)

        except Exception as e:
            self._log("ERROR", f"Monitor positions error: {e}")

    # ── Update exits: cancel GTT + re-issue with new SL and/or target ────────

    async def _update_gtt_exits(
        self,
        pos: PositionState,
        new_sl: float,
        new_target: float,
        ltp: float,
        reason: str = "",
    ):
        """Cancel the existing GTT and place a new one with updated SL and/or target."""
        try:
            kite = self._get_kite()
            loop = asyncio.get_running_loop()

            if pos.gtt_id:
                try:
                    gtt_id = pos.gtt_id
                    await loop.run_in_executor(None, lambda: kite.delete_gtt(gtt_id))
                    self._log("GTT_CANCEL", f"{pos.symbol}: GTT {pos.gtt_id} cancelled ({reason})", symbol=pos.symbol)
                except Exception as e:
                    self._log("WARN", f"{pos.symbol}: Could not cancel GTT: {e}", symbol=pos.symbol)

            is_short = pos.action == "SELL"
            qty = pos.remaining_quantity  # always use remaining (partial exits may have reduced this)

            if pos.targets:
                # Multi-target mode: single-leg SL-only GTT (targets managed by agent)
                sl_orders = [
                    {
                        "transaction_type": "BUY" if is_short else "SELL",
                        "quantity": qty,
                        "order_type": "LIMIT",
                        "product": "MIS",
                        "price": new_sl,
                    }
                ]
                new_gtt_id = await loop.run_in_executor(
                    None,
                    lambda: kite.place_gtt(
                        trigger_type="single",
                        tradingsymbol=pos.symbol,
                        exchange="NSE",
                        trigger_values=[new_sl],
                        last_price=ltp,
                        orders=sl_orders,
                    ),
                )
                self._log(
                    "GTT_UPDATED",
                    f"{pos.symbol}: New SL GTT {new_gtt_id} | SL ₹{new_sl:.2f} | {qty} shares",
                    symbol=pos.symbol,
                )
            else:
                # Legacy single-target mode: two-leg GTT with SL + target
                if is_short:
                    trigger_values = sorted([new_target, new_sl])
                    orders = [
                        {"transaction_type": "BUY", "quantity": qty, "order_type": "LIMIT", "product": "MIS", "price": new_target},
                        {"transaction_type": "BUY", "quantity": qty, "order_type": "LIMIT", "product": "MIS", "price": new_sl},
                    ]
                else:
                    trigger_values = sorted([new_sl, new_target])
                    orders = [
                        {"transaction_type": "SELL", "quantity": qty, "order_type": "LIMIT", "product": "MIS", "price": new_sl},
                        {"transaction_type": "SELL", "quantity": qty, "order_type": "LIMIT", "product": "MIS", "price": new_target},
                    ]
                new_gtt_id = await loop.run_in_executor(
                    None,
                    lambda: kite.place_gtt(
                        trigger_type="two-leg",
                        tradingsymbol=pos.symbol,
                        exchange="NSE",
                        trigger_values=trigger_values,
                        last_price=ltp,
                        orders=orders,
                    ),
                )
                self._log(
                    "GTT_UPDATED",
                    f"{pos.symbol}: New GTT {new_gtt_id} | SL ₹{new_sl:.2f} | Target ₹{new_target:.2f}",
                    symbol=pos.symbol,
                )

            pos.gtt_id = new_gtt_id

        except Exception as e:
            self._log("ERROR", f"{pos.symbol}: GTT update failed: {e}", symbol=pos.symbol)

    # ── Cancel all GTTs (no position close — used when market is closed) ──────

    async def _cancel_all_gtts(self):
        """Cancel all active GTTs without closing positions. Used on off-hours stop."""
        if not self.positions:
            return
        kite = self._get_kite()
        loop = asyncio.get_running_loop()
        for symbol, pos in list(self.positions.items()):
            if pos.gtt_id:
                try:
                    gtt_id = pos.gtt_id
                    await loop.run_in_executor(None, lambda: kite.delete_gtt(gtt_id))
                    pos.gtt_id = None
                    self._log("GTT_CANCEL", f"{symbol}: GTT cancelled on agent stop", symbol=symbol)
                except Exception as e:
                    self._log("WARN", f"{symbol}: GTT cancel failed: {e}", symbol=symbol)

    # ── Force squareoff at 3:10 PM or on manual stop ─────────────────────────

    async def _force_squareoff(self):
        self.status = "SQUARING_OFF"
        if not self.positions:
            self.status = "MONITORING"
            return

        kite = self._get_kite()
        loop = asyncio.get_running_loop()

        for symbol, pos in list(self.positions.items()):
            try:
                # Cancel GTT first to avoid double-fill
                if pos.gtt_id:
                    try:
                        gtt_id = pos.gtt_id
                        await loop.run_in_executor(None, lambda: kite.delete_gtt(gtt_id))
                        self._log("GTT_CANCEL", f"{symbol}: GTT cancelled before squareoff", symbol=symbol)
                    except Exception:
                        pass

                # Close remaining position at market
                close_txn = "SELL" if pos.action == "BUY" else "BUY"
                qty = pos.remaining_quantity  # partial exits may have already reduced this
                logger.info(
                    f"[Agent:{self.user_id}] Placing squareoff — {symbol} {close_txn} {qty} MIS MARKET"
                )
                order_id = await loop.run_in_executor(
                    None,
                    lambda: kite.place_order(
                        variety="regular",
                        exchange="NSE",
                        tradingsymbol=symbol,
                        transaction_type=close_txn,
                        quantity=qty,
                        product="MIS",
                        order_type="MARKET",
                    ),
                )
                self._log(
                    "SQUAREOFF",
                    f"{symbol}: ✓ Squareoff placed — {close_txn} {qty} MIS MARKET | "
                    f"order_id={order_id} | P&L≈₹{pos.current_pnl:+.2f}",
                    symbol=symbol,
                )
                self.daily_pnl += pos.current_pnl

                # Unsubscribe from ticker
                if pos.instrument_token and self._ticker_manager:
                    self._ticker_manager.unsubscribe(pos.instrument_token)
                self._price_cache.remove_symbol(symbol)
                self.positions.pop(symbol, None)

            except Exception as e:
                logger.exception(f"[Agent:{self.user_id}] {symbol}: Squareoff raised exception")
                self._log("ERROR", f"{symbol}: Squareoff failed — {e}", symbol=symbol)

        self.status = "MONITORING"

    # ── Status ────────────────────────────────────────────────────────────────

    def get_status(self) -> Dict:
        return {
            "user_id": self.user_id,
            "is_running": self.is_running,
            "status": self.status,
            "started_at": self.started_at,
            "last_scan_at": self.last_scan_at,
            "scanning_done": self._scanning_done,
            "ticker_connected": self._ticker_manager.is_connected if self._ticker_manager else False,
            "open_positions": [p.to_dict() for p in self.positions.values()],
            "trade_count_today": self.trade_count_today,
            "daily_pnl": round(self.daily_pnl, 2),
            "daily_loss_limit_hit": self.daily_loss_limit_hit,
            "settings": {
                "max_positions": self.max_positions,
                "risk_percent": self.risk_percent,
                "scan_interval_minutes": self.scan_interval_minutes,
                "max_trades_per_day": self.max_trades_per_day,
                "max_daily_loss_pct": self.max_daily_loss_pct,
                "capital_to_use": self.capital_to_use,
                "leverage": self.leverage,
            },
            "recent_logs": [l.to_dict() for l in self.logs[:50]],
        }


# ── Manager (singleton) ───────────────────────────────────────────────────────

class AutonomousAgentManager:
    """Manages per-user autonomous agents. One instance per app process."""

    def __init__(self):
        self._agents: Dict[str, UserTradingAgent] = {}

    async def start_agent(
        self,
        user_id: str,
        api_key: str,
        access_token: str,
        max_positions: int = 2,
        risk_percent: float = 1.0,
        scan_interval_minutes: int = 5,
        max_trades_per_day: int = 3,
        max_daily_loss_pct: float = 2.0,
        capital_to_use: float = 0.0,
        leverage: int = 1,
    ) -> Dict:
        if user_id in self._agents and self._agents[user_id].is_running:
            return {"status": "already_running", "message": "Agent is already running for this user"}

        agent = UserTradingAgent(
            user_id=user_id,
            api_key=api_key,
            access_token=access_token,
            max_positions=max_positions,
            risk_percent=risk_percent,
            scan_interval_minutes=scan_interval_minutes,
            max_trades_per_day=max_trades_per_day,
            max_daily_loss_pct=max_daily_loss_pct,
            capital_to_use=capital_to_use,
            leverage=leverage,
        )
        self._agents[user_id] = agent
        await agent.start()
        return {"status": "started", "message": f"Autonomous agent started for user {user_id}"}

    async def stop_agent(self, user_id: str) -> Dict:
        if user_id not in self._agents or not self._agents[user_id].is_running:
            # Clean up stale agent if present
            self._agents.pop(user_id, None)
            return {"status": "not_running", "message": "No active agent for this user"}
        await self._agents[user_id].stop()
        # Remove from memory — clean slate for next start, no stale state on refresh
        del self._agents[user_id]
        return {"status": "stopped", "message": "Agent stopped. Open positions have been squared off and GTTs cancelled."}

    def get_agent_status(self, user_id: str) -> Optional[Dict]:
        if user_id not in self._agents:
            return None
        return self._agents[user_id].get_status()

    def is_running(self, user_id: str) -> bool:
        return user_id in self._agents and self._agents[user_id].is_running

    async def stop_all(self):
        for agent in self._agents.values():
            if agent.is_running:
                await agent.stop()
        self._agents.clear()


# Module-level singleton
autonomous_agent_manager = AutonomousAgentManager()
