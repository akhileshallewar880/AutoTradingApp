from app.services.zerodha_service import zerodha_service
from app.core.logging import logger
from datetime import datetime, time
import pytz


class MarketClosedException(Exception):
    """Raised when an order is attempted outside NSE market hours (and AMO is unavailable)."""
    pass


class AmoOrderPlaced(Exception):
    """
    Raised (as a signal, not an error) when an order is placed as AMO.
    Caught by execution_agent to skip the fill-waiting loop.
    """
    def __init__(self, order_id: str, message: str):
        super().__init__(message)
        self.order_id = order_id


class OrderService:
    """
    Service for placing orders via Zerodha.

    Market hours:  Mon–Fri, 09:15–15:30 IST  → regular variety
    AMO window:    Mon–Fri, 15:45–08:57 IST  → variety="amo" (CNC only)
    """

    MARKET_OPEN  = time(9, 15)
    MARKET_CLOSE = time(15, 30)
    AMO_START    = time(15, 45)   # AMO accepts orders from 3:45 PM
    AMO_END      = time(8, 57)    # AMO closes at 8:57 AM (pre-market)
    IST = pytz.timezone("Asia/Kolkata")

    def __init__(self):
        self.zs = zerodha_service

    def is_market_open(self) -> bool:
        now_ist = datetime.now(self.IST)
        if now_ist.weekday() >= 5:
            return False
        current_time = now_ist.time()
        return self.MARKET_OPEN <= current_time <= self.MARKET_CLOSE

    def is_amo_window(self) -> bool:
        """
        True when Zerodha's AMO window is open.

        Weekends (Sat/Sun): ALL day — Zerodha accepts AMO orders on weekends
          and executes them at the following Monday's market open.
        Weekdays: 3:45 PM – 8:57 AM (after market close until pre-market).
          The 9:00–9:14 AM gap is also covered so that early-morning users
          are not blocked between AMO close and market open.
        """
        now_ist = datetime.now(self.IST)
        weekday = now_ist.weekday()

        # Weekends: always allow AMO (executes next trading day)
        if weekday >= 5:
            return True

        # Weekdays: after 3:45 PM OR before 9:15 AM (covers full non-market window)
        ct = now_ist.time()
        return ct >= self.AMO_START or ct < self.MARKET_OPEN

    def market_status_message(self) -> str:
        now_ist = datetime.now(self.IST)
        weekday = now_ist.weekday()
        current_time = now_ist.time()
        time_str = current_time.strftime('%I:%M %p')

        if weekday >= 5:
            day_name = "Saturday" if weekday == 5 else "Sunday"
            return (
                f"Market is closed today ({day_name}). "
                "Intraday orders require market hours (Mon–Fri 9:15 AM – 3:30 PM IST). "
                "Swing CNC orders can be placed as AMO (executes Monday morning)."
            )
        elif current_time < self.MARKET_OPEN:
            return (
                f"Market has not opened yet (current: {time_str} IST). "
                f"NSE opens at 9:15 AM IST. "
                "Swing CNC orders can be placed as AMO (executes at market open today)."
            )
        elif current_time > self.MARKET_CLOSE:
            return (
                f"Market is closed for today (current: {time_str} IST). "
                f"NSE closed at 3:30 PM IST. "
                "Intraday orders must wait for tomorrow's market open. "
                "Swing CNC orders can be placed as AMO."
            )
        return "Market is open."

    async def execute_trade(
        self,
        symbol: str,
        quantity: int,
        price: float,
        stop_loss: float,
        target: float,
        product: str = "CNC",
        transaction_type: str = "BUY",
        order_type: str = "LIMIT",
    ) -> str:
        """
        Execute an entry order via Zerodha.

        During market hours: places a regular LIMIT/MARKET order.
        After market hours (CNC only): places an AMO (After Market Order) that
          executes at the next trading session's market open.  Raises AmoOrderPlaced
          with the order_id so the caller can skip the fill-waiting loop.

        Raises:
            MarketClosedException: market is closed AND AMO is not available.
            AmoOrderPlaced:        CNC order accepted as AMO (not a real error).
        """
        try:
            action_label = "SHORT SELL" if transaction_type == "SELL" else "BUY"
            logger.info(
                f"Placing {order_type} order: {symbol} {action_label} {quantity} "
                f"@ ₹{price} product={product}"
            )

            if not self.is_market_open():
                # CNC swing orders → try AMO during the AMO window
                if product == "CNC" and self.is_amo_window():
                    order_id = await self.zs.place_order(
                        symbol=symbol,
                        transaction_type=transaction_type,
                        quantity=quantity,
                        order_type=order_type,
                        price=price,
                        product=product,
                        exchange="NSE",
                        validity="DAY",
                        variety="amo",
                    )
                    logger.info(
                        f"AMO placed: {symbol} {action_label} {quantity} @ ₹{price} "
                        f"| Order ID: {order_id}"
                    )
                    raise AmoOrderPlaced(
                        order_id=order_id,
                        message=(
                            f"After Market Order placed — {symbol} {action_label} "
                            f"{quantity} shares @ ₹{price:.2f}. "
                            f"Order ID: {order_id}. "
                            f"Will execute at market open (9:15 AM IST next trading day)."
                        ),
                    )

                msg = self.market_status_message()
                logger.warning(f"Order rejected — market closed: {msg}")
                raise MarketClosedException(msg)

            order_id = await self.zs.place_order(
                symbol=symbol,
                transaction_type=transaction_type,
                quantity=quantity,
                order_type=order_type,
                price=price,
                product=product,
                exchange="NSE",
                validity="DAY",
            )
            logger.info(
                f"{'SHORT SELL' if transaction_type == 'SELL' else 'BUY'} {order_type} order "
                f"placed ({product}). Order ID: {order_id}"
            )
            return order_id

        except (MarketClosedException, AmoOrderPlaced):
            raise
        except Exception as e:
            logger.error(f"Error placing order for {symbol}: {e}")
            raise Exception(f"Trade Execution Failed: {str(e)}")


order_service = OrderService()
