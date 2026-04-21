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
        num_stocks: int = 0,
    ) -> int:
        """
        Calculate position size.

        Swing mode (num_stocks > 0):
          Allocates capital equally across stocks — deploys full capital.
          capital_per_stock = capital / num_stocks
          quantity          = floor(capital_per_stock / entry_price)

        Intraday mode (num_stocks == 0):
          Risk-based sizing with leverage.
          quantity = floor((capital × leverage × risk%) / risk_per_share)
        """
        if entry_price <= 0:
            return 0

        # ── Swing: equal-weight capital allocation ────────────────────────
        if num_stocks > 0:
            capital_per_stock = capital / num_stocks
            quantity = math.floor(capital_per_stock / entry_price)
            logger.info(
                f"Capital Alloc [{action}]: Capital={capital:,.0f}, "
                f"Stocks={num_stocks}, PerStock={capital_per_stock:,.0f}, "
                f"Entry={entry_price:.2f}, Qty={quantity}"
            )
            return max(quantity, 1)

        # ── Intraday: risk-based sizing ────────────────────────────────────
        leverage = max(1, min(5, leverage))
        if action == "SELL":
            risk_per_share = stop_loss - entry_price
            if risk_per_share <= 0:
                logger.warning(
                    f"SHORT risk calc invalid: stop_loss ({stop_loss}) must be "
                    f"ABOVE entry ({entry_price}) for a short position."
                )
                return 0
        else:
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
