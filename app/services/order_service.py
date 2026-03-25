from app.services.zerodha_service import zerodha_service
from app.core.logging import logger
from datetime import datetime, time
import pytz


class MarketClosedException(Exception):
    """Raised when an order is attempted outside NSE market hours."""
    pass


class OrderService:
    """
    Service for placing orders via Zerodha.

    Market hours: Mon–Fri, 09:15–15:30 IST
    Raises MarketClosedException if called outside these hours.
    """

    MARKET_OPEN = time(9, 15)
    MARKET_CLOSE = time(15, 30)
    IST = pytz.timezone("Asia/Kolkata")

    def __init__(self):
        self.zs = zerodha_service

    def is_market_open(self) -> bool:
        now_ist = datetime.now(self.IST)
        if now_ist.weekday() >= 5:
            return False
        current_time = now_ist.time()
        return self.MARKET_OPEN <= current_time <= self.MARKET_CLOSE

    def market_status_message(self) -> str:
        now_ist = datetime.now(self.IST)
        weekday = now_ist.weekday()
        current_time = now_ist.time()

        if weekday >= 5:
            day_name = "Saturday" if weekday == 5 else "Sunday"
            return (
                f"Market is closed today ({day_name}). "
                "NSE trades Monday–Friday, 9:15 AM – 3:30 PM IST."
            )
        elif current_time < self.MARKET_OPEN:
            return (
                f"Market has not opened yet. "
                f"NSE opens at 9:15 AM IST (current time: {current_time.strftime('%I:%M %p')} IST)."
            )
        elif current_time > self.MARKET_CLOSE:
            return (
                f"Market is closed for today. "
                f"NSE closed at 3:30 PM IST (current time: {current_time.strftime('%I:%M %p')} IST). "
                "Please try again tomorrow during market hours."
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

        Args:
            transaction_type: "BUY"  for long positions
                              "SELL" for short sell positions (intraday only with MIS)
            product:          "MIS"  for intraday (auto-squares off at 3:15 PM)
                              "CNC"  for delivery / long-term
            order_type:       "LIMIT" (default) places at exact entry_price for better fills.
                              "MARKET" for immediate fills (used for squareoff exits).

        Raises:
            MarketClosedException: If called outside NSE market hours.

        Returns:
            Order ID string on success.
        """
        try:
            action_label = "SHORT SELL" if transaction_type == "SELL" else "BUY"
            logger.info(
                f"Placing {order_type} order: {symbol} {action_label} {quantity} "
                f"@ ₹{price} product={product}"
            )

            if not self.is_market_open():
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

        except MarketClosedException:
            raise
        except Exception as e:
            logger.error(f"Error placing order for {symbol}: {e}")
            raise Exception(f"Trade Execution Failed: {str(e)}")


order_service = OrderService()
