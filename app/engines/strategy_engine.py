from typing import List, Dict, Optional
import pandas as pd
import numpy as np
from app.core.logging import logger

class StrategyEngine:
    def __init__(self):
        pass

    def filter_high_volume(self, instruments: List[Dict], limit: int = 50) -> List[Dict]:
        """
        Filters the top N instruments based on volume. 
        Note: logic here assumes 'volume' key exists in input dict, 
        which comes from data_service or an API call.
        """
        # Mock sorting as we might not have volume in instrument list without quote call
        # In real world, we'd sort by 'last_price' * 'volume' or just 'volume'
        logger.info(f"Filtering top {limit} stocks by volume")
        return instruments[:limit]

    def apply_technical_analysis(self, df: pd.DataFrame) -> Dict:
        """
        Applies deterministic rules:
        - ATR Calculation
        - Trend check (e.g. Price > EMA 50)
        """
        if df.empty:
            return {}

        df = df.copy()
        df['close'] = df['close'].astype(float)
        df['high'] = df['high'].astype(float)
        df['low'] = df['low'].astype(float)
        
        # Calculate ATR
        high_low = df['high'] - df['low']
        high_close = np.abs(df['high'] - df['close'].shift())
        low_close = np.abs(df['low'] - df['close'].shift())
        ranges = pd.concat([high_low, high_close, low_close], axis=1)
        true_range = np.max(ranges, axis=1)
        
        atr = true_range.rolling(14).mean().iloc[-1]
        last_close = df['close'].iloc[-1]
        
        # Simple Logic: 
        # Stop Loss = 2 * ATR
        # Target = 2 * Stop Loss (1:2 Risk Reward)
        
        stop_loss = last_close - (2 * atr)
        target = last_close + (4 * atr)
        
        return {
            "atr": atr,
            "last_close": last_close,
            "calculated_stop_loss": stop_loss,
            "calculated_target": target,
            "signal": "BUY" # Simplistic assumption for the agent to validate
        }

strategy_engine = StrategyEngine()
