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
import threading
import uuid
from datetime import datetime
from typing import Dict, List, Optional
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
    """Wraps KiteTicker WebSocket lifecycle for a single user session."""

    def __init__(self, api_key: str, access_token: str, price_cache: PriceCache):
        self._api_key = api_key
        self._access_token = access_token
        self._cache = price_cache
        self._ticker = None
        self._connected = False
        self._subscribed: set = set()

    def start(self):
        from kiteconnect import KiteTicker  # local import to avoid top-level noise
        self._ticker = KiteTicker(self._api_key, self._access_token)

        def on_ticks(ws, ticks):
            self._cache.update(ticks)

        def on_connect(ws, response):
            self._connected = True
            logger.info("[Ticker] WebSocket connected")
            # Re-subscribe to any tokens already queued before connect
            if self._subscribed:
                tokens = list(self._subscribed)
                ws.subscribe(tokens)
                ws.set_mode(ws.MODE_QUOTE, tokens)

        def on_close(ws, code, reason):
            self._connected = False
            logger.info(f"[Ticker] WebSocket closed: {code} {reason}")

        def on_error(ws, code, reason):
            logger.warning(f"[Ticker] Error {code}: {reason}")

        self._ticker.on_ticks = on_ticks
        self._ticker.on_connect = on_connect
        self._ticker.on_close = on_close
        self._ticker.on_error = on_error

        # Runs in a background thread — non-blocking
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
        max_trades_per_day: int = 6,
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

    # ── Logging ───────────────────────────────────────────────────────────────

    def _log(self, event: str, message: str, symbol: str = None):
        entry = AgentLog(event, message, symbol)
        self.logs.insert(0, entry)
        if len(self.logs) > self.MAX_LOGS:
            self.logs = self.logs[: self.MAX_LOGS]
        logger.info(f"[Agent:{self.user_id}][{event}] {message}")

    def _get_kite(self) -> KiteConnect:
        kite = KiteConnect(api_key=self.api_key, timeout=15)
        kite.set_access_token(self.access_token)
        return kite

    # ── Lifecycle ─────────────────────────────────────────────────────────────

    async def start(self):
        if self.is_running:
            return
        self.is_running = True
        self.status = "SCANNING"
        self.started_at = _ist_now().isoformat()
        self.trade_count_today = 0
        self.daily_pnl = 0.0
        self.daily_loss_limit_hit = False
        self._scanning_done = False  # fresh start — enable scanning

        self._log("STARTED", "Autonomous trading agent started")

        # Fetch starting capital
        try:
            kite = self._get_kite()
            loop = asyncio.get_event_loop()
            margins = await loop.run_in_executor(None, kite.margins)
            equity = margins.get("equity", {})
            balance = float(
                equity.get("available", {}).get("live_balance")
                or equity.get("net", 0)
            )
            self.starting_capital = (
                self.capital_to_use if self.capital_to_use > 0 else balance
            )
            self._log("CAPITAL", f"Starting capital: ₹{self.starting_capital:,.2f}")
        except Exception as e:
            self._log("WARN", f"Could not fetch starting capital: {e}")

        # Start KiteTicker for real-time price streaming
        try:
            self._ticker_manager = _TickerManager(
                self.api_key, self.access_token, self._price_cache
            )
            self._ticker_manager.start()
            self._log("TICKER", "KiteTicker WebSocket started — real-time prices active")
        except Exception as e:
            self._log("WARN", f"KiteTicker failed to start (will fall back to API polling): {e}")
            self._ticker_manager = None

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
            return

        self.is_running = False  # halt loops at next iteration

        if self.positions:
            if _is_market_open():
                self.status = "SQUARING_OFF"
                self._log("SQUAREOFF", "Agent stopping — squaring off all open positions and cancelling GTTs")
                await self._force_squareoff()
            else:
                self._log("GTT_CANCEL", "Agent stopping — market closed, cancelling all active GTTs")
                await self._cancel_all_gtts()

        self.status = "STOPPED"

        for task in [self._scan_task, self._monitor_task]:
            if task:
                task.cancel()

        # Stop KiteTicker
        if self._ticker_manager:
            try:
                self._ticker_manager.stop()
            except Exception:
                pass
            self._ticker_manager = None

        self._log("STOPPED", "Autonomous trading agent stopped")

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
                    self._log("WAIT", "Market closed — sleeping")
                    await asyncio.sleep(60)
                    continue

                # Phase 2: scanning complete — only monitoring
                if self._scanning_done:
                    await asyncio.sleep(60)
                    continue

                if self.daily_loss_limit_hit:
                    self._log("PAUSED", "Daily loss limit hit — no new trades today")
                    self._scanning_done = True
                    await asyncio.sleep(300)
                    continue

                mins_left = _minutes_until_squareoff()
                if mins_left <= 20:
                    self._log("SCAN_SKIP", f"Only {mins_left} min until squareoff — skipping new entries")
                    self._scanning_done = True
                    await asyncio.sleep(60)
                    continue

                if self.trade_count_today >= self.max_trades_per_day:
                    self._log("SCAN_SKIP", f"Max trades/day ({self.max_trades_per_day}) reached — done for today")
                    self._scanning_done = True
                    await asyncio.sleep(300)
                    continue

                await self._run_scan()

            except asyncio.CancelledError:
                break
            except Exception as e:
                self._log("ERROR", f"Scan loop error: {e}")
                await asyncio.sleep(60)

            if not self._scanning_done:
                await asyncio.sleep(self.scan_interval_minutes * 60)

    async def _run_scan(self):
        """
        Scan market → score all signals → execute top-N positions in one pass.
        After this call completes (regardless of result), _scanning_done is set
        to True once at least one position is open, preventing further scans.
        """
        self.status = "SCANNING"
        self._log("SCAN_START", f"Market scan running ({len(self.positions)} open, {self.trade_count_today} trades today)")
        self.last_scan_at = _ist_now().isoformat()

        try:
            candidates = await self._analysis_svc.screen_and_enrich_intraday(
                limit=20,
                user_api_key=self.api_key,
                user_access_token=self.access_token,
            )

            if not candidates:
                self._log("SCAN_EMPTY", "Screener returned no candidates")
                return

            # Skip stocks already in an open position
            open_symbols = set(self.positions.keys())
            fresh = [c for c in candidates if c["symbol"] not in open_symbols]

            if not fresh:
                self._log("SCAN_SKIP", "All top candidates already in open positions")
                return

            # Score each candidate
            qualified = []
            for c in fresh:
                indicators = c.get("indicators", {})
                if not indicators:
                    continue
                sig = strategy_engine.generate_intraday_signal(indicators)
                if sig["strength"] >= 2 and sig["signal"] != "NEUTRAL":
                    qualified.append({**c, "sig": sig})

            if not qualified:
                self._log(
                    "SCAN_NONE",
                    f"Scanned {len(fresh)} stocks — no signal with strength ≥ 2",
                )
                return

            # Sort best first and take up to available position slots
            qualified.sort(key=lambda x: x["sig"]["score"], reverse=True)
            slots_available = self.max_positions - len(self.positions)
            to_trade = qualified[:slots_available]

            self._log(
                "SCAN_RESULT",
                f"Found {len(qualified)} qualifying signals — entering {len(to_trade)} position(s)",
            )

            # Get available capital once for this scan cycle
            try:
                kite = self._get_kite()
                loop = asyncio.get_event_loop()
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
            except Exception:
                capital = self.starting_capital

            if capital < 1000:
                self._log("SKIP", f"Insufficient capital (₹{capital:.0f}) — skipping all entries")
                return

            # Execute each qualifying stock
            for best in to_trade:
                if not self.is_running:
                    break
                if self.trade_count_today >= self.max_trades_per_day:
                    self._log("SCAN_SKIP", f"Max trades/day ({self.max_trades_per_day}) reached")
                    break

                symbol = best["symbol"]
                sig = best["sig"]
                ltp = float(best["last_price"])

                self._log(
                    "SIGNAL",
                    f"{symbol}: {sig['signal']} strength={sig['strength']} score={sig['score']} @ ₹{ltp:.2f}",
                    symbol=symbol,
                )

                # Position sizing: ATR-based SL/target, risk% of capital
                indicators = best.get("indicators", {})
                atr = float(indicators.get("atr_14", ltp * 0.01) or ltp * 0.01)
                action = sig["signal"]  # BUY or SELL

                if action == "BUY":
                    stop_loss = round(ltp - (1.5 * atr), 2)
                    target = round(ltp + (3.0 * atr), 2)
                    if not (stop_loss < ltp < target):
                        stop_loss = round(ltp * 0.985, 2)
                        target = round(ltp * 1.03, 2)
                else:  # SELL (short)
                    stop_loss = round(ltp + (1.5 * atr), 2)
                    target = round(ltp - (3.0 * atr), 2)
                    if not (target < ltp < stop_loss):
                        stop_loss = round(ltp * 1.015, 2)
                        target = round(ltp * 0.97, 2)

                risk_per_share = abs(ltp - stop_loss)
                effective_capital = capital * self.leverage
                max_risk = effective_capital * (self.risk_percent / 100)
                quantity = max(1, int(max_risk / risk_per_share)) if risk_per_share > 0 else 1

                # Cap: no more than 10% of capital per trade
                max_by_capital = int((capital * 0.10) / ltp) if ltp > 0 else 1
                quantity = min(quantity, max(1, max_by_capital))

                self._log(
                    "ENTRY",
                    f"{symbol}: {action} {quantity} shares @ ₹{ltp:.2f} | SL: ₹{stop_loss:.2f} | Target: ₹{target:.2f}",
                    symbol=symbol,
                )

                # Execute trade using existing execution_agent
                analysis_id = str(uuid.uuid4())
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
                    )
                except Exception as e:
                    self._log("TRADE_FAIL", f"{symbol}: Execution error — {e}", symbol=symbol)
                    continue

                if result["status"] == "COMPLETED":
                    self.positions[symbol] = PositionState(
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
                    self.trade_count_today += 1
                    self._log(
                        "TRADE_OPEN",
                        f"{symbol}: Position opened — GTT ID: {result.get('gtt_order_id')}",
                        symbol=symbol,
                    )

                    # Subscribe to KiteTicker for real-time price streaming
                    await self._subscribe_ticker(symbol)
                else:
                    self._log(
                        "TRADE_FAIL",
                        f"{symbol}: Trade failed — {result.get('error', result['status'])}",
                        symbol=symbol,
                    )

        except Exception as e:
            self._log("ERROR", f"Scan error: {e}")
        finally:
            # Switch to monitoring mode once we have open positions
            if self.positions:
                self._scanning_done = True
                self._log(
                    "SCAN_DONE",
                    f"Stock selection complete — {len(self.positions)} position(s) open. Switching to monitoring mode.",
                )
            self.status = "MONITORING"

    async def _subscribe_ticker(self, symbol: str):
        """Fetch instrument token for symbol and subscribe to KiteTicker."""
        if not self._ticker_manager:
            return
        try:
            kite = self._get_kite()
            loop = asyncio.get_event_loop()
            ltp_data = await loop.run_in_executor(
                None, lambda: kite.ltp([f"NSE:{symbol}"])
            )
            token = ltp_data.get(f"NSE:{symbol}", {}).get("instrument_token")
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

                if not self.positions or not _is_market_open():
                    continue

                if _minutes_until_squareoff() <= 2:
                    self._log("SQUAREOFF", "3:10 PM squareoff triggered — closing all MIS positions")
                    await self._force_squareoff()
                    continue

                gtt_check_counter += 1
                check_gtts = (gtt_check_counter % 6 == 0)  # every ~30 seconds
                await self._monitor_positions(check_gtts=check_gtts)

            except asyncio.CancelledError:
                break
            except Exception as e:
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
                try:
                    kite = self._get_kite()
                    loop = asyncio.get_event_loop()
                    quotes = await loop.run_in_executor(
                        None, lambda: kite.quote([f"NSE:{s}" for s in cache_miss_symbols])
                    )
                    for symbol in cache_miss_symbols:
                        quote = quotes.get(f"NSE:{symbol}", {})
                        ltp = quote.get("last_price")
                        if ltp is not None:
                            prices[symbol] = float(ltp)
                except Exception as e:
                    self._log("WARN", f"API price fallback failed: {e}")

            # Step 2: Fetch active GTT IDs (only every 30s to limit API calls)
            active_gtt_ids: set = set()
            if check_gtts:
                try:
                    kite = self._get_kite()
                    loop = asyncio.get_event_loop()
                    gtts = await loop.run_in_executor(None, kite.get_gtts)
                    active_gtt_ids = {
                        str(g.get("id"))
                        for g in gtts
                        if g.get("status", "").lower() in ("active",)
                    }
                except Exception:
                    pass

            filled_symbols = []

            for symbol, pos in list(self.positions.items()):
                ltp = prices.get(symbol, pos.entry_price)

                # ── P&L update ────────────────────────────────────────────
                if pos.action == "BUY":
                    pos.current_pnl = (ltp - pos.entry_price) * pos.quantity
                else:
                    pos.current_pnl = (pos.entry_price - ltp) * pos.quantity

                # Log position update at reduced frequency (every 30s)
                if check_gtts:
                    move_done = (ltp - pos.entry_price) if pos.action == "BUY" else (pos.entry_price - ltp)
                    move_total = (pos.target - pos.entry_price) if pos.action == "BUY" else (pos.entry_price - pos.target)
                    progress = (move_done / move_total * 100) if move_total > 0 else 0
                    self._log(
                        "POS_UPDATE",
                        f"{symbol}: LTP ₹{ltp:.2f} | P&L ₹{pos.current_pnl:+.2f} | {progress:.0f}% to target",
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
                # When a position was moving favourably but price has since reversed
                # by ≥ 0.5 ATR from the watermark (and we're still in profit), lower
                # the target so the GTT fires sooner and locks in the remaining gain.
                # Only done once per position to avoid GTT-churn.
                if check_gtts and pos.atr > 0 and not pos.target_adjusted:
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
                        f"{symbol}: GTT no longer active — position closed. P&L ≈ ₹{pos.current_pnl:+.2f}",
                        symbol=symbol,
                    )
                    self.daily_pnl += pos.current_pnl
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
            loop = asyncio.get_event_loop()

            if pos.gtt_id:
                try:
                    gtt_id = pos.gtt_id
                    await loop.run_in_executor(None, lambda: kite.delete_gtt(gtt_id))
                    self._log("GTT_CANCEL", f"{pos.symbol}: GTT {pos.gtt_id} cancelled ({reason})", symbol=pos.symbol)
                except Exception as e:
                    self._log("WARN", f"{pos.symbol}: Could not cancel GTT: {e}", symbol=pos.symbol)

            is_short = pos.action == "SELL"
            if is_short:
                trigger_values = sorted([new_target, new_sl])
                orders = [
                    {"transaction_type": "BUY", "quantity": pos.quantity, "order_type": "LIMIT", "product": "MIS", "price": new_target},
                    {"transaction_type": "BUY", "quantity": pos.quantity, "order_type": "LIMIT", "product": "MIS", "price": new_sl},
                ]
            else:
                trigger_values = sorted([new_sl, new_target])
                orders = [
                    {"transaction_type": "SELL", "quantity": pos.quantity, "order_type": "LIMIT", "product": "MIS", "price": new_sl},
                    {"transaction_type": "SELL", "quantity": pos.quantity, "order_type": "LIMIT", "product": "MIS", "price": new_target},
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
            pos.gtt_id = new_gtt_id
            self._log(
                "GTT_UPDATED",
                f"{pos.symbol}: New GTT {new_gtt_id} | SL ₹{new_sl:.2f} | Target ₹{new_target:.2f}",
                symbol=pos.symbol,
            )

        except Exception as e:
            self._log("ERROR", f"{pos.symbol}: GTT update failed: {e}", symbol=pos.symbol)

    # ── Cancel all GTTs (no position close — used when market is closed) ──────

    async def _cancel_all_gtts(self):
        """Cancel all active GTTs without closing positions. Used on off-hours stop."""
        if not self.positions:
            return
        kite = self._get_kite()
        loop = asyncio.get_event_loop()
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
        loop = asyncio.get_event_loop()

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

                # Close position at market
                close_txn = "SELL" if pos.action == "BUY" else "BUY"
                qty = pos.quantity
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
                    f"{symbol}: Squareoff order placed ({close_txn} {qty} MIS MARKET) — ID: {order_id}",
                    symbol=symbol,
                )
                self.daily_pnl += pos.current_pnl

                # Unsubscribe from ticker
                if pos.instrument_token and self._ticker_manager:
                    self._ticker_manager.unsubscribe(pos.instrument_token)
                self._price_cache.remove_symbol(symbol)
                self.positions.pop(symbol, None)

            except Exception as e:
                self._log("ERROR", f"{symbol}: Squareoff failed: {e}", symbol=symbol)

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
        max_trades_per_day: int = 6,
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
