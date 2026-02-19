from typing import List
from app.models.trade_models import Trade
import pandas as pd

class PerformanceEngine:
    def __init__(self):
        pass

    def calculate_monthly_metrics(self, trades: List[Trade]) -> dict:
        """
        Calculates Win Rate, Total PnL, Drawdown.
        """
        if not trades:
            return {
                "total_pnl": 0.0,
                "win_rate": 0.0,
                "max_drawdown": 0.0,
                "total_trades": 0
            }
            
        df = pd.DataFrame([t.model_dump() for t in trades])
        
        # Mock PnL calc (assuming closed trades have pnl)
        total_pnl = df['pnl'].sum()
        
        wins = df[df['pnl'] > 0]
        win_rate = (len(wins) / len(df)) * 100 if len(df) > 0 else 0
        
        # Max Drawdown (simplified on cumulative pnl)
        df['cum_pnl'] = df['pnl'].cumsum()
        df['peak'] = df['cum_pnl'].cummax()
        df['drawdown'] = df['cum_pnl'] - df['peak']
        max_drawdown = df['drawdown'].min()
        
        return {
            "total_pnl": round(total_pnl, 2),
            "win_rate": round(win_rate, 2),
            "max_drawdown": round(max_drawdown, 2),
            "total_trades": len(df)
        }

performance_engine = PerformanceEngine()
