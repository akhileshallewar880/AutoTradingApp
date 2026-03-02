from typing import List, Dict, Optional
import pandas as pd
import numpy as np
from app.core.logging import logger


class StrategyEngine:
    def __init__(self):
        pass

    # ── Intraday signal generation ────────────────────────────────────────────

    def generate_intraday_signal(self, indicators: Dict) -> Dict:
        """
        Generate an intraday BUY / SELL / NEUTRAL signal using 3 indicator combos:

        Combo 1: VWAP + RSI  (Institutional Level)
          BUY  — price ABOVE VWAP AND RSI 50–70 (momentum zone, not overbought)
          SELL — price BELOW VWAP AND RSI 30–50 (bearish momentum, not oversold)

        Combo 2: MACD + RSI  (Momentum & Strength)
          BUY  — MACD histogram > 0 (bullish) AND RSI 40–70
          SELL — MACD histogram < 0 (bearish) AND RSI 30–60

        Combo 3: Bollinger Bands + RSI  (Volatility & Reversal)
          BUY  — bb_position = NEAR_LOWER AND RSI < 40 (mean reversion long)
          SELL — bb_position = NEAR_UPPER AND RSI > 60 (mean reversion short)

        Returns:
            signal   : "BUY" | "SELL" | "NEUTRAL"
            strength : 0–3 (number of combos that agree)
            reasons  : list of explanation strings
            score    : numeric score for ranking
        """
        rsi = indicators.get("rsi", 50.0)
        price_vs_vwap = indicators.get("price_vs_vwap", "ABOVE")
        macd_hist = indicators.get("macd_histogram", 0.0)
        bb_position = indicators.get("bb_position", "MIDDLE")
        stoch_signal = indicators.get("stoch_signal", "NEUTRAL")
        ema_9 = indicators.get("ema_9", 0.0)
        ema_21 = indicators.get("ema_21", 0.0)
        last_close = indicators.get("last_close", 0.0)

        buy_votes = []
        sell_votes = []

        # ── Combo 1: VWAP + RSI ───────────────────────────────────────────
        if price_vs_vwap == "ABOVE" and 50 <= rsi <= 70:
            buy_votes.append(
                f"VWAP+RSI: Price above VWAP, RSI={rsi:.1f} (momentum zone)"
            )
        elif price_vs_vwap == "BELOW" and 30 <= rsi <= 50:
            sell_votes.append(
                f"VWAP+RSI: Price below VWAP, RSI={rsi:.1f} (bearish zone)"
            )

        # ── Combo 2: MACD + RSI ───────────────────────────────────────────
        if macd_hist > 0 and 40 <= rsi <= 70:
            buy_votes.append(
                f"MACD+RSI: MACD histogram={macd_hist:.4f} (bullish), RSI={rsi:.1f}"
            )
        elif macd_hist < 0 and 30 <= rsi <= 60:
            sell_votes.append(
                f"MACD+RSI: MACD histogram={macd_hist:.4f} (bearish), RSI={rsi:.1f}"
            )

        # ── Combo 3: Bollinger Bands + RSI ───────────────────────────────
        if bb_position == "NEAR_LOWER" and rsi < 40:
            buy_votes.append(
                f"BB+RSI: Price near lower band, RSI={rsi:.1f} — mean reversion long"
            )
        elif bb_position == "NEAR_UPPER" and rsi > 60:
            sell_votes.append(
                f"BB+RSI: Price near upper band, RSI={rsi:.1f} — mean reversion short"
            )

        # ── Tiebreaker: EMA trend ─────────────────────────────────────────
        if ema_9 > 0 and ema_21 > 0 and last_close > 0:
            if last_close > ema_9 > ema_21:
                buy_votes.append("EMA: Price > EMA9 > EMA21 (bullish alignment)")
            elif last_close < ema_9 < ema_21:
                sell_votes.append("EMA: Price < EMA9 < EMA21 (bearish alignment)")

        n_buy = len(buy_votes)
        n_sell = len(sell_votes)

        if n_buy > n_sell:
            signal = "BUY"
            strength = n_buy
            reasons = buy_votes
        elif n_sell > n_buy:
            signal = "SELL"
            strength = n_sell
            reasons = sell_votes
        else:
            signal = "NEUTRAL"
            strength = 0
            reasons = buy_votes + sell_votes

        # Score: signal_strength × 10 + stochastic confirmation bonus
        score = strength * 10
        if signal == "BUY" and stoch_signal in ("BULLISH", "OVERSOLD"):
            score += 3
        elif signal == "SELL" and stoch_signal in ("BEARISH", "OVERBOUGHT"):
            score += 3

        return {
            "signal": signal,
            "strength": strength,
            "reasons": reasons,
            "score": score,
        }

    # ── Legacy methods (used by trading_agent.py) ─────────────────────────────

    def filter_high_volume(self, instruments: List[Dict], limit: int = 50) -> List[Dict]:
        logger.info(f"Filtering top {limit} stocks by volume")
        return instruments[:limit]

    def apply_technical_analysis(self, df: pd.DataFrame) -> Dict:
        """
        Legacy deterministic analysis used by trading_agent.py.
        Calculates ATR-based stop-loss and target.
        """
        if df.empty:
            return {}

        df = df.copy()
        df["close"] = df["close"].astype(float)
        df["high"] = df["high"].astype(float)
        df["low"] = df["low"].astype(float)

        high_low = df["high"] - df["low"]
        high_close = np.abs(df["high"] - df["close"].shift())
        low_close = np.abs(df["low"] - df["close"].shift())
        ranges = pd.concat([high_low, high_close, low_close], axis=1)
        true_range = np.max(ranges, axis=1)

        atr = true_range.rolling(14).mean().iloc[-1]
        last_close = df["close"].iloc[-1]

        stop_loss = last_close - (2 * atr)
        target = last_close + (4 * atr)

        return {
            "atr": atr,
            "last_close": last_close,
            "calculated_stop_loss": stop_loss,
            "calculated_target": target,
            "signal": "BUY",
        }


strategy_engine = StrategyEngine()
