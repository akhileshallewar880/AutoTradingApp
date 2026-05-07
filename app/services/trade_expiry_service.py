"""
Swing Trade Expiry Service.

Runs as a background asyncio task (started at app startup).
Every weekday at 9:15 AM IST it queries vantrade_swing_positions for any
OPEN positions whose hold period has elapsed (expiry_date <= today).

For each expired position it:
  1. Marks the position as HOLD_ENDED in DB (prevents reprocessing).
  2. Logs a prominent warning that the user must exit manually.

NO automatic exit order is placed.  The GTT remains active.
The user is notified via in-app banner (holdings screen) and push notification.
"""
import asyncio
from datetime import datetime, timedelta
from app.core.logging import logger
from app.storage.database import db


class TradeExpiryService:
    """Background scheduler that flags expired swing positions for manual exit."""

    async def run_scheduler(self):
        logger.info("[ExpiryService] Swing trade expiry scheduler started")
        while True:
            try:
                await self._wait_until_next_market_open()
                # Wait 2 extra minutes so AMO fills settle before we query them
                await asyncio.sleep(120)
                await self._process_amo_pending_positions()
                await self._flag_expired_positions()
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

    async def _flag_expired_positions(self):
        """
        Mark positions whose hold duration has elapsed as HOLD_ENDED.
        Does NOT place any exit order — the user must exit manually via the app.
        """
        expired = await db.get_expired_swing_positions()
        if not expired:
            logger.info("[ExpiryService] No expired swing positions today")
            return

        logger.warning(
            f"[ExpiryService] {len(expired)} position(s) have reached their "
            "hold duration. Flagging as HOLD_ENDED — NO automatic exit placed. "
            "Users must exit via the app."
        )
        for pos in expired:
            await self._flag_one_position(pos)

    async def _flag_one_position(self, pos: dict):
        """
        Mark a single expired position as HOLD_ENDED.
        The GTT remains active — if the user doesn't exit, the GTT still protects them.
        """
        symbol      = pos.get("stock_symbol", "")
        position_id = pos.get("id")
        hold_days   = pos.get("hold_duration_days", 0)

        logger.warning(
            f"[ExpiryService] HOLD ENDED: {symbol} held {hold_days}d — "
            "marking HOLD_ENDED, GTT kept active, NO exit order placed. "
            "User should exit via the Holdings screen."
        )

        try:
            await db.mark_swing_position_hold_ended(position_id)
        except Exception as e:
            logger.error(
                f"[ExpiryService] Failed to flag {symbol} (id={position_id}) "
                f"as HOLD_ENDED: {e}"
            )


trade_expiry_service = TradeExpiryService()
