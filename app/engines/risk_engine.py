from app.core.logging import logger
import math

class RiskEngine:
    def __init__(self):
        pass

    def calculate_quantity(self, entry_price: float, stop_loss: float, risk_per_trade: float, capital: float) -> int:
        """
        Calculates position size based on risk percentage.
        Quantity = (Capital * Risk%) / (Entry - StopLoss)
        """
        if entry_price <= stop_loss:
            logger.warning("Entry price is lower than or equal to Stop Loss (for Long trade). Cannot calc quantity.")
            return 0
            
        risk_per_share = entry_price - stop_loss
        total_risk_amount = capital * (risk_per_trade / 100.0)
        
        quantity = math.floor(total_risk_amount / risk_per_share)
        
        logger.info(f"Risk Calc: Capital={capital}, Risk%={risk_per_trade}, Risk/Share={risk_per_share}, Qty={quantity}")
        return max(quantity, 1) # return at least 1 if valid setup, or handle 0 logic upstream

risk_engine = RiskEngine()
