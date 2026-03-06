import uuid
import asyncio
from app.core.logging import logger
from app.services.zerodha_service import zerodha_service
from app.services.order_service import order_service, MarketClosedException
from app.models.analysis_models import ExecutionUpdate
from typing import List, Dict, Callable
from datetime import datetime


class ExecutionAgent:
    """
    Agent responsible for executing trades and managing orders.

    Workflow:
      1. Place entry order  (BUY for long / SELL for short-sell) via MIS or CNC
      2. Wait for order fill
      3. Place GTT (Good Till Triggered) with stop-loss + target for both MIS and CNC
         - Long  (BUY entry) : GTT SELL orders — stop-loss leg + target leg
         - Short (SELL entry): GTT BUY  orders — target leg (cover profit) + SL leg
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
    ) -> Dict:
        """
        Execute a complete trade workflow:
          1. Place entry order  (BUY or SELL/short)
          2. Monitor until filled
          3. Place GTT with stop-loss + target (works for both MIS and CNC)

        Args:
            action           : "BUY" (long) or "SELL" (intraday short sell)
            hold_duration_days: 0 → MIS (intraday); >0 → CNC (delivery)
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
        # Critical for multi-user: api_key and access_token must be from the same account.
        self.zs.set_credentials(api_key, access_token)

        try:
            # ── Step 1: Place entry order ──────────────────────────────────
            entry_label = "SHORT SELL" if is_short else "BUY"
            await self._send_update(
                analysis_id,
                stock_symbol,
                "ORDER_PLACING",
                f"Placing {entry_label} {product} order for {quantity} shares @ ₹{entry_price:.2f}",
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
            )

            execution_log["entry_order_id"] = entry_order_id

            await self._send_update(
                analysis_id,
                stock_symbol,
                "ORDER_PLACED",
                f"{entry_label} order placed. Order ID: {entry_order_id}",
                update_callback,
                order_id=entry_order_id,
            )

            # ── Step 2: Monitor until filled ───────────────────────────────
            await self._send_update(
                analysis_id,
                stock_symbol,
                "ORDER_MONITORING",
                "Monitoring order status…",
                update_callback,
                order_id=entry_order_id,
            )

            is_filled = await self._wait_for_order_fill(entry_order_id, timeout=300)

            if not is_filled:
                await self._send_update(
                    analysis_id,
                    stock_symbol,
                    "ORDER_TIMEOUT",
                    "Order not filled within timeout — GTT not placed.",
                    update_callback,
                    order_id=entry_order_id,
                )
                execution_log["status"] = "TIMEOUT"
                return execution_log

            await self._send_update(
                analysis_id,
                stock_symbol,
                "ORDER_FILLED",
                f"{entry_label} order filled at ₹{entry_price:.2f}",
                update_callback,
                order_id=entry_order_id,
            )

            # ── Step 3: Place GTT (for both MIS and CNC) ──────────────────
            if is_short:
                gtt_desc = (
                    f"Placing GTT (SHORT cover): "
                    f"target ₹{target:.2f} (profit), SL ₹{stop_loss:.2f} (loss cap)"
                )
            else:
                gtt_desc = (
                    f"Placing GTT: SL ₹{stop_loss:.2f}, Target ₹{target:.2f}"
                )

            await self._send_update(
                analysis_id, stock_symbol, "GTT_PLACING", gtt_desc, update_callback
            )

            gtt_id = await self._place_gtt_order(
                symbol=stock_symbol,
                quantity=quantity,
                entry_price=entry_price,
                stop_loss=stop_loss,
                target=target,
                product=product,
                is_short=is_short,
            )

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

    # ── GTT placement ─────────────────────────────────────────────────────────

    async def _place_gtt_order(
        self,
        symbol: str,
        quantity: int,
        entry_price: float,
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
            # Short: target < entry < stop_loss
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
            # Long: stop_loss < entry < target
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
            last_price=entry_price,
            orders=orders,
            gtt_type="two-leg",
        )
        return gtt_id

    # ── Order monitoring ──────────────────────────────────────────────────────

    async def _wait_for_order_fill(self, order_id: str, timeout: int = 300) -> bool:
        start_time = asyncio.get_event_loop().time()
        poll_interval = 2

        while asyncio.get_event_loop().time() - start_time < timeout:
            try:
                order_status = await self.zs.get_order_status(order_id)
                status = order_status.get("status", "").upper()
                logger.info(f"Order {order_id} status: {status}")

                if status == "COMPLETE":
                    return True
                elif status in ["CANCELLED", "REJECTED"]:
                    logger.warning(f"Order {order_id} was {status}")
                    return False

                await asyncio.sleep(poll_interval)

            except Exception as e:
                logger.error(f"Error checking order status: {e}")
                await asyncio.sleep(poll_interval)

        return False

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
