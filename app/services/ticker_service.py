"""
KiteTicker Service — Real-time WebSocket price streaming via Zerodha's paid API.

Architecture:
  - One KiteTicker instance per user (keyed by api_key).
  - Ticks are pushed into an asyncio.Queue per subscriber.
  - The FastAPI SSE endpoint drains the queue and streams to Flutter.
  - Ticker auto-reconnects on disconnect.

Usage:
  ticker_service.start(api_key, access_token, tokens=[256265, 260105])
  async for tick in ticker_service.subscribe(api_key):
      yield tick  # send to SSE client
  ticker_service.stop(api_key)

Instrument tokens (hardcoded for indices — never change):
  NIFTY 50   : 256265
  NIFTY BANK : 260105
"""

import asyncio
import json
import threading
from datetime import datetime
from typing import Dict, List, Optional, Set
from app.core.logging import logger

try:
    from kiteconnect import KiteTicker
    KITE_TICKER_AVAILABLE = True
except ImportError:
    KITE_TICKER_AVAILABLE = False
    logger.warning("[TickerService] kiteconnect not available — ticker disabled")


# ── Well-known index tokens ────────────────────────────────────────────────

INDEX_TOKENS = {
    "NIFTY": 256265,
    "BANKNIFTY": 260105,
}

WATCHLIST_TOKENS = list(INDEX_TOKENS.values())  # default subscription


class _UserTicker:
    """Manages a single KiteTicker connection for one user."""

    def __init__(self, api_key: str, access_token: str, tokens: List[int]):
        self.api_key = api_key
        self.tokens = tokens
        self._queues: List[asyncio.Queue] = []
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._kt: Optional["KiteTicker"] = None
        self._connected = False
        self._thread: Optional[threading.Thread] = None

    def start(self):
        if not KITE_TICKER_AVAILABLE:
            return
        self._loop = asyncio.get_event_loop()
        self._kt = KiteTicker(self.api_key, self.access_token)  # type: ignore[attr-defined]

        def on_ticks(ws, ticks):
            for tick in ticks:
                payload = {
                    "instrument_token": tick.get("instrument_token"),
                    "last_price": tick.get("last_price"),
                    "change": tick.get("change"),
                    "volume": tick.get("volume_traded"),
                    "buy_quantity": tick.get("total_buy_quantity"),
                    "sell_quantity": tick.get("total_sell_quantity"),
                    "ohlc": tick.get("ohlc", {}),
                    "timestamp": datetime.now().isoformat(),
                }
                for q in list(self._queues):
                    try:
                        self._loop.call_soon_threadsafe(q.put_nowait, payload)
                    except Exception:
                        pass

        def on_connect(ws, response):
            self._connected = True
            ws.subscribe(self.tokens)
            ws.set_mode(ws.MODE_FULL, self.tokens)
            logger.info(
                f"[TickerService] Connected for {self.api_key[:8]}… "
                f"subscribed to {self.tokens}"
            )

        def on_close(ws, code, reason):
            self._connected = False
            logger.info(
                f"[TickerService] Disconnected ({code}): {reason}"
            )

        def on_error(ws, code, reason):
            logger.error(f"[TickerService] Error ({code}): {reason}")

        self._kt.on_ticks = on_ticks
        self._kt.on_connect = on_connect
        self._kt.on_close = on_close
        self._kt.on_error = on_error

        self._thread = threading.Thread(
            target=self._kt.connect, kwargs={"threaded": True}, daemon=True
        )
        self._thread.start()
        logger.info(f"[TickerService] Ticker thread started for {self.api_key[:8]}…")

    def add_queue(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue(maxsize=200)
        self._queues.append(q)
        return q

    def remove_queue(self, q: asyncio.Queue):
        try:
            self._queues.remove(q)
        except ValueError:
            pass

    def stop(self):
        if self._kt:
            try:
                self._kt.close()
            except Exception:
                pass
        self._connected = False
        logger.info(f"[TickerService] Stopped for {self.api_key[:8]}…")

    @property
    def is_connected(self) -> bool:
        return self._connected

    # access_token stored at start time
    @property
    def access_token(self):
        return self._access_token

    @access_token.setter
    def access_token(self, v):
        self._access_token = v


class TickerService:
    """
    Global ticker manager.
    Holds one _UserTicker per api_key and manages subscriber queues.
    """

    def __init__(self):
        self._tickers: Dict[str, _UserTicker] = {}

    def start(
        self,
        api_key: str,
        access_token: str,
        tokens: Optional[List[int]] = None,
    ) -> bool:
        """
        Start (or restart) a ticker for this user.
        If already running with same access_token, returns True immediately.
        """
        if not KITE_TICKER_AVAILABLE:
            logger.warning("[TickerService] KiteTicker not available")
            return False

        if tokens is None:
            tokens = WATCHLIST_TOKENS

        existing = self._tickers.get(api_key)
        if existing and existing.is_connected:
            logger.info(f"[TickerService] Already connected for {api_key[:8]}…")
            return True

        # Stop stale ticker if any
        if existing:
            existing.stop()

        ut = _UserTicker(api_key, access_token, tokens)
        ut.access_token = access_token
        self._tickers[api_key] = ut
        ut.start()
        return True

    def stop(self, api_key: str):
        ut = self._tickers.pop(api_key, None)
        if ut:
            ut.stop()

    async def stream(self, api_key: str, access_token: str, tokens: Optional[List[int]] = None):
        """
        Async generator that yields tick dicts for SSE streaming.
        Auto-starts ticker if not running.
        Cleans up queue on disconnect.
        """
        self.start(api_key, access_token, tokens)
        ut = self._tickers.get(api_key)
        if ut is None:
            return

        q = ut.add_queue()
        try:
            while True:
                try:
                    tick = await asyncio.wait_for(q.get(), timeout=30.0)
                    yield tick
                except asyncio.TimeoutError:
                    # Send heartbeat to keep SSE connection alive
                    yield {"heartbeat": True, "timestamp": datetime.now().isoformat()}
        finally:
            ut.remove_queue(q)
            logger.info(
                f"[TickerService] SSE client disconnected for {api_key[:8]}…"
            )

    def status(self, api_key: str) -> Dict:
        ut = self._tickers.get(api_key)
        if ut is None:
            return {"connected": False, "subscribed_tokens": []}
        return {
            "connected": ut.is_connected,
            "subscribed_tokens": ut.tokens,
            "subscriber_count": len(ut._queues),
        }

    def get_snapshot(self, api_key: str, access_token: str, tokens: List[int]) -> Dict:
        """
        One-shot price snapshot without full WebSocket connection.
        Uses kite.ltp() for low-latency bulk price fetch.
        Returns {token: last_price} map.
        """
        from kiteconnect import KiteConnect
        kite = KiteConnect(api_key=api_key)
        kite.set_access_token(access_token)
        try:
            ltp_data = kite.ltp(tokens)
            return {
                str(token): {
                    "last_price": data["last_price"],
                    "instrument_token": data["instrument_token"],
                }
                for token, data in ltp_data.items()
            }
        except Exception as e:
            logger.error(f"[TickerService] Snapshot failed: {e}")
            return {}


ticker_service = TickerService()
