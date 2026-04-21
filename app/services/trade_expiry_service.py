"""
Swing Trade Expiry Service.

Runs as a background asyncio task (started at app startup).
Every weekday at 9:15 AM IST it queries vantrade_swing_positions for any
OPEN positions whose hold period has elapsed (expiry_date <= today).
For each expired position it:
  1. Marks the position as EXITING in DB (prevents double-exit).
  2. Cancels the active GTT via Zerodha.
  3. Places a MARKET exit order (SELL for BUY positions, BUY for SELL positions).
  4. Marks the position EXPIRED with the exit order ID.

If the access_token has expired (daily Zerodha token), the exit will fail
and the position is flagged ERROR — the user must exit manually via the
Zerodha app. This is logged as a warning.
"""
import asyncio
from datetime import datetime, timedelta
from app.core.logging import logger
from app.storage.database import db


class TradeExpiryService:
    """Background scheduler that auto-exits expired swing positions."""

    async def run_scheduler(self):
        logger.info("[ExpiryService] Swing trade expiry scheduler started")
        while True:
            try:
                await self._wait_until_next_market_open()
                # Wait 2 extra minutes so AMO fills settle before we query them
                await asyncio.sleep(120)
                await self._process_amo_pending_positions()
                await self._exit_expired_positions()
            except asyncio.CancelledError:
                logger.info("[ExpiryService] Scheduler cancelled")
                break
            except Exception as e:
                logger.error(f"[ExpiryService] Scheduler error: {e}")
                # Back off 1 hour on unexpected error to avoid tight loops
                await asyncio.sleep(3600)

    async def _wait_until_next_market_open(self):
        """Sleep until the next 9:15 AM IST on a weekday."""
        import pytz
        IST = pytz.timezone("Asia/Kolkata")
        while True:
            now = datetime.now(IST)
            # Skip weekends
            if now.weekday() < 5:
                target = now.replace(hour=9, minute=15, second=0, microsecond=0)
                if now < target:
                    secs = (target - now).total_seconds()
                    logger.info(
                        f"[ExpiryService] Next expiry check in "
                        f"{secs/3600:.1f}h (09:15 IST)"
                    )
                    await asyncio.sleep(secs)
                    return
            # Past 9:15 AM today, or weekend — wait until tomorrow 9:15 AM
            next_day = (now + timedelta(days=1)).replace(
                hour=9, minute=15, second=0, microsecond=0
            )
            secs = (next_day - now).total_seconds()
            await asyncio.sleep(secs)

    async def _process_amo_pending_positions(self):
        positions = await db.get_amo_pending_positions()
        if not positions:
            logger.info("[ExpiryService] No AMO_PENDING positions to check")
            return
        logger.info(f"[ExpiryService] Checking {len(positions)} AMO_PENDING position(s) for fills")
        for pos in positions:
            await self._activate_amo_position(pos)

    async def _activate_amo_position(self, pos: dict):
        symbol       = pos.get("stock_symbol", "")
        position_id  = pos.get("id")
        action       = pos.get("action", "BUY")
        quantity     = int(pos.get("quantity", 0) or 0)
        entry_price  = float(pos.get("entry_price", 0) or 0)
        stop_loss    = float(pos.get("stop_loss", 0) or 0)
        target_price = float(pos.get("target_price", 0) or 0)
        entry_order_id = str(pos.get("entry_order_id", "") or "")
        api_key      = pos.get("api_key", "") or ""
        access_token = pos.get("access_token", "") or ""

        logger.info(f"[ExpiryService] Checking AMO fill: {symbol} order={entry_order_id}")

        try:
            from app.services.zerodha_service import zerodha_service
            from app.agents.execution_agent import ExecutionAgent

            zerodha_service.set_credentials(api_key, access_token)

            # Fetch order status from Zerodha
            order = await zerodha_service.get_order_status(entry_order_id)
            status = order.get("status", "").upper()

            if status == "COMPLETE":
                fill_price = float(order.get("average_price") or entry_price)
                logger.info(
                    f"[ExpiryService] AMO filled: {symbol} @ ₹{fill_price:.2f} "
                    f"(expected ₹{entry_price:.2f})"
                )

                # Get live LTP for GTT last_price
                try:
                    quotes = await zerodha_service.get_quote([symbol])
                    nse_key = f"NSE:{symbol}"
                    ltp = float(quotes.get(nse_key, {}).get("last_price", fill_price))
                except Exception:
                    ltp = fill_price

                # Place GTT using execution agent helper
                agent = ExecutionAgent()
                agent.zs = zerodha_service
                is_short = (action == "SELL")
                gtt_id = await agent._place_gtt_order(
                    symbol=symbol,
                    quantity=quantity,
                    last_price=ltp,
                    stop_loss=stop_loss,
                    target=target_price,
                    product="CNC",
                    is_short=is_short,
                )

                await db.mark_swing_position_active(position_id, fill_price, str(gtt_id))
                logger.info(
                    f"[ExpiryService] {symbol} AMO activated — fill=₹{fill_price:.2f}, "
                    f"GTT={gtt_id} | SL=₹{stop_loss:.2f} Target=₹{target_price:.2f}"
                )

            elif status in ("CANCELLED", "REJECTED"):
                logger.warning(
                    f"[ExpiryService] AMO {entry_order_id} for {symbol} was {status}. "
                    "Marking position ERROR."
                )
                await db.mark_swing_position_error(
                    position_id,
                    f"AMO order {status.lower()} by Zerodha (order_id={entry_order_id})"
                )

            else:
                # Still OPEN/TRIGGER PENDING/etc. — leave as AMO_PENDING, check next day
                logger.info(
                    f"[ExpiryService] AMO {entry_order_id} for {symbol} status={status} "
                    "— leaving as AMO_PENDING"
                )

        except Exception as e:
            logger.error(
                f"[ExpiryService] Failed to activate AMO position {symbol} "
                f"(id={position_id}): {e}"
            )

    async def _exit_expired_positions(self):
        expired = await db.get_expired_swing_positions()
        if not expired:
            logger.info("[ExpiryService] No expired swing positions today")
            return
        logger.info(f"[ExpiryService] Auto-exiting {len(expired)} expired position(s)")
        for pos in expired:
            await self._exit_one_position(pos)

    async def _exit_one_position(self, pos: dict):
        symbol       = pos.get("stock_symbol", "")
        position_id  = pos.get("id")
        action       = pos.get("action", "BUY")
        quantity     = int(pos.get("quantity", 0) or 0)
        api_key      = pos.get("api_key", "") or ""
        access_token = pos.get("access_token", "") or ""
        gtt_id       = pos.get("gtt_id")
        hold_days    = pos.get("hold_duration_days", 0)

        exit_action = "SELL" if action == "BUY" else "BUY"
        logger.info(
            f"[ExpiryService] Expiry exit: {symbol} {quantity} shares "
            f"(held {hold_days}d) — placing {exit_action} MARKET"
        )

        # Guard: mark EXITING to prevent double processing on repeated scheduler runs
        await db.mark_swing_position_exiting(position_id)

        try:
            from app.services.zerodha_service import zerodha_service
            from app.services.order_service import order_service

            zerodha_service.set_credentials(api_key, access_token)

            # Step 1: Cancel the GTT so it doesn't trigger after our market exit
            if gtt_id:
                try:
                    zerodha_service.kite.delete_gtt(int(gtt_id))
                    logger.info(f"[ExpiryService] GTT {gtt_id} cancelled for {symbol}")
                except Exception as gtt_err:
                    logger.warning(
                        f"[ExpiryService] Could not cancel GTT {gtt_id} "
                        f"for {symbol}: {gtt_err}"
                    )

            # Step 2: Place MARKET exit order (exit is market, entry was limit)
            exit_order_id = await order_service.execute_trade(
                symbol=symbol,
                quantity=quantity,
                price=0,
                stop_loss=0,
                target=0,
                product="CNC",
                transaction_type=exit_action,
                order_type="MARKET",
            )

            logger.info(
                f"[ExpiryService] {symbol} exited via expiry — "
                f"order {exit_order_id} ({exit_action} {quantity} CNC MARKET)"
            )
            await db.mark_swing_position_expired(position_id, exit_order_id=str(exit_order_id))

        except Exception as e:
            logger.error(
                f"[ExpiryService] Failed to exit {symbol} (id={position_id}): {e}. "
                f"Manual exit required in Zerodha app."
            )
            await db.mark_swing_position_error(position_id, error=str(e))


trade_expiry_service = TradeExpiryService()
