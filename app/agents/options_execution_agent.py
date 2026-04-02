"""
Options Execution Agent

Workflow for intraday options (MIS):
  1. Place BUY LIMIT order with market-protection price (entry + 2% slippage, rounded
     to NFO tick size 0.05) — Zerodha API rejects plain MARKET orders on NFO.
  2. Wait for fill — capture actual fill price (avg_price)
  3. Place SL (stop-loss limit) SELL order: trigger=adjusted_sl, price=trigger-5%
     SL-M is discontinued for F&O by the exchange. 5% gap chosen (not 2%) because
     options can gap down sharply on fast moves, and a 2% limit often goes unfilled.
  4. Do NOT place a simultaneous target SELL order.
     Reason: Zerodha treats a second SELL as a new short position and charges short
     margin, often rejecting it as "insufficient funds" even though you hold a long.
     Target exits are handled exclusively by the monitoring agent (_check_target_hit
     + _exit_position), which cancels the SL order before placing the exit SELL so
     there is never more than one open SELL order at a time.

No GTT is used here — Zerodha does NOT support GTT for MIS orders on options.
Auto square-off at 3:15 PM is the backstop.
"""

import asyncio
import uuid
from datetime import datetime
from typing import Callable, Dict, Optional, Tuple
from app.core.logging import logger
from app.services.zerodha_service import zerodha_service
from app.models.analysis_models import ExecutionUpdate


