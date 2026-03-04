from kiteconnect import KiteConnect
from app.core.config import get_settings
from app.core.logging import logger
import asyncio
from typing import List, Dict, Any, Optional
import hashlib

settings = get_settings()

class ZerodhaService:
    def __init__(self):
        # Use app's registered credentials if available (for backward compatibility)
        self.api_key = settings.ZERODHA_API_KEY.strip() if settings.ZERODHA_API_KEY else None
        self.api_secret = settings.ZERODHA_API_SECRET.strip() if settings.ZERODHA_API_SECRET else None
        self.access_token = settings.ZERODHA_ACCESS_TOKEN

        # Only initialize kite if api_key is available
        if self.api_key:
            self.kite = KiteConnect(api_key=self.api_key)
            logger.info(f"ZerodhaService initialized with api_key length={len(self.api_key)}, api_secret length={len(self.api_secret) if self.api_secret else 0}")
            if self.access_token:
                self.kite.set_access_token(self.access_token)
            else:
                logger.warning("Zerodha Access Token not found! API calls may fail.")
        else:
            self.kite = None
            logger.info("ZerodhaService initialized without app credentials. Per-request methods will be used.")

    def get_login_url(self) -> str:
        """Generate Kite Connect login URL using app's credentials."""
        if not self.kite:
            raise RuntimeError("ZerodhaService not initialized with app credentials")
        login_url = self.kite.login_url()
        logger.info(f"Generated login URL: {login_url}")
        return login_url

    def get_login_url_with_api_key(self, api_key: str) -> str:
        """Generate Kite Connect login URL with user-provided API key."""
        try:
            kite = KiteConnect(api_key=api_key)
            login_url = kite.login_url()
            logger.info(f"Generated login URL for user API key: {login_url}")
            return login_url
        except Exception as e:
            logger.error(f"Error generating login URL with user API key: {e}")
            raise

    async def generate_session(self, request_token: str) -> Dict:
        """
        Exchange request_token for access_token using app credentials.
        Returns session data including access_token, user details, etc.
        """
        if not self.kite:
            raise RuntimeError("ZerodhaService not initialized with app credentials")
        try:
            logger.info(f"Generating session: token_length={len(request_token)}, api_key={self.api_key}, secret_length={len(self.api_secret) if self.api_secret else 0}")
            loop = asyncio.get_event_loop()
            from functools import partial
            data = await loop.run_in_executor(
                None,
                partial(self.kite.generate_session, request_token, api_secret=self.api_secret)
            )
            self.kite.set_access_token(data["access_token"])
            logger.info(f"Session generated successfully for user: {data['user_id']}")
            return data
        except Exception as e:
            import traceback
            logger.error(f"Error generating session: {e}")
            logger.error(traceback.format_exc())
            # If the exception has a response attribute (like requests.exceptions.HTTPError), log it
            if hasattr(e, 'response') and e.response is not None:
                try:
                    logger.error(f"Zerodha API response: {e.response.text}")
                except Exception:
                    pass
            raise

    async def generate_session_with_credentials(self, request_token: str, api_key: str, api_secret: str) -> Dict:
        """
        Exchange request_token for access_token using user-provided credentials.
        Returns session data including access_token, user details, etc.
        """
        try:
            logger.info(f"Generating session with user credentials: token_length={len(request_token)}, api_key_length={len(api_key)}")
            kite = KiteConnect(api_key=api_key)
            loop = asyncio.get_event_loop()
            from functools import partial
            data = await loop.run_in_executor(
                None,
                partial(kite.generate_session, request_token, api_secret=api_secret)
            )
            logger.info(f"Session generated successfully for user: {data['user_id']}")
            return data
        except Exception as e:
            import traceback
            logger.error(f"Error generating session with user credentials: {e}")
            logger.error(traceback.format_exc())
            # If the exception has a response attribute (like requests.exceptions.HTTPError), log it
            if hasattr(e, 'response') and e.response is not None:
                try:
                    logger.error(f"Zerodha API response: {e.response.text}")
                except Exception:
                    pass
            raise

    async def get_profile(self) -> Dict:
        """Get user profile."""
        try:
            loop = asyncio.get_event_loop()
            profile = await loop.run_in_executor(None, self.kite.profile)
            return profile
        except Exception as e:
            logger.error(f"Error fetching profile: {e}")
            raise

    async def invalidate_session(self) -> bool:
        """Logout and invalidate access token."""
        try:
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(None, self.kite.invalidate_access_token)
            logger.info("Session invalidated successfully")
            return True
        except Exception as e:
            logger.error(f"Error invalidating session: {e}")
            raise

    async def get_instruments(self, exchange: str = "NSE") -> List[Dict]:
        """Fetch all instruments for a given exchange."""
        logger.info(f"Fetching instruments for {exchange}")
        # KiteConnect is synchronous, so we run it in a thread
        try:
            loop = asyncio.get_event_loop()
            instruments = await loop.run_in_executor(None, self.kite.instruments, exchange)
            return instruments
        except Exception as e:
            logger.error(f"Error fetching instruments: {e}")
            raise

    async def get_historical_data(self, instrument_token: int, from_date: str, to_date: str, interval: str) -> List[Dict]:
        """Fetch historical data."""
        logger.info(f"Fetching historical data for {instrument_token} from {from_date} to {to_date}")
        try:
            loop = asyncio.get_event_loop()
            data = await loop.run_in_executor(
                None, 
                self.kite.historical_data, 
                instrument_token, 
                from_date, 
                to_date, 
                interval
            )
            return data
        except Exception as e:
            logger.error(f"Error fetching historical data: {e}")
            # return empty list on failure to avoid crashing entire flow, or re-raise based on requirement
            return []

    async def get_margins(self) -> Dict:
        """Fetch account margins."""
        try:
            loop = asyncio.get_event_loop()
            margins = await loop.run_in_executor(None, self.kite.margins)
            return margins
        except Exception as e:
            logger.error(f"Error fetching margins: {e}")
            raise

    async def place_order(self, symbol: str, transaction_type: str, quantity: int, price: float = 0, variety: str = "regular", exchange: str = "NSE", order_type: str = "MARKET", product: str = "MIS", validity: str = "DAY", tag: str = "algo_trade") -> str:
        """Place an order."""
        logger.info(f"Placing order: {symbol} {transaction_type} {quantity} @ {price}")
        try:
            params = {
                "variety": variety,
                "exchange": exchange,
                "tradingsymbol": symbol,
                "transaction_type": transaction_type,
                "quantity": quantity,
                "product": product,
                "order_type": order_type,
                "validity": validity,
                "tag": tag
            }
            if order_type == "LIMIT":
                params["price"] = price

            loop = asyncio.get_event_loop()
            order_id = await loop.run_in_executor(None, lambda: self.kite.place_order(**params))
            logger.info(f"Order placed successfully. ID: {order_id}")
            return order_id
        except Exception as e:
            logger.error(f"Error placing order: {e}")
            raise

    async def get_quote(self, symbols: List[str]) -> Dict:
        """Get real-time quotes for given symbols."""
        try:
            loop = asyncio.get_event_loop()
            # Format symbols with exchange prefix for quote API
            formatted_symbols = [f"NSE:{symbol}" for symbol in symbols]
            quotes = await loop.run_in_executor(None, self.kite.quote, formatted_symbols)
            return quotes
        except Exception as e:
            logger.error(f"Error fetching quotes: {e}")
            raise

    async def get_order_status(self, order_id: str) -> Dict:
        """Get status of a specific order."""
        try:
            loop = asyncio.get_event_loop()
            orders = await loop.run_in_executor(None, self.kite.orders)
            # Find the specific order
            order = next((o for o in orders if o['order_id'] == order_id), None)
            if not order:
                raise ValueError(f"Order {order_id} not found")
            return order
        except Exception as e:
            logger.error(f"Error fetching order status: {e}")
            raise

    async def get_orders(self, access_token: str = None) -> List[Dict]:
        """Fetch all orders for today."""
        try:
            if access_token:
                self.kite.set_access_token(access_token)
            loop = asyncio.get_event_loop()
            orders = await loop.run_in_executor(None, self.kite.orders)
            return orders or []
        except Exception as e:
            logger.error(f"Error fetching orders: {e}")
            raise

    async def get_positions(self, access_token: str = None) -> Dict:
        """Fetch current positions (day + net)."""
        try:
            if access_token:
                self.kite.set_access_token(access_token)
            loop = asyncio.get_event_loop()
            positions = await loop.run_in_executor(None, self.kite.positions)
            return positions or {"day": [], "net": []}
        except Exception as e:
            logger.error(f"Error fetching positions: {e}")
            raise

    async def get_tradebook(self, access_token: str = None) -> List[Dict]:
        """Fetch tradebook (executed trades)."""
        try:
            if access_token:
                self.kite.set_access_token(access_token)
            loop = asyncio.get_event_loop()
            trades = await loop.run_in_executor(None, self.kite.trades)
            return trades or []
        except Exception as e:
            logger.error(f"Error fetching tradebook: {e}")
            raise

    async def get_gtts(self, access_token: str = None) -> List[Dict]:
        """Fetch all GTT (Good Till Triggered) orders."""
        try:
            if access_token:
                self.kite.set_access_token(access_token)
            loop = asyncio.get_event_loop()
            gtts = await loop.run_in_executor(None, self.kite.get_gtts)
            return gtts or []
        except Exception as e:
            logger.error(f"Error fetching GTTs: {e}")
            raise

    async def place_gtt(self, 
                       tradingsymbol: str, 
                       exchange: str,
                       trigger_values: List[float],
                       last_price: float,
                       orders: List[Dict],
                       gtt_type: str = "two-leg") -> str:
        """
        Place GTT (Good Till Triggered) order.
        
        Args:
            tradingsymbol: Trading symbol
            exchange: Exchange (NSE, BSE, etc.)
            trigger_values: List of trigger prices [stop_loss, target]
            last_price: Current market price
            orders: List of order configurations
            gtt_type: Type of GTT (single, two-leg)
        
        Returns:
            GTT order ID
        """
        try:
            logger.info(f"Placing GTT for {tradingsymbol}: Triggers {trigger_values}")
            
            gtt_params = {
                "trigger_type": gtt_type,
                "tradingsymbol": tradingsymbol,
                "exchange": exchange,
                "trigger_values": trigger_values,
                "last_price": last_price,
                "orders": orders
            }
            
            loop = asyncio.get_event_loop()
            gtt_id = await loop.run_in_executor(
                None,
                lambda: self.kite.place_gtt(**gtt_params)
            )
            logger.info(f"GTT placed successfully. ID: {gtt_id}")
            return str(gtt_id)
        except Exception as e:
            logger.error(f"Error placing GTT: {e}")
            raise
        
zerodha_service = ZerodhaService()
