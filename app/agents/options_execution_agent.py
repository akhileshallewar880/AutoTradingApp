"""
Options Execution Agent

Workflow for intraday options (MIS):
  1. Place BUY LIMIT order with market-protection price (entry + 2% slippage, rounded
     to NFO tick size 0.05) — Zerodha API rejects plain MARKET orders on NFO.
  2. Wait for fill — capture actual fill price (avg_price)
  3. Place SL (stop-loss limit) SELL order: trigger=adjusted_sl, price=trigger-2%
     SL-M is discontinued for F&O by the exchange.
  4. Place LIMIT SELL order at target premium (take-profit leg).
     GTT is not supported for MIS options — both SL and target orders are live
     simultaneously; user must cancel the unfilled one after exit.
  5. Return execution log with order IDs.

No GTT is used here — Zerodha does NOT support GTT for MIS orders on options.
Auto square-off at 3:15 PM is the backstop.
"""

import asyncio
import uuid
from datetime import datetime
from typing import Callable, Dict, Optional
from app.core.logging import logger
from app.services.zerodha_service import zerodha_service
from app.models.analysis_models import ExecutionUpdate


class OptionsExecutionAgent:

    FILL_POLL_INTERVAL = 3     # seconds between order status checks
    FILL_TIMEOUT = 60          # seconds — limit orders at market price fill fast
    NFO_TICK_SIZE = 0.05       # minimum price increment for NFO options
    MARKET_PROTECTION_PCT = 0.02  # 2% above current premium for buy limit (ensures fill)

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
            # ── Step 1: Place BUY LIMIT order with market protection ────────
            # Zerodha API rejects plain MARKET orders on NFO.
            # Use LIMIT at entry_premium + 2% slippage, rounded to tick size 0.05.
            protect_price = self._market_protect_price(entry_premium)
            await self._send_update(
                analysis_id, option_symbol, "ORDER_PLACING",
                (
                    f"Placing BUY LIMIT order — {quantity} units of {option_symbol} "
                    f"@ ₹{protect_price:.2f} (market-protection, MIS, NFO)"
                ),
                update_callback,
            )

            entry_order_id = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: self.zs.kite.place_order(
                    variety=self.zs.kite.VARIETY_REGULAR,
                    exchange=self.zs.kite.EXCHANGE_NFO,
                    tradingsymbol=option_symbol,
                    transaction_type=self.zs.kite.TRANSACTION_TYPE_BUY,
                    quantity=quantity,
                    product=self.zs.kite.PRODUCT_MIS,
                    order_type=self.zs.kite.ORDER_TYPE_LIMIT,
                    price=protect_price,
                ),
            )

            execution_log["entry_order_id"] = entry_order_id
            await self._send_update(
                analysis_id, option_symbol, "ORDER_PLACED",
                f"BUY LIMIT order placed: order_id={entry_order_id} @ ₹{protect_price:.2f}. Waiting for fill…",
                update_callback,
            )

            # ── Step 2: Wait for fill ────────────────────────────────────
            fill_price = await self._wait_for_fill(
                entry_order_id, analysis_id, option_symbol, update_callback
            )

            if fill_price is None:
                raise RuntimeError(
                    f"Order {entry_order_id} did not fill within {self.FILL_TIMEOUT}s"
                )

            execution_log["fill_price"] = fill_price
            await self._send_update(
                analysis_id, option_symbol, "ORDER_FILLED",
                f"Filled at ₹{fill_price:.2f} premium. Placing SL-M order…",
                update_callback,
            )

            # ── Step 3: Derive SL from analysis-recommended levels ──────
            # Prefer the analysis SL adjusted for actual fill slippage.
            # This keeps the monitoring levels consistent with what the
            # user saw on the analysis screen.
            if entry_premium > 0 and stop_loss_premium < entry_premium:
                sl_ratio = stop_loss_premium / entry_premium
                raw_sl = fill_price * sl_ratio
            else:
                sl_ratio = 0.75
                raw_sl = fill_price * 0.75

            # Hard rule: SL trigger MUST be strictly below fill price.
            # Cap at fill * 0.97, then snap DOWN to nearest NFO tick (0.05).
            raw_sl = min(raw_sl, fill_price * 0.97)
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

            # ── Step 5: Place LIMIT SELL order at target ────────────────
            # GTT is not supported for MIS options. Place a regular LIMIT SELL.
            # WARNING: both SL and target orders are live simultaneously —
            # whichever fills first, the other must be cancelled manually.
            target_order_id = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: self.zs.kite.place_order(
                    variety=self.zs.kite.VARIETY_REGULAR,
                    exchange=self.zs.kite.EXCHANGE_NFO,
                    tradingsymbol=option_symbol,
                    transaction_type=self.zs.kite.TRANSACTION_TYPE_SELL,
                    quantity=quantity,
                    product=self.zs.kite.PRODUCT_MIS,
                    order_type=self.zs.kite.ORDER_TYPE_LIMIT,
                    price=adjusted_target,
                ),
            )

            execution_log["target_order_id"] = target_order_id
            execution_log["target_price"] = adjusted_target
            execution_log["status"] = "COMPLETED"
            await self._send_update(
                analysis_id, option_symbol, "COMPLETED",
                (
                    f"Trade active! Fill=₹{fill_price:.2f} | "
                    f"SL trigger=₹{adjusted_sl:.2f} limit=₹{sl_limit_price:.2f} (order {sl_order_id}) | "
                    f"Target=₹{adjusted_target:.2f} limit sell placed (order {target_order_id}). "
                    f"⚠️ Cancel whichever order doesn't hit. Auto square-off at 3:15 PM."
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
        Return the limit price for an SL (stop-loss limit) SELL order.
        Set 2% below the trigger, rounded down to the nearest NFO tick (0.05).
        This ensures the order fills after the trigger is hit even with a gap.
        """
        raw = trigger * (1 - self.MARKET_PROTECTION_PCT)
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

    async def _wait_for_fill(
        self,
        order_id: str,
        analysis_id: str,
        symbol: str,
        update_callback: Optional[Callable],
    ) -> Optional[float]:
        """
        Poll order status until COMPLETE or timeout.
        Returns fill price (average_price) or None on timeout.
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
                            f"[OptionsExecution] {symbol} order {order_id} filled @ ₹{avg_price:.2f}"
                        )
                        return avg_price
                    elif status in ("REJECTED", "CANCELLED"):
                        logger.error(
                            f"[OptionsExecution] Order {order_id} {status}: "
                            f"{order.get('status_message', '')}"
                        )
                        return None
            except Exception as e:
                logger.warning(f"[OptionsExecution] Status poll error: {e}")

        logger.error(
            f"[OptionsExecution] Order {order_id} timeout after {self.FILL_TIMEOUT}s"
        )
        return None

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