class OptionsExecutionAgent:

    FILL_POLL_INTERVAL = 3     # seconds between order status checks
    FILL_TIMEOUT = 60          # seconds — limit orders at market price fill fast
    NFO_TICK_SIZE = 0.05       # minimum price increment for NFO options
    MARKET_PROTECTION_PCT = 0.02  # 2% above current premium for BUY LIMIT (ensures fill)
    SL_LIMIT_GAP_PCT = 0.05       # 5% below SL trigger for the SL-L limit price
                                   # (options gap down fast; 2% often goes unfilled)
    MAX_ENTRY_RETRIES = 3      # max times to retry a rejected entry order

    # Rejection reasons that can be fixed by fetching fresh LTP + recalculating price
    _PRICE_REJECTION_KEYWORDS = (
        "price", "range", "tick", "ltp", "circuit", "limit",
    )
    # Rejection reasons that cannot be fixed — fail immediately
    _FATAL_REJECTION_KEYWORDS = (
        "margin", "fund", "quantity", "lot", "banned", "blocked", "square",
    )

    def __init__(self):
        self.zs = zerodha_service

    async def execute_options_trade(
        self,
        option_symbol: str,          # e.g. NIFTY25APR22500CE
        instrument_token: int,
        quantity: int,               # lots × lot_size
        entry_premium: float,
        stop_loss_premium: float,
        target_premium: float,
        analysis_id: str,
        api_key: str,
        access_token: str,
        update_callback: Optional[Callable] = None,
        # Preserve analysis-recommended levels for display continuity
        analysis_sl: float = 0.0,
        analysis_target: float = 0.0,
    ) -> Dict:
        """
        Execute a Nifty/BankNifty options trade:
          1. BUY MARKET (MIS) on NFO
          2. SL-M SELL (MIS) at stop_loss_premium trigger

        Returns execution log dict.
        """
        execution_log = {
            "option_symbol": option_symbol,
            "quantity": quantity,
            "status": "STARTED",
            "entry_order_id": None,
            "sl_order_id": None,
            "target_order_id": None,
            "fill_price": None,
            "sl_trigger": None,
            "sl_limit": None,
            "target_price": None,
            "updates": [],
        }

        self.zs.set_credentials(api_key, access_token)

        try:
            # ── Steps 1+2: Place BUY LIMIT with retry on rejection ──────────
            # Zerodha API rejects plain MARKET orders on NFO.
            # We place LIMIT at entry_premium + 2% (market protection).  If the
            # order is rejected because the price is stale (premium moved since
            # analysis), we fetch the current LTP and retry up to MAX_ENTRY_RETRIES.
            entry_order_id, fill_price = await self._place_entry_with_retry(
                option_symbol=option_symbol,
                quantity=quantity,
                entry_premium=entry_premium,
                analysis_id=analysis_id,
                update_callback=update_callback,
            )

            if fill_price is None:
                raise RuntimeError(
                    f"Entry order could not be filled after {self.MAX_ENTRY_RETRIES} attempts"
                )

            execution_log["entry_order_id"] = entry_order_id
            execution_log["fill_price"] = fill_price
            await self._send_update(
                analysis_id, option_symbol, "ORDER_FILLED",
                f"Filled at ₹{fill_price:.2f} premium. Placing SL-M order…",
                update_callback,
            )

            # ── Step 3: Derive SL from analysis-recommended levels ──────
            # Scale the analysis SL proportionally to the actual fill price
            # so the R:R the user approved is preserved.
            # e.g. analysis entry=₹309 SL=₹306 (1% below) → fill=₹311 SL≈₹308
            if entry_premium > 0 and stop_loss_premium < entry_premium:
                sl_ratio = stop_loss_premium / entry_premium   # e.g. 0.990
                raw_sl = fill_price * sl_ratio
            else:
                raw_sl = fill_price * 0.97   # fallback: 3% below fill

            # Hard rule: SL trigger MUST be strictly below fill price.
            # Only apply the safety guard if the scaled SL is at or above fill.
            # Do NOT force the SL 3% below fill when the analysis SL was tighter —
            # that changes the R:R and causes the mismatch the user sees.
            if raw_sl >= fill_price:
                raw_sl = fill_price * 0.97

            adjusted_sl = self._snap_tick_down(raw_sl)

            # Derive target: scale analysis target by same fill/entry ratio
            # so it stays consistent with the R:R the user approved.
            if entry_premium > 0 and analysis_target > entry_premium:
                target_ratio = (analysis_target - entry_premium) / entry_premium
                raw_target = fill_price * (1 + target_ratio)
            else:
                # Fallback: 2× the SL distance above fill
                raw_target = fill_price + (fill_price - adjusted_sl) * 2.0
            adjusted_target = self._round_to_tick(raw_target)

            # Ensure target > fill > sl
            if adjusted_target <= fill_price:
                adjusted_target = self._round_to_tick(
                    fill_price + (fill_price - adjusted_sl) * 2.0
                )

            logger.info(
                f"[OptionsExecution] Levels: fill=₹{fill_price:.2f} "
                f"sl=₹{adjusted_sl:.2f} target=₹{adjusted_target:.2f} "
                f"(analysis entry=₹{entry_premium:.2f} sl=₹{stop_loss_premium:.2f} "
                f"target=₹{analysis_target:.2f})"
            )

            # ── Step 4: Place SL (Stop-Loss Limit) SELL order ──────────
            # SL-M is discontinued for F&O. Use SL (stop-loss limit) instead:
            # trigger_price = adjusted_sl (order activates when premium hits this)
            # price = trigger - 2% slippage, rounded to tick (ensures fill after trigger)
            sl_limit_price = self._sl_limit_price(adjusted_sl)
            sl_order_id = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: self.zs.kite.place_order(
                    variety=self.zs.kite.VARIETY_REGULAR,
                    exchange=self.zs.kite.EXCHANGE_NFO,
                    tradingsymbol=option_symbol,
                    transaction_type=self.zs.kite.TRANSACTION_TYPE_SELL,
                    quantity=quantity,
                    product=self.zs.kite.PRODUCT_MIS,
                    order_type=self.zs.kite.ORDER_TYPE_SL,
                    trigger_price=adjusted_sl,
                    price=sl_limit_price,
                ),
            )

            execution_log["sl_order_id"] = sl_order_id
            execution_log["sl_trigger"] = adjusted_sl
            execution_log["sl_limit"] = sl_limit_price

            # ── Step 5: Record target level — NO second SELL order placed ──
            # Placing a simultaneous LIMIT SELL for the same qty while an SL SELL
            # is already open causes Zerodha to treat it as a new short position and
            # reject it for "insufficient funds" (short margin required).
            # The monitoring agent handles target exits via _check_target_hit():
            # it cancels the SL order first, then places a single LIMIT SELL, so
            # there is never more than one open SELL order at any time.
            execution_log["target_order_id"] = None   # managed by monitoring agent
            execution_log["target_price"] = adjusted_target
            execution_log["status"] = "COMPLETED"
            await self._send_update(
                analysis_id, option_symbol, "COMPLETED",
                (
                    f"Trade active! Fill=₹{fill_price:.2f} | "
                    f"SL trigger=₹{adjusted_sl:.2f} limit=₹{sl_limit_price:.2f} (order {sl_order_id}) | "
                    f"Target=₹{adjusted_target:.2f} — monitored by AI agent (no second SELL placed). "
                    f"Auto square-off at 3:15 PM."
                ),
                update_callback,
            )

        except Exception as exc:
            execution_log["status"] = "FAILED"
            execution_log["error"] = str(exc)
            logger.error(
                f"[OptionsExecutionAgent] {option_symbol} execution failed: {exc}",
                exc_info=True,
            )
            await self._send_update(
                analysis_id, option_symbol, "ERROR",
                f"Execution failed: {exc}",
                update_callback,
            )

        return execution_log

    def _round_to_tick(self, price: float) -> float:
        """Round price to nearest NFO tick size (0.05)."""
        ticks = round(price / self.NFO_TICK_SIZE)
        return round(ticks * self.NFO_TICK_SIZE, 2)

    def _snap_tick_down(self, price: float) -> float:
        """Round DOWN to nearest NFO tick (0.05). Used for SL trigger so it is
        always strictly below the reference price, never accidentally above it."""
        ticks = int(price / self.NFO_TICK_SIZE)
        return round(ticks * self.NFO_TICK_SIZE, 2)

    def _sl_limit_price(self, trigger: float) -> float:
        """
        Return the limit price for an SL-L (stop-loss limit) SELL order.
        Set 5% below the trigger, rounded down to the nearest NFO tick (0.05).
        Options can gap down sharply on fast moves; a 2% gap often goes unfilled.
        5% gives a wider safety net while still bounding slippage.
        """
        raw = trigger * (1 - self.SL_LIMIT_GAP_PCT)
        ticks = int(raw / self.NFO_TICK_SIZE)
        return round(ticks * self.NFO_TICK_SIZE, 2)

    def _market_protect_price(self, premium: float) -> float:
        """
        Return a limit price slightly above the current premium to ensure fill
        (market-protection pattern required by Zerodha NFO API).
        Rounds up to the nearest NFO tick size (0.05).
        """
        raw = premium * (1 + self.MARKET_PROTECTION_PCT)
        ticks = round(raw / self.NFO_TICK_SIZE)
        return round(ticks * self.NFO_TICK_SIZE, 2)

    async def _place_entry_with_retry(
        self,
        option_symbol: str,
        quantity: int,
        entry_premium: float,
        analysis_id: str,
        update_callback: Optional[Callable],
    ) -> Tuple[Optional[str], Optional[float]]:
        """
        Place a BUY LIMIT entry order with automatic retry on price-related rejections.

        Strategy on rejection:
          - Price / range / tick errors → fetch fresh LTP from Zerodha, recalculate
            market-protection price, and retry (up to MAX_ENTRY_RETRIES).
          - Fatal errors (margin, quantity, banned, etc.) → fail immediately.
          - Timeout (did not fill within FILL_TIMEOUT) → widen protection slightly
            and retry once more.

        Returns (order_id, fill_price) or (None, None) on final failure.
        """
        loop = asyncio.get_event_loop()
        current_premium = entry_premium  # starts with analysis price; refreshed on retry

        for attempt in range(1, self.MAX_ENTRY_RETRIES + 1):
            protect_price = self._market_protect_price(current_premium)

            await self._send_update(
                analysis_id, option_symbol, "ORDER_PLACING",
                (
                    f"[Attempt {attempt}/{self.MAX_ENTRY_RETRIES}] "
                    f"Placing BUY LIMIT — {quantity} × {option_symbol} "
                    f"@ ₹{protect_price:.2f} (LTP basis: ₹{current_premium:.2f}, MIS, NFO)"
                ),
                update_callback,
            )

            try:
                order_id = await loop.run_in_executor(
                    None,
                    lambda p=protect_price: self.zs.kite.place_order(
                        variety=self.zs.kite.VARIETY_REGULAR,
                        exchange=self.zs.kite.EXCHANGE_NFO,
                        tradingsymbol=option_symbol,
                        transaction_type=self.zs.kite.TRANSACTION_TYPE_BUY,
                        quantity=quantity,
                        product=self.zs.kite.PRODUCT_MIS,
                        order_type=self.zs.kite.ORDER_TYPE_LIMIT,
                        price=p,
                    ),
                )
            except Exception as place_err:
                # Zerodha raises InputException for synchronous rejections
                reason = str(place_err)
                logger.error(
                    f"[OptionsExecution] place_order raised on attempt {attempt}: {reason}"
                )
                await self._send_update(
                    analysis_id, option_symbol, "ORDER_REJECTED",
                    f"Order placement error (attempt {attempt}): {reason}",
                    update_callback,
                )
                refreshed = await self._handle_rejection(
                    option_symbol, reason, attempt, analysis_id, update_callback
                )
                if refreshed is None:
                    return None, None   # fatal rejection
                current_premium = refreshed
                continue

            await self._send_update(
                analysis_id, option_symbol, "ORDER_PLACED",
                f"Order placed: {order_id} @ ₹{protect_price:.2f}. Waiting for fill…",
                update_callback,
            )

            fill_price, rejection_reason = await self._wait_for_fill(
                order_id, analysis_id, option_symbol, update_callback
            )

            if fill_price is not None:
                return order_id, fill_price

            if rejection_reason is not None:
                # Order was rejected after being accepted — diagnose and retry
                refreshed = await self._handle_rejection(
                    option_symbol, rejection_reason, attempt,
                    analysis_id, update_callback
                )
                if refreshed is None:
                    return None, None   # fatal rejection
                current_premium = refreshed
            else:
                # Timeout — widen protection by another 1% and retry
                logger.warning(
                    f"[OptionsExecution] Fill timeout on attempt {attempt}. "
                    f"Fetching fresh LTP and widening protection."
                )
                ltp = await self._fetch_ltp(option_symbol)
                current_premium = ltp if ltp else current_premium * 1.01
                await self._send_update(
                    analysis_id, option_symbol, "ORDER_TIMEOUT",
                    (
                        f"Order did not fill within {self.FILL_TIMEOUT}s "
                        f"(attempt {attempt}). Fresh LTP: ₹{current_premium:.2f}. Retrying…"
                    ),
                    update_callback,
                )

        logger.error(
            f"[OptionsExecution] {option_symbol} entry failed after "
            f"{self.MAX_ENTRY_RETRIES} attempts."
        )
        return None, None

    async def _handle_rejection(
        self,
        option_symbol: str,
        reason: str,
        attempt: int,
        analysis_id: str,
        update_callback: Optional[Callable],
    ) -> Optional[float]:
        """
        Triage the rejection reason.
        Returns a refreshed premium to use for the next attempt,
        or None if the rejection is fatal and no retry should be made.
        """
        reason_lower = reason.lower()

        # Fatal reasons — cannot be fixed programmatically
        if any(kw in reason_lower for kw in self._FATAL_REJECTION_KEYWORDS):
            logger.error(
                f"[OptionsExecution] Fatal rejection for {option_symbol}: {reason}"
            )
            await self._send_update(
                analysis_id, option_symbol, "ORDER_REJECTED",
                f"Fatal rejection — cannot retry: {reason}",
                update_callback,
            )
            return None

        # Price / range rejections — fetch fresh LTP and retry
        if any(kw in reason_lower for kw in self._PRICE_REJECTION_KEYWORDS):
            ltp = await self._fetch_ltp(option_symbol)
            if ltp and ltp > 0:
                logger.info(
                    f"[OptionsExecution] Price rejection on attempt {attempt}. "
                    f"Fresh LTP for {option_symbol}: ₹{ltp:.2f}"
                )
                await self._send_update(
                    analysis_id, option_symbol, "ORDER_REJECTED",
                    (
                        f'Order rejected: "{reason}". '
                        f"Fetched fresh LTP ₹{ltp:.2f} — recalculating price and retrying…"
                    ),
                    update_callback,
                )
                return ltp
            else:
                logger.error(
                    f"[OptionsExecution] Price rejection but LTP fetch failed: {reason}"
                )
                await self._send_update(
                    analysis_id, option_symbol, "ORDER_REJECTED",
                    f"Order rejected and LTP fetch failed: {reason}",
                    update_callback,
                )
                return None

        # Unknown reason — attempt retry with fresh LTP as a best-effort
        ltp = await self._fetch_ltp(option_symbol)
        if ltp and ltp > 0 and attempt < self.MAX_ENTRY_RETRIES:
            await self._send_update(
                analysis_id, option_symbol, "ORDER_REJECTED",
                (
                    f'Order rejected (unknown reason): "{reason}". '
                    f"Retrying with fresh LTP ₹{ltp:.2f}…"
                ),
                update_callback,
            )
            return ltp

        await self._send_update(
            analysis_id, option_symbol, "ORDER_REJECTED",
            f"Order rejected and out of retries: {reason}",
            update_callback,
        )
        return None

    async def _fetch_ltp(self, option_symbol: str) -> Optional[float]:
        """Fetch the current last-traded price of an NFO option from Zerodha."""
        try:
            loop = asyncio.get_event_loop()
            nfo_key = f"NFO:{option_symbol}"
            ltp_data = await loop.run_in_executor(
                None, lambda: self.zs.kite.ltp([nfo_key])
            )
            ltp = ltp_data.get(nfo_key, {}).get("last_price", 0.0)
            logger.info(f"[OptionsExecution] LTP fetch {option_symbol}: ₹{ltp:.2f}")
            return float(ltp) if ltp else None
        except Exception as e:
            logger.warning(f"[OptionsExecution] LTP fetch failed for {option_symbol}: {e}")
            return None

    async def _wait_for_fill(
        self,
        order_id: str,
        analysis_id: str,
        symbol: str,
        update_callback: Optional[Callable],
    ) -> Tuple[Optional[float], Optional[str]]:
        """
        Poll order status until COMPLETE, REJECTED, CANCELLED, or timeout.

        Returns:
          (fill_price, None)  — filled successfully
          (None, reason)      — rejected/cancelled with reason string
          (None, None)        — timed out without a terminal status
        """
        elapsed = 0
        loop = asyncio.get_event_loop()

        while elapsed < self.FILL_TIMEOUT:
            await asyncio.sleep(self.FILL_POLL_INTERVAL)
            elapsed += self.FILL_POLL_INTERVAL

            try:
                orders = await loop.run_in_executor(
                    None, self.zs.kite.orders
                )
                order = next(
                    (o for o in orders if str(o["order_id"]) == str(order_id)),
                    None,
                )
                if order:
                    status = order.get("status", "").upper()
                    if status == "COMPLETE":
                        avg_price = float(order.get("average_price", 0))
                        logger.info(
                            f"[OptionsExecution] {symbol} order {order_id} "
                            f"filled @ ₹{avg_price:.2f}"
                        )
                        return avg_price, None
                    elif status in ("REJECTED", "CANCELLED"):
                        reason = order.get("status_message", status)
                        logger.error(
                            f"[OptionsExecution] Order {order_id} {status}: {reason}"
                        )
                        return None, reason
            except Exception as e:
                logger.warning(f"[OptionsExecution] Status poll error: {e}")

        logger.error(
            f"[OptionsExecution] Order {order_id} timeout after {self.FILL_TIMEOUT}s"
        )
        return None, None

    async def _send_update(
        self,
        analysis_id: str,
        symbol: str,
        update_type: str,
        message: str,
        callback: Optional[Callable],
    ):
        update = ExecutionUpdate(
            analysis_id=analysis_id,
            stock_symbol=symbol,
            update_type=update_type,
            message=message,
        )
        if callback:
            try:
                await callback(update)
            except Exception as e:
                logger.warning(f"[OptionsExecution] Callback error: {e}")
        logger.info(f"[OptionsExecution][{symbol}][{update_type}] {message}")


options_execution_agent = OptionsExecutionAgent()
