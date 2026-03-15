from app.core.logging import logger
import math


class RiskEngine:
    def __init__(self):
        pass

    def calculate_quantity(
        self,
        entry_price: float,
        stop_loss: float,
        risk_per_trade: float,
        capital: float,
        action: str = "BUY",
        leverage: int = 1,
    ) -> int:
        """
        Calculate position size based on risk percentage and leverage.

        For BUY  (long):  risk_per_share = entry_price - stop_loss
        For SELL (short): risk_per_share = stop_loss - entry_price

        Quantity = (Capital × Leverage × Risk%) / risk_per_share

        Leverage (1–5x) is for MIS intraday trades only.
        Zerodha provides up to 5x margin on MIS equity positions.
        """
        leverage = max(1, min(5, leverage))  # clamp 1–5
        if action == "SELL":
            # Short position: stop is ABOVE entry
            risk_per_share = stop_loss - entry_price
            if risk_per_share <= 0:
                logger.warning(
                    f"SHORT risk calc invalid: stop_loss ({stop_loss}) must be "
                    f"ABOVE entry ({entry_price}) for a short position."
                )
                return 0
        else:
            # Long position: stop is BELOW entry
            risk_per_share = entry_price - stop_loss
            if risk_per_share <= 0:
                logger.warning(
                    f"BUY risk calc invalid: entry_price ({entry_price}) must be "
                    f"ABOVE stop_loss ({stop_loss}) for a long position."
                )
                return 0

        effective_capital = capital * leverage
        total_risk_amount = effective_capital * (risk_per_trade / 100.0)
        quantity = math.floor(total_risk_amount / risk_per_share)

        logger.info(
            f"Risk Calc [{action}]: Capital={capital}, Leverage={leverage}x, "
            f"EffectiveCapital={effective_capital}, Risk%={risk_per_trade}, "
            f"Risk/Share={risk_per_share:.2f}, Qty={quantity}"
        )
        return max(quantity, 1)


risk_engine = RiskEngine()
