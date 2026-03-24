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
        Generate an intraday BUY / SELL / NEUTRAL signal using 5 indicator combos.

        Combo 1: VWAP + RSI  (Institutional Level)
          BUY  — price ABOVE VWAP AND RSI 45–75 (widened from 50–70)
          SELL — price BELOW VWAP AND RSI 25–55 (widened from 30–50)

        Combo 2: MACD + RSI  (Momentum & Strength)
          BUY  — MACD histogram > 0 AND RSI 40–75
                 OR macd_bullish_crossover (immediate crossover → strong signal)
          SELL — MACD histogram < 0 AND RSI 25–60
                 OR macd_bearish_crossover

        Combo 3: Bollinger Bands + RSI  (Volatility & Reversal)
          BUY  — bb_position = NEAR_LOWER AND RSI < 45 (mean reversion long)
                 OR price crossing above BB middle (momentum breakout)
          SELL — bb_position = NEAR_UPPER AND RSI > 55 (mean reversion short)

        Combo 4: EMA Trend (promoted from tiebreaker to full vote)
          BUY  — price > EMA9 > EMA21 (bullish trend alignment)
          SELL — price < EMA9 < EMA21 (bearish trend alignment)

        Combo 5: Stochastic (promoted from bonus to full vote)
          BUY  — stoch_k < 30 AND stoch_k > stoch_d (oversold + recovering)
          SELL — stoch_k > 70 AND stoch_k < stoch_d (overbought + falling)

        Returns:
            signal   : "BUY" | "SELL" | "NEUTRAL"
            strength : 0–5 (number of combos that agree)
            reasons  : list of explanation strings
            score    : numeric score for ranking
        """
        rsi = indicators.get("rsi", 50.0)
        price_vs_vwap = indicators.get("price_vs_vwap", "ABOVE")
        macd_hist = indicators.get("macd_histogram", 0.0)
        macd_bullish_crossover = indicators.get("macd_bullish_crossover", False)
        macd_bearish_crossover = indicators.get("macd_bearish_crossover", False)
        bb_position = indicators.get("bb_position", "MIDDLE")
        bb_middle = indicators.get("bb_middle", 0.0)
        stoch_k = indicators.get("stoch_k", 50.0)
        stoch_d = indicators.get("stoch_d", 50.0)
        stoch_signal = indicators.get("stoch_signal", "NEUTRAL")
        ema_9 = indicators.get("ema_9", 0.0)
        ema_21 = indicators.get("ema_21", 0.0)
        last_close = indicators.get("last_close", 0.0)

        buy_votes = []
        sell_votes = []

        # ── Combo 1: VWAP + RSI ───────────────────────────────────────────
        # Widened RSI range: BUY 45–75 (was 50–70), SELL 25–55 (was 30–50)
        if price_vs_vwap == "ABOVE" and 45 <= rsi <= 75:
            buy_votes.append(
                f"VWAP+RSI: Price above VWAP, RSI={rsi:.1f} (momentum zone)"
            )
        elif price_vs_vwap == "BELOW" and 25 <= rsi <= 55:
            sell_votes.append(
                f"VWAP+RSI: Price below VWAP, RSI={rsi:.1f} (bearish zone)"
            )

        # ── Combo 2: MACD + RSI (+ crossover signals) ────────────────────
        if macd_bullish_crossover:
            # Immediate crossover → strong momentum signal regardless of RSI
            buy_votes.append(
                f"MACD: Bullish crossover detected (hist={macd_hist:.4f}) — strong momentum"
            )
        elif macd_hist > 0 and 40 <= rsi <= 75:
            buy_votes.append(
                f"MACD+RSI: MACD histogram={macd_hist:.4f} (bullish), RSI={rsi:.1f}"
            )

        if macd_bearish_crossover:
            # Immediate crossover → strong bearish momentum signal
            sell_votes.append(
                f"MACD: Bearish crossover detected (hist={macd_hist:.4f}) — strong momentum"
            )
        elif macd_hist < 0 and 25 <= rsi <= 60:
            sell_votes.append(
                f"MACD+RSI: MACD histogram={macd_hist:.4f} (bearish), RSI={rsi:.1f}"
            )

        # ── Combo 3: Bollinger Bands + RSI ───────────────────────────────
        if bb_position == "NEAR_LOWER" and rsi < 45:
            buy_votes.append(
                f"BB+RSI: Price near lower band, RSI={rsi:.1f} — mean reversion long"
            )
        elif bb_position == "MIDDLE" and last_close > bb_middle > 0 and macd_hist > 0:
            # BB middle crossover + positive MACD = momentum breakout
            buy_votes.append(
                f"BB: Price above BB midline with positive MACD={macd_hist:.4f} — momentum breakout"
            )

        if bb_position == "NEAR_UPPER" and rsi > 55:
            sell_votes.append(
                f"BB+RSI: Price near upper band, RSI={rsi:.1f} — mean reversion short"
            )
        elif bb_position == "MIDDLE" and last_close < bb_middle > 0 and macd_hist < 0:
            sell_votes.append(
                f"BB: Price below BB midline with negative MACD={macd_hist:.4f} — momentum breakdown"
            )

        # ── Combo 4: EMA Trend (full vote, not just tiebreaker) ──────────
        if ema_9 > 0 and ema_21 > 0 and last_close > 0:
            if last_close > ema_9 > ema_21:
                buy_votes.append(f"EMA: Price({last_close:.2f}) > EMA9({ema_9:.2f}) > EMA21({ema_21:.2f}) — bullish alignment")
            elif last_close < ema_9 < ema_21:
                sell_votes.append(f"EMA: Price({last_close:.2f}) < EMA9({ema_9:.2f}) < EMA21({ema_21:.2f}) — bearish alignment")

        # ── Combo 5: Stochastic (full vote) ──────────────────────────────
        # BUY: oversold AND recovering (k crossing above d)
        if stoch_k < 30 and stoch_k > stoch_d:
            buy_votes.append(
                f"Stoch: Oversold+recovering — K={stoch_k:.1f} crossed above D={stoch_d:.1f}"
            )
        elif stoch_signal == "OVERSOLD":
            buy_votes.append(
                f"Stoch: Oversold zone — K={stoch_k:.1f}, D={stoch_d:.1f}"
            )

        # SELL: overbought AND falling (k crossing below d)
        if stoch_k > 70 and stoch_k < stoch_d:
            sell_votes.append(
                f"Stoch: Overbought+falling — K={stoch_k:.1f} crossed below D={stoch_d:.1f}"
            )
        elif stoch_signal == "OVERBOUGHT":
            sell_votes.append(
                f"Stoch: Overbought zone — K={stoch_k:.1f}, D={stoch_d:.1f}"
            )

        # ── Resolve signal ────────────────────────────────────────────────
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
        elif n_buy == n_sell and n_buy >= 1:
            # Tiebreak: use VWAP direction
            if price_vs_vwap == "ABOVE":
                signal = "BUY"
                strength = n_buy
                reasons = buy_votes
            else:
                signal = "SELL"
                strength = n_sell
                reasons = sell_votes
        else:
            # Truly neutral — still try to assign weak signal from MACD direction alone
            if macd_hist > 0:
                signal = "BUY"
                strength = 1
                reasons = [f"MACD: Positive histogram={macd_hist:.4f} — weak bullish bias"]
            elif macd_hist < 0:
                signal = "SELL"
                strength = 1
                reasons = [f"MACD: Negative histogram={macd_hist:.4f} — weak bearish bias"]
            else:
                signal = "NEUTRAL"
                strength = 0
                reasons = []

        # Score: signal_strength × 10 + bonus for multiple combos + stochastic bonus
        score = strength * 10
        if signal == "BUY":
            if stoch_signal in ("BULLISH", "OVERSOLD"):
                score += 3
            if macd_bullish_crossover:
                score += 5   # crossovers are high-conviction
            if price_vs_vwap == "ABOVE":
                score += 2   # VWAP confirmation bonus
        elif signal == "SELL":
            if stoch_signal in ("BEARISH", "OVERBOUGHT"):
                score += 3
            if macd_bearish_crossover:
                score += 5
            if price_vs_vwap == "BELOW":
                score += 2

        logger.debug(
            f"Signal: {signal} | strength={strength} | score={score} | "
            f"RSI={rsi:.1f} VWAP={price_vs_vwap} MACD_hist={macd_hist:.4f} "
            f"BB={bb_position} EMA9={ema_9:.2f} EMA21={ema_21:.2f} "
            f"stoch_k={stoch_k:.1f}"
        )

        return {
            "signal": signal,
            "strength": strength,
            "reasons": reasons,
            "score": score,
        }

    # ── Daily swing signal (used by backtest_engine on daily OHLCV data) ────────

    def generate_daily_signal(self, indicators: Dict) -> Dict:
        """
        Daily swing trading signal — designed for daily OHLCV candles.

        generate_intraday_signal() was built for 5-minute candles (intraday VWAP,
        tight RSI bands, etc.) and produces garbage on daily data. This method uses
        indicator relationships that are meaningful on a daily timeframe.

        Combos (need ≥3 to generate a signal):

        Combo 1 — EMA Trend Alignment (primary filter)
          BUY : EMA20 > EMA50  (medium-term uptrend confirmed)
          SELL: EMA20 < EMA50  (medium-term downtrend confirmed)

        Combo 2 — Price vs EMA20 (trend participation)
          BUY : close > EMA20  (price respecting trend, not extended below)
          SELL: close < EMA20

        Combo 3 — RSI Momentum Zone (not overbought/oversold entry)
          BUY : RSI 45–68  (momentum building, not yet overbought)
          SELL: RSI 32–55  (momentum declining, not yet oversold)

        Combo 4 — MACD Direction / Crossover (momentum confirmation)
          BUY : histogram > 0 or bullish crossover just fired
          SELL: histogram < 0 or bearish crossover just fired

        Combo 5 — ADX Trend Strength (trend quality filter)
          BUY : ADX > 20 AND DI+ > DI-  (trending up, not ranging)
          SELL: ADX > 20 AND DI- > DI+  (trending down, not ranging)

        Returns:
            signal   : "BUY" | "SELL" | "NEUTRAL"
            strength : number of combos agreeing (0–5)
            reasons  : list of explanation strings
        """
        close     = indicators.get("last_close", 0.0)
        ema20     = indicators.get("ema_20", 0.0)
        ema50     = indicators.get("ema_50", 0.0)
        rsi       = indicators.get("rsi", 50.0)
        macd_hist = indicators.get("macd_histogram", 0.0)
        macd_bx   = indicators.get("macd_bullish_crossover", False)
        macd_brx  = indicators.get("macd_bearish_crossover", False)
        adx       = indicators.get("adx", 0.0)
        di_plus   = indicators.get("di_plus", 0.0)
        di_minus  = indicators.get("di_minus", 0.0)

        buy_votes: list = []
        sell_votes: list = []

        # ── Combo 1: EMA trend alignment ──────────────────────────────────
        if ema20 > 0 and ema50 > 0:
            if ema20 > ema50:
                buy_votes.append(
                    f"EMA20({ema20:.2f}) > EMA50({ema50:.2f}) — uptrend aligned"
                )
            else:
                sell_votes.append(
                    f"EMA20({ema20:.2f}) < EMA50({ema50:.2f}) — downtrend aligned"
                )

        # ── Combo 2: Price vs EMA20 ────────────────────────────────────────
        if ema20 > 0:
            if close > ema20:
                buy_votes.append(
                    f"Price({close:.2f}) > EMA20({ema20:.2f}) — above trend"
                )
            else:
                sell_votes.append(
                    f"Price({close:.2f}) < EMA20({ema20:.2f}) — below trend"
                )

        # ── Combo 3: RSI momentum zone ─────────────────────────────────────
        if 45 <= rsi <= 68:
            buy_votes.append(f"RSI={rsi:.1f} — bullish momentum zone (45–68)")
        elif 32 <= rsi <= 55:
            sell_votes.append(f"RSI={rsi:.1f} — bearish momentum zone (32–55)")

        # ── Combo 4: MACD direction / crossover ───────────────────────────
        if macd_bx:
            buy_votes.append(
                f"MACD bullish crossover (hist={macd_hist:.4f}) — momentum turning up"
            )
        elif macd_hist > 0:
            buy_votes.append(f"MACD histogram={macd_hist:.4f} — positive momentum")

        if macd_brx:
            sell_votes.append(
                f"MACD bearish crossover (hist={macd_hist:.4f}) — momentum turning down"
            )
        elif macd_hist < 0:
            sell_votes.append(f"MACD histogram={macd_hist:.4f} — negative momentum")

        # ── Combo 5: ADX trend strength ────────────────────────────────────
        if adx > 20:
            if di_plus > di_minus:
                buy_votes.append(
                    f"ADX={adx:.1f} (>20) DI+({di_plus:.1f}) > DI-({di_minus:.1f}) — trending up"
                )
            elif di_minus > di_plus:
                sell_votes.append(
                    f"ADX={adx:.1f} (>20) DI-({di_minus:.1f}) > DI+({di_plus:.1f}) — trending down"
                )

        # ── Resolve: require ≥3 agreeing combos ───────────────────────────
        n_buy  = len(buy_votes)
        n_sell = len(sell_votes)

        if n_buy >= 3 and n_buy > n_sell:
            score = n_buy * 10 + (5 if adx > 25 else 0) + (5 if macd_bx else 0)
            return {"signal": "BUY",  "strength": n_buy,  "reasons": buy_votes,  "score": score}
        elif n_sell >= 3 and n_sell > n_buy:
            score = n_sell * 10 + (5 if adx > 25 else 0) + (5 if macd_brx else 0)
            return {"signal": "SELL", "strength": n_sell, "reasons": sell_votes, "score": score}
        else:
            return {"signal": "NEUTRAL", "strength": 0, "reasons": [], "score": 0}

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
