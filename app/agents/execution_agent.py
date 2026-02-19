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
    Handles the complete workflow: Buy Order -> Wait for Fill -> Place GTT
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
        access_token: str,  # User's access token for real orders
        update_callback: Callable = None
    ) -> Dict:
        """
        Execute a complete trade workflow:
        1. Place buy order
        2. Monitor until filled
        3. Place GTT for target and stop-loss
        
        Args:
            stock_symbol: Trading symbol
            quantity: Quantity to buy
            entry_price: Entry price
            stop_loss: Stop loss price
            target: Target price
            analysis_id: Analysis ID for tracking
            access_token: User's Zerodha access token
            update_callback: Async function to call with status updates
        
        Returns:
            Dict with execution status and order IDs
        """
        execution_log = {
            "stock_symbol": stock_symbol,
            "status": "STARTED",
            "buy_order_id": None,
            "gtt_order_id": None,
            "updates": []
        }
        
        # Set access token for this execution
        self.zs.kite.set_access_token(access_token)
        
        try:
            # Step 1: Place Buy Order
            await self._send_update(
                analysis_id, stock_symbol, "ORDER_PLACING",
                f"Placing BUY order for {quantity} shares",
                update_callback
            )
            
            buy_order_id = await self.os.execute_trade(
                symbol=stock_symbol,
                quantity=quantity,
                price=entry_price,
                stop_loss=stop_loss,
                target=target
            )
            
            execution_log["buy_order_id"] = buy_order_id
            
            await self._send_update(
                analysis_id, stock_symbol, "ORDER_PLACED",
                f"BUY order placed successfully. Order ID: {buy_order_id}",
                update_callback,
                order_id=buy_order_id
            )
            
            # Step 2: Monitor order status until filled
            await self._send_update(
                analysis_id, stock_symbol, "ORDER_MONITORING",
                "Monitoring order status...",
                update_callback,
                order_id=buy_order_id
            )
            
            is_filled = await self._wait_for_order_fill(buy_order_id, timeout=300)
            
            if not is_filled:
                await self._send_update(
                    analysis_id, stock_symbol, "ORDER_TIMEOUT",
                    "Order not filled within timeout period",
                    update_callback,
                    order_id=buy_order_id
                )
                execution_log["status"] = "TIMEOUT"
                return execution_log
            
            await self._send_update(
                analysis_id, stock_symbol, "ORDER_FILLED",
                f"BUY order filled successfully at ₹{entry_price}",
                update_callback,
                order_id=buy_order_id
            )
            
            # Step 3: Place GTT for Target and Stop Loss
            await self._send_update(
                analysis_id, stock_symbol, "GTT_PLACING",
                f"Placing GTT with SL: ₹{stop_loss}, Target: ₹{target}",
                update_callback
            )
            
            gtt_id = await self._place_gtt_order(
                stock_symbol,
                quantity,
                entry_price,
                stop_loss,
                target
            )
            
            execution_log["gtt_order_id"] = gtt_id
            
            await self._send_update(
                analysis_id, stock_symbol, "GTT_PLACED",
                f"GTT placed successfully. GTT ID: {gtt_id}",
                update_callback,
                order_id=gtt_id
            )
            
            execution_log["status"] = "COMPLETED"
            
            await self._send_update(
                analysis_id, stock_symbol, "COMPLETED",
                f"Trade execution completed for {stock_symbol}",
                update_callback
            )
            
            return execution_log
            
        except MarketClosedException as e:
            # Market is closed — surface a clear, actionable message
            logger.warning(f"Market closed during execution of {stock_symbol}: {e}")
            await self._send_update(
                analysis_id, stock_symbol, "MARKET_CLOSED",
                str(e),
                update_callback
            )
            execution_log["status"] = "MARKET_CLOSED"
            execution_log["error"] = str(e)
            return execution_log

        except Exception as e:
            logger.error(f"Trade execution failed for {stock_symbol}: {e}")
            await self._send_update(
                analysis_id, stock_symbol, "ERROR",
                f"Execution failed: {str(e)}",
                update_callback
            )
            execution_log["status"] = "FAILED"
            execution_log["error"] = str(e)
            return execution_log

    async def _wait_for_order_fill(self, order_id: str, timeout: int = 300) -> bool:
        """
        Poll order status until filled or timeout.
        
        Args:
            order_id: Order ID to monitor
            timeout: Timeout in seconds
        
        Returns:
            True if order filled, False otherwise
        """
        start_time = asyncio.get_event_loop().time()
        poll_interval = 2  # Check every 2 seconds
        
        while asyncio.get_event_loop().time() - start_time < timeout:
            try:
                order_status = await self.zs.get_order_status(order_id)
                status = order_status.get('status', '').upper()
                
                logger.info(f"Order {order_id} status: {status}")
                
                if status == 'COMPLETE':
                    return True
                elif status in ['CANCELLED', 'REJECTED']:
                    logger.warning(f"Order {order_id} was {status}")
                    return False
                
                await asyncio.sleep(poll_interval)
                
            except Exception as e:
                logger.error(f"Error checking order status: {e}")
                await asyncio.sleep(poll_interval)
        
        return False

    async def _place_gtt_order(
        self,
        symbol: str,
        quantity: int,
        last_price: float,
        stop_loss: float,
        target: float
    ) -> str:
        """Place GTT OCO (One-Cancels-Other) order for target and stop-loss."""
        
        # GTT order configuration
        trigger_values = [stop_loss, target]
        
        orders = [
            {
                "transaction_type": "SELL",
                "quantity": quantity,
                "order_type": "LIMIT",
                "product": "CNC",
                "price": stop_loss
            },
            {
                "transaction_type": "SELL",
                "quantity": quantity,
                "order_type": "LIMIT",
                "product": "CNC",
                "price": target
            }
        ]
        
        gtt_id = await self.zs.place_gtt(
            tradingsymbol=symbol,
            exchange="NSE",
            trigger_values=trigger_values,
            last_price=last_price,
            orders=orders,
            gtt_type="two-leg"
        )
        
        return gtt_id

    async def _send_update(
        self,
        analysis_id: str,
        stock_symbol: str,
        update_type: str,
        message: str,
        callback: Callable = None,
        order_id: str = None
    ):
        """Send execution update via callback."""
        if callback:
            update = ExecutionUpdate(
                analysis_id=analysis_id,
                stock_symbol=stock_symbol,
                update_type=update_type,
                message=message,
                order_id=order_id
            )
            await callback(update)

execution_agent = ExecutionAgent()
