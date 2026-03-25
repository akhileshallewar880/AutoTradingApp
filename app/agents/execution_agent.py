import uuid
import asyncio
from app.core.logging import logger
from app.services.zerodha_service import zerodha_service
from app.services.order_service import order_service, MarketClosedException
from app.models.analysis_models import ExecutionUpdate
from typing import List, Dict, Callable, Tuple
from datetime import datetime


class ExecutionAgent:
    """
    Agent responsible for executing trades and managing orders.

    Workflow:
      1. Place entry order  (BUY for long / SELL for short-sell) via MIS or CNC
      2. Wait for order fill — captures actual fill price
      3. Recalculate SL/target if fill price deviates from expected entry price
      4. Fetch live LTP for accurate GTT last_price
      5. Validate GTT trigger prices make sense vs current market price
      6. Place GTT with adjusted prices
    """

    def __init__(self):
        self.zs = zerodha_service
        self.os = order_service

    async def execute_trade_with_gtt(
        self,
        stock_symbol: str,
        quantity: int,
        entry_price: float,
        stop_loss: float,
        target: float,
        analysis_id: str,
        access_token: str,
        api_key: str,
        update_callback: Callable = None,
        hold_duration_days: int = 0,
        action: str = "BUY",
        sl_only: bool = False,
    ) -> Dict:
        """
        sl_only=True  → place single-leg SL-only GTT (used with multi-target strategy
                         where T1/T2 exits are managed by the agent, not GTT).
        sl_only=False → place two-leg GTT with SL + target (legacy/single-target mode).
        """
        is_intraday = hold_duration_days == 0
        product = "MIS" if is_intraday else "CNC"
        is_short = action == "SELL"

        execution_log = {
            "stock_symbol": stock_symbol,
            "action": action,
            "status": "STARTED",
            "entry_order_id": None,
            "gtt_order_id": None,
            "updates": [],
        }

        # Reinitialize kite with this user's api_key + access_token.
        self.zs.set_credentials(api_key, access_token)

        try:
            # ── Step 1: Place LIMIT entry order ────────────────────────────
            # LIMIT order at the AI-recommended entry price ensures we get
            # exactly the price the analysis was based on, with no slippage.
            # The agent waits for the fill; if price never reaches the limit
            # within the timeout the order is cancelled automatically.
            entry_label = "SHORT SELL" if is_short else "BUY"
            await self._send_update(
                analysis_id,
                stock_symbol,
                "ORDER_PLACING",
                (
                    f"Placing {entry_label} LIMIT order — "
                    f"{quantity} shares @ ₹{entry_price:.2f} ({product}). "
                    f"Waiting for price to reach ₹{entry_price:.2f}…"
                ),
                update_callback,
            )

            entry_order_id = await self.os.execute_trade(
                symbol=stock_symbol,
                quantity=quantity,
                price=entry_price,
                stop_loss=stop_loss,
                target=target,
                product=product,
                transaction_type=action,
                order_type="LIMIT",
            )

            execution_log["entry_order_id"] = entry_order_id

            await self._send_update(
                analysis_id,
                stock_symbol,
                "ORDER_PLACED",
                (
                    f"{entry_label} LIMIT order placed @ ₹{entry_price:.2f}. "
                    f"Order ID: {entry_order_id} — monitoring for fill…"
                ),
                update_callback,
                order_id=entry_order_id,
            )

            # ── Step 2: Monitor until filled ───────────────────────────────
            is_filled, fill_info = await self._wait_for_order_fill(entry_order_id, timeout=300)

            if not is_filled:
                final_status = fill_info.get("status", "TIMEOUT").upper()
                reason = fill_info.get("status_message", "")

                if final_status in ("CANCELLED", "REJECTED"):
                    update_type = "ORDER_REJECTED"
                    msg = (
                        f"Order {final_status}"
                        + (f": {reason}" if reason else "")
                        + ". No position opened."
                    )
                    log_status = "REJECTED"
                else:
                    # Limit order not filled within 5 min — cancel it so it
                    # doesn't fill later when we're no longer monitoring.
                    update_type = "ORDER_TIMEOUT"
                    log_status = "TIMEOUT"
                    try:
                        await self.zs.cancel_order(entry_order_id)
                        msg = (
                            f"Price did not reach ₹{entry_price:.2f} within 5 minutes. "
                            f"Limit order cancelled — no position opened."
                        )
                    except Exception as cancel_err:
                        logger.warning(
                            f"{stock_symbol}: cancel after timeout failed: {cancel_err}"
                        )
                        msg = (
                            f"Price did not reach ₹{entry_price:.2f} within 5 minutes. "
                            f"Order may still be pending — check Zerodha app and cancel manually "
                            f"if needed. Order ID: {entry_order_id}"
                        )

                await self._send_update(
                    analysis_id, stock_symbol, update_type, msg, update_callback,
                    order_id=entry_order_id,
                )
                execution_log["status"] = log_status
                execution_log["error"] = msg
                return execution_log

            # ── Step 3: Reconcile fill price ───────────────────────────────
            actual_fill = fill_info.get("average_price", 0.0)
            gtt_stop_loss = stop_loss
            gtt_target = target

            if actual_fill > 0:
                deviation_pct = abs(actual_fill - entry_price) / entry_price * 100
                sl_distance = abs(stop_loss - entry_price)
                target_distance = abs(target - entry_price)

                if deviation_pct > 0.2:  # >0.2% deviation — recalculate GTT prices
                    if is_short:
                        gtt_stop_loss = round(actual_fill + sl_distance, 2)
                        gtt_target = round(actual_fill - target_distance, 2)
                    else:
                        gtt_stop_loss = round(actual_fill - sl_distance, 2)
                        gtt_target = round(actual_fill + target_distance, 2)

                    await self._send_update(
                        analysis_id,
                        stock_symbol,
                        "ORDER_FILLED",
                        (
                            f"{entry_label} filled @ ₹{actual_fill:.2f} "
                            f"(expected ₹{entry_price:.2f}, deviation {deviation_pct:.2f}%). "
                            f"GTT recalculated — SL: ₹{gtt_stop_loss:.2f}, "
                            f"Target: ₹{gtt_target:.2f}"
                        ),
                        update_callback,
                        order_id=entry_order_id,
                    )
                    logger.info(
                        f"{stock_symbol} fill deviation {deviation_pct:.2f}%: "
                        f"expected ₹{entry_price:.2f}, filled ₹{actual_fill:.2f}. "
                        f"GTT SL ₹{gtt_stop_loss:.2f}, Target ₹{gtt_target:.2f}"
                    )
                else:
                    await self._send_update(
                        analysis_id,
                        stock_symbol,
                        "ORDER_FILLED",
                        f"{entry_label} order filled @ ₹{actual_fill:.2f}",
                        update_callback,
                        order_id=entry_order_id,
                    )
            else:
                actual_fill = entry_price
                await self._send_update(
                    analysis_id,
                    stock_symbol,
                    "ORDER_FILLED",
                    f"{entry_label} order filled @ ₹{entry_price:.2f}",
                    update_callback,
                    order_id=entry_order_id,
                )

            # ── Step 4: Fetch live price for accurate GTT last_price ──────
            # Try kite.ltp() first (lighter); fall back to kite.quote() if
            # the account doesn't have the paid data subscription.
            # Using a stale fill price risks the GTT triggering immediately
            # if the market has moved past the SL since the order filled.
            gtt_last_price = actual_fill  # final fallback
            live_price_source = "fill"
            try:
                ltp_data = await self.zs.get_ltp([stock_symbol])
                ltp_key = f"NSE:{stock_symbol}"
                live_ltp = ltp_data.get(ltp_key, {}).get("last_price", 0.0)
                if live_ltp > 0:
                    gtt_last_price = live_ltp
                    live_price_source = "ltp"
            except Exception:
                # kite.ltp() needs paid plan — try kite.quote() instead
                try:
                    quote_data = await self.zs.get_quote([stock_symbol])
                    quote_key = f"NSE:{stock_symbol}"
                    live_quote = quote_data.get(quote_key, {}).get("last_price", 0.0)
                    if live_quote > 0:
                        gtt_last_price = live_quote
                        live_price_source = "quote"
                except Exception as quote_err:
                    logger.warning(
                        f"{stock_symbol}: both LTP and quote fetch failed — "
                        f"using fill price ₹{actual_fill:.2f} as GTT last_price. "
                        f"Error: {quote_err}"
                    )

            logger.info(
                f"{stock_symbol}: GTT last_price=₹{gtt_last_price:.2f} "
                f"(source={live_price_source}, fill=₹{actual_fill:.2f})"
            )

            # ── Step 5: Validate GTT trigger prices vs live market ─────────
            gtt_stop_loss, gtt_target, price_warn = self._validate_and_fix_gtt_prices(
                stock_symbol=stock_symbol,
                is_short=is_short,
                stop_loss=gtt_stop_loss,
                target=gtt_target,
                last_price=gtt_last_price,
            )

            if price_warn:
                await self._send_update(
                    analysis_id, stock_symbol, "GTT_PRICE_ADJUSTED",
                    price_warn, update_callback,
                )

            # ── Step 6: Place GTT ──────────────────────────────────────────
            if is_short:
                gtt_desc = (
                    f"Placing GTT (SHORT cover): "
                    f"target ₹{gtt_target:.2f} (profit), SL ₹{gtt_stop_loss:.2f} (loss cap)"
                )
            else:
                gtt_desc = (
                    f"Placing GTT: SL ₹{gtt_stop_loss:.2f}, Target ₹{gtt_target:.2f}"
                )

            await self._send_update(
                analysis_id, stock_symbol, "GTT_PLACING", gtt_desc, update_callback
            )

            try:
                if sl_only:
                    gtt_id = await self._place_sl_gtt(
                        symbol=stock_symbol,
                        quantity=quantity,
                        last_price=gtt_last_price,
                        stop_loss=gtt_stop_loss,
                        product=product,
                        is_short=is_short,
                    )
                else:
                    gtt_id = await self._place_gtt_order(
                        symbol=stock_symbol,
                        quantity=quantity,
                        last_price=gtt_last_price,
                        stop_loss=gtt_stop_loss,
                        target=gtt_target,
                        product=product,
                        is_short=is_short,
                    )
            except Exception as gtt_err:
                logger.error(
                    f"{stock_symbol} GTT failed | "
                    f"last_price=₹{gtt_last_price:.2f} "
                    f"sl=₹{gtt_stop_loss:.2f} target=₹{gtt_target:.2f} "
                    f"product={product} is_short={is_short} | "
                    f"error: {gtt_err}"
                )

                if is_intraday:
                    # Intraday: MIS auto-squares at 3:15 PM — do NOT squareoff manually.
                    # Just warn the user to set SL/target manually if needed.
                    warn_msg = (
                        f"⚠ GTT placement failed: {gtt_err}. "
                        f"Position is OPEN (MIS — auto-squares off at 3:15 PM IST). "
                        f"Set SL ₹{gtt_stop_loss:.2f} / Target ₹{gtt_target:.2f} manually "
                        f"in your Zerodha app if needed."
                    )
                    await self._send_update(
                        analysis_id, stock_symbol, "GTT_FAILED", warn_msg, update_callback,
                    )
                    execution_log["status"] = "GTT_FAILED"
                    execution_log["error"] = str(gtt_err)
                    execution_log["gtt_order_id"] = None
                else:
                    # Swing (CNC): unprotected overnight position — squareoff immediately.
                    await self._send_update(
                        analysis_id, stock_symbol, "GTT_FAILED",
                        f"GTT failed: {gtt_err}. Squaring off to avoid unprotected overnight position…",
                        update_callback,
                    )
                    execution_log["gtt_order_id"] = None
                    exit_transaction = "BUY" if is_short else "SELL"
                    try:
                        exit_order_id = await self.os.execute_trade(
                            symbol=stock_symbol,
                            quantity=quantity,
                            price=0,
                            stop_loss=0,
                            target=0,
                            product=product,
                            transaction_type=exit_transaction,
                            order_type="MARKET",
                        )
                        logger.info(
                            f"{stock_symbol} squared off after GTT failure — "
                            f"{exit_transaction} {quantity} MARKET. Order: {exit_order_id}"
                        )
                        await self._send_update(
                            analysis_id, stock_symbol, "SQUAREDOFF",
                            (
                                f"Position squared off ({exit_transaction} {quantity} @ MARKET). "
                                f"Exit Order ID: {exit_order_id}. No open position."
                            ),
                            update_callback,
                            order_id=exit_order_id,
                        )
                        execution_log["status"] = "SQUAREDOFF"
                        execution_log["error"] = f"GTT failed ({gtt_err}); auto square-off placed."
                    except Exception as sq_err:
                        critical_msg = (
                            f"⚠ GTT FAILED AND AUTO SQUARE-OFF ALSO FAILED: {sq_err}. "
                            f"YOU HAVE AN OPEN {entry_label} POSITION OF {quantity} SHARES IN "
                            f"{stock_symbol}. EXIT MANUALLY IN ZERODHA IMMEDIATELY!"
                        )
                        logger.critical(f"{stock_symbol} SQUARE-OFF FAILED: {sq_err}")
                        await self._send_update(
                            analysis_id, stock_symbol, "SQUAREOFF_FAILED",
                            critical_msg, update_callback,
                        )
                        execution_log["status"] = "SQUAREOFF_FAILED"
                        execution_log["error"] = (
                            f"GTT failed ({gtt_err}); square-off also failed ({sq_err})"
                        )
                return execution_log

            execution_log["gtt_order_id"] = gtt_id

            gtt_note = ""
            if is_intraday:
                gtt_note = (
                    " ⚠ MIS positions auto-square-off at 3:15 PM IST. "
                    "Cancel this GTT if auto-squareoff occurs first."
                )

            await self._send_update(
                analysis_id,
                stock_symbol,
                "GTT_PLACED",
                f"GTT placed successfully. GTT ID: {gtt_id}.{gtt_note}",
                update_callback,
                order_id=str(gtt_id),
            )

            execution_log["status"] = "COMPLETED"

            await self._send_update(
                analysis_id,
                stock_symbol,
                "COMPLETED",
                f"Trade execution completed — {stock_symbol} {entry_label} {product}",
                update_callback,
            )

            return execution_log

        except MarketClosedException as e:
            logger.warning(f"Market closed during execution of {stock_symbol}: {e}")
            await self._send_update(
                analysis_id, stock_symbol, "MARKET_CLOSED", str(e), update_callback
            )
            execution_log["status"] = "MARKET_CLOSED"
            execution_log["error"] = str(e)
            return execution_log

        except Exception as e:
            logger.error(f"Trade execution failed for {stock_symbol}: {e}")
            await self._send_update(
                analysis_id,
                stock_symbol,
                "ERROR",
                f"Execution failed: {str(e)}",
                update_callback,
            )
            execution_log["status"] = "FAILED"
            execution_log["error"] = str(e)
            return execution_log

    # ── GTT price validation ───────────────────────────────────────────────────

    def _validate_and_fix_gtt_prices(
        self,
        stock_symbol: str,
        is_short: bool,
        stop_loss: float,
        target: float,
        last_price: float,
    ) -> Tuple[float, float, str]:
        """
        Validate GTT trigger prices against the current market price.
        Zerodha requires: for LONG → sl < last_price < target
                          for SHORT → target < last_price < sl

        Returns (adjusted_sl, adjusted_target, warning_message).
        warning_message is empty string if no adjustment was needed.
        """
        if last_price <= 0:
            return stop_loss, target, ""

        warn = ""

        if is_short:
            # SHORT: target < last_price < stop_loss
            valid = target < last_price < stop_loss
            if not valid:
                old_sl, old_tgt = stop_loss, target
                # Recalculate symmetrically around last_price
                avg_distance = (abs(stop_loss - target)) / 2
                stop_loss = round(last_price + avg_distance * 0.4, 2)
                target = round(last_price - avg_distance * 0.6, 2)
                warn = (
                    f"GTT prices invalid for current market ₹{last_price:.2f} "
                    f"(SHORT needs target < price < SL). "
                    f"Adjusted: SL ₹{old_sl:.2f}→₹{stop_loss:.2f}, "
                    f"Target ₹{old_tgt:.2f}→₹{target:.2f}."
                )
                logger.warning(f"{stock_symbol}: {warn}")
        else:
            # LONG: stop_loss < last_price < target
            valid = stop_loss < last_price < target
            if not valid:
                old_sl, old_tgt = stop_loss, target
                avg_distance = abs(target - stop_loss) / 2
                stop_loss = round(last_price - avg_distance * 0.4, 2)
                target = round(last_price + avg_distance * 0.6, 2)
                warn = (
                    f"GTT prices invalid for current market ₹{last_price:.2f} "
                    f"(LONG needs SL < price < target). "
                    f"Adjusted: SL ₹{old_sl:.2f}→₹{stop_loss:.2f}, "
                    f"Target ₹{old_tgt:.2f}→₹{target:.2f}."
                )
                logger.warning(f"{stock_symbol}: {warn}")

        return stop_loss, target, warn

    # ── GTT placement ─────────────────────────────────────────────────────────

    async def _place_gtt_order(
        self,
        symbol: str,
        quantity: int,
        last_price: float,
        stop_loss: float,
        target: float,
        product: str,
        is_short: bool = False,
    ) -> str:
        """
        Place a two-leg GTT (One-Cancels-Other) for long or short positions.

        Long  (BUY entry):
          trigger_values = [stop_loss, target]  (lower = SL, upper = target)
          GTT orders: SELL at stop_loss + SELL at target

        Short (SELL entry):
          trigger_values = [target, stop_loss]  (lower = profit target, upper = SL)
          GTT orders: BUY at target (cover profit) + BUY at stop_loss (cover loss)
        """
        if is_short:
            # Short: target < last_price < stop_loss
            trigger_values = sorted([target, stop_loss])
            orders = [
                {
                    "transaction_type": "BUY",
                    "quantity": quantity,
                    "order_type": "LIMIT",
                    "product": product,
                    "price": target,     # cover at target = profit
                },
                {
                    "transaction_type": "BUY",
                    "quantity": quantity,
                    "order_type": "LIMIT",
                    "product": product,
                    "price": stop_loss,  # cover at stop_loss = loss cap
                },
            ]
        else:
            # Long: stop_loss < last_price < target
            trigger_values = sorted([stop_loss, target])
            orders = [
                {
                    "transaction_type": "SELL",
                    "quantity": quantity,
                    "order_type": "LIMIT",
                    "product": product,
                    "price": stop_loss,  # exit at SL = loss protection
                },
                {
                    "transaction_type": "SELL",
                    "quantity": quantity,
                    "order_type": "LIMIT",
                    "product": product,
                    "price": target,     # exit at target = profit
                },
            ]

        gtt_id = await self.zs.place_gtt(
            tradingsymbol=symbol,
            exchange="NSE",
            trigger_values=trigger_values,
            last_price=last_price,
            orders=orders,
            gtt_type="two-leg",
        )
        return gtt_id

    async def _place_sl_gtt(
        self,
        symbol: str,
        quantity: int,
        last_price: float,
        stop_loss: float,
        product: str,
        is_short: bool = False,
    ) -> str:
        """
        Place a single-leg SL-only GTT.
        Used with the multi-target (scaling-out) strategy where partial target exits
        are executed directly by the agent via MARKET orders.
        """
        txn = "BUY" if is_short else "SELL"
        orders = [
            {
                "transaction_type": txn,
                "quantity": quantity,
                "order_type": "LIMIT",
                "product": product,
                "price": stop_loss,
            }
        ]
        gtt_id = await self.zs.place_gtt(
            tradingsymbol=symbol,
            exchange="NSE",
            trigger_values=[stop_loss],
            last_price=last_price,
            orders=orders,
            gtt_type="single",
        )
        return gtt_id

    # ── Order monitoring ──────────────────────────────────────────────────────

    async def _wait_for_order_fill(
        self, order_id: str, timeout: int = 300
    ) -> Tuple[bool, dict]:
        """
        Poll until order is COMPLETE, CANCELLED, or REJECTED, or timeout.

        Returns:
            (True,  {"average_price": float, "status": "COMPLETE", ...})  on fill
            (False, {"status": "CANCELLED"/"REJECTED"/"TIMEOUT", "status_message": str})  otherwise
        """
        start_time = asyncio.get_event_loop().time()
        poll_interval = 2
        last_order_detail: dict = {}

        while asyncio.get_event_loop().time() - start_time < timeout:
            try:
                order_detail = await self.zs.get_order_status(order_id)
                last_order_detail = order_detail
                status = order_detail.get("status", "").upper()
                logger.info(f"Order {order_id} status: {status}")

                if status == "COMPLETE":
                    return True, order_detail
                elif status in ("CANCELLED", "REJECTED"):
                    logger.warning(
                        f"Order {order_id} {status}: "
                        f"{order_detail.get('status_message', '')}"
                    )
                    return False, order_detail

                await asyncio.sleep(poll_interval)

            except Exception as e:
                logger.error(f"Error checking order status: {e}")
                await asyncio.sleep(poll_interval)

        last_order_detail["status"] = "TIMEOUT"
        return False, last_order_detail

    # ── Update helper ─────────────────────────────────────────────────────────

    async def _send_update(
        self,
        analysis_id: str,
        stock_symbol: str,
        update_type: str,
        message: str,
        callback: Callable = None,
        order_id: str = None,
    ):
        if callback:
            update = ExecutionUpdate(
                analysis_id=analysis_id,
                stock_symbol=stock_symbol,
                update_type=update_type,
                message=message,
                order_id=order_id,
            )
            await callback(update)


execution_agent = ExecutionAgent()
