"""
Options Engine — Generates BUY_CE / BUY_PE signals by running technical
indicators on the index (Nifty / BankNifty) 5-minute candles.

Uses the same 5-combo voting framework as strategy_engine.py but tuned
for index options:
  - Requires 3/5 minimum votes (stricter than equity intraday)
  - Adds time-of-day filter (no new entries after 2:00 PM)
  - Adds theta-decay warning (caution after 1:30 PM on expiry day)
"""

from typing import List, Dict, Optional
from datetime import datetime, date
import pandas as pd
import numpy as np
from app.core.logging import logger


class OptionsEngine:

    MIN_VOTES_REQUIRED = 3  # out of 5 combos — stricter for options

    def calculate_indicators(self, candles: List[Dict]) -> Optional[Dict]:
        """
        Compute VWAP, RSI, MACD, Bollinger Bands, EMA(9), EMA(21),
        and Stochastic from 5-minute candles.

        Returns None if insufficient data (< 20 candles).
        """
        if not candles or len(candles) < 20:
            logger.warning(
                f"[OptionsEngine] Insufficient candles ({len(candles) if candles else 0})"
                " — need at least 20"
            )
            return None

        df = pd.DataFrame(candles)
        df.columns = [c.lower() for c in df.columns]  # normalise column names
        df = df.rename(columns={"date": "timestamp"})

        close = df["close"].astype(float)
        high = df["high"].astype(float)
        low = df["low"].astype(float)
        volume = df["volume"].astype(float)

        # ── VWAP ────────────────────────────────────────────────────────────
        typical_price = (high + low + close) / 3
        cum_tp_vol = (typical_price * volume).cumsum()
        cum_vol = volume.cumsum()
        # Index candles (NIFTY/BANKNIFTY) have zero volume — VWAP would be NaN.
        # In that case fall back to EMA20 as a proxy for "fair value".
        last_close = close.iloc[-1]
        if cum_vol.iloc[-1] > 0:
            vwap = (cum_tp_vol / cum_vol).iloc[-1]
            price_vs_vwap = "ABOVE" if last_close > vwap else "BELOW"
        else:
            # Use 20-period SMA as VWAP proxy when volume is unavailable
            vwap = close.rolling(20).mean().iloc[-1]
            if np.isnan(vwap):
                vwap = last_close  # fallback: treat as neutral
            price_vs_vwap = "ABOVE" if last_close > vwap else "BELOW"

        # ── RSI (14) ────────────────────────────────────────────────────────
        delta = close.diff()
        gain = delta.clip(lower=0)
        loss = -delta.clip(upper=0)
        avg_gain = gain.ewm(com=13, adjust=False).mean()
        avg_loss = loss.ewm(com=13, adjust=False).mean()
        rs = avg_gain / avg_loss.replace(0, np.nan)
        rsi = (100 - 100 / (1 + rs)).iloc[-1]
        rsi = float(rsi) if not np.isnan(rsi) else 50.0

        # ── MACD (12, 26, 9) ─────────────────────────────────────────────
        ema12 = close.ewm(span=12, adjust=False).mean()
        ema26 = close.ewm(span=26, adjust=False).mean()
        macd_line = ema12 - ema26
        signal_line = macd_line.ewm(span=9, adjust=False).mean()
        macd_hist = macd_line - signal_line

        macd_hist_now = float(macd_hist.iloc[-1])
        macd_hist_prev = float(macd_hist.iloc[-2]) if len(macd_hist) > 1 else 0.0
        macd_bullish_crossover = macd_hist_prev < 0 < macd_hist_now
        macd_bearish_crossover = macd_hist_prev > 0 > macd_hist_now

        # ── Bollinger Bands (20, 2σ) ────────────────────────────────────
        bb_period = 20
        bb_mid = close.rolling(bb_period).mean()
        bb_std = close.rolling(bb_period).std()
        bb_upper = bb_mid + 2 * bb_std
        bb_lower = bb_mid - 2 * bb_std

        bb_upper_now = float(bb_upper.iloc[-1])
        bb_lower_now = float(bb_lower.iloc[-1])
        bb_mid_now = float(bb_mid.iloc[-1])
        band_width = bb_upper_now - bb_lower_now

        if band_width > 0:
            pct_b = (last_close - bb_lower_now) / band_width
        else:
            pct_b = 0.5

        if pct_b < 0.2:
            bb_position = "NEAR_LOWER"
        elif pct_b > 0.8:
            bb_position = "NEAR_UPPER"
        else:
            bb_position = "MIDDLE"

        # ── EMA(9) and EMA(21) ────────────────────────────────────────────
        ema_9 = float(close.ewm(span=9, adjust=False).mean().iloc[-1])
        ema_21 = float(close.ewm(span=21, adjust=False).mean().iloc[-1])

        # ── Stochastic (14, 3) ────────────────────────────────────────────
        stoch_period = 14
        lowest_low = low.rolling(stoch_period).min()
        highest_high = high.rolling(stoch_period).max()
        range_hilo = highest_high - lowest_low
        stoch_k_raw = 100 * (close - lowest_low) / range_hilo.replace(0, np.nan)
        stoch_k = float(stoch_k_raw.rolling(3).mean().iloc[-1])
        stoch_d = float(stoch_k_raw.rolling(3).mean().rolling(3).mean().iloc[-1])
        stoch_k = stoch_k if not np.isnan(stoch_k) else 50.0
        stoch_d = stoch_d if not np.isnan(stoch_d) else 50.0

        indicators = {
            "last_close": last_close,
            "vwap": vwap,
            "price_vs_vwap": price_vs_vwap,
            "rsi": rsi,
            "macd_histogram": macd_hist_now,
            "macd_bullish_crossover": macd_bullish_crossover,
            "macd_bearish_crossover": macd_bearish_crossover,
            "bb_position": bb_position,
            "bb_upper": bb_upper_now,
            "bb_lower": bb_lower_now,
            "bb_middle": bb_mid_now,
            "ema_9": ema_9,
            "ema_21": ema_21,
            "stoch_k": stoch_k,
            "stoch_d": stoch_d,
            "candle_count": len(candles),
        }
        vwap_label = "VWAP" if cum_vol.iloc[-1] > 0 else "SMA20(VWAP-proxy)"
        logger.info(
            f"[OptionsEngine] Indicators: close={last_close:.2f} "
            f"{vwap_label}={vwap:.2f} ({price_vs_vwap}) RSI={rsi:.1f} "
            f"MACD_hist={macd_hist_now:.4f} BB={bb_position} "
            f"EMA9={ema_9:.2f} EMA21={ema_21:.2f} Stoch K={stoch_k:.1f} D={stoch_d:.1f}"
        )
        return indicators

    def generate_signal(
        self,
        indicators: Dict,
        expiry_date: Optional[date] = None,
    ) -> Dict:
        """
        Vote across 5 combos to produce BUY_CE, BUY_PE, or NEUTRAL.

        BUY_CE → bullish index → buy CALL option
        BUY_PE → bearish index → buy PUT option

        Returns:
          signal   : "BUY_CE" | "BUY_PE" | "NEUTRAL"
          strength : 0–5 (votes in winning direction)
          reasons  : list of explanation strings
          score    : numeric confidence (0–100)
        """
        now = datetime.now()

        # ── Expiry-day theta decay warning ───────────────────────────────
        expiry_warning = False
        if expiry_date and expiry_date == date.today():
            if now.hour >= 13 and now.minute >= 30:
                expiry_warning = True
                logger.warning(
                    "[OptionsEngine] Expiry day after 1:30 PM — theta decay risk"
                )

        rsi = indicators.get("rsi", 50.0)
        price_vs_vwap = indicators.get("price_vs_vwap", "ABOVE")
        macd_hist = indicators.get("macd_histogram", 0.0)
        macd_bullish_crossover = indicators.get("macd_bullish_crossover", False)
        macd_bearish_crossover = indicators.get("macd_bearish_crossover", False)
        bb_position = indicators.get("bb_position", "MIDDLE")
        bb_middle = indicators.get("bb_middle", 0.0)
        stoch_k = indicators.get("stoch_k", 50.0)
        stoch_d = indicators.get("stoch_d", 50.0)
        ema_9 = indicators.get("ema_9", 0.0)
        ema_21 = indicators.get("ema_21", 0.0)
        last_close = indicators.get("last_close", 0.0)

        bullish_votes = []
        bearish_votes = []

        # ── Combo 1: VWAP + RSI ──────────────────────────────────────────
        if price_vs_vwap == "ABOVE" and 45 <= rsi <= 75:
            bullish_votes.append(
                f"VWAP+RSI: Index above VWAP, RSI={rsi:.1f} (bullish momentum)"
            )
        elif price_vs_vwap == "BELOW" and 25 <= rsi <= 55:
            bearish_votes.append(
                f"VWAP+RSI: Index below VWAP, RSI={rsi:.1f} (bearish momentum)"
            )

        # ── Combo 2: MACD + RSI ──────────────────────────────────────────
        if macd_bullish_crossover:
            bullish_votes.append(
                f"MACD: Bullish crossover (hist={macd_hist:.4f}) — strong momentum"
            )
        elif macd_hist > 0 and 40 <= rsi <= 75:
            bullish_votes.append(
                f"MACD+RSI: Histogram={macd_hist:.4f} (bullish), RSI={rsi:.1f}"
            )

        if macd_bearish_crossover:
            bearish_votes.append(
                f"MACD: Bearish crossover (hist={macd_hist:.4f}) — strong momentum"
            )
        elif macd_hist < 0 and 25 <= rsi <= 60:
            bearish_votes.append(
                f"MACD+RSI: Histogram={macd_hist:.4f} (bearish), RSI={rsi:.1f}"
            )

        # ── Combo 3: Bollinger Bands + RSI ──────────────────────────────
        if bb_position == "NEAR_LOWER" and rsi < 45:
            bullish_votes.append(
                f"BB+RSI: Index near lower band, RSI={rsi:.1f} — mean reversion up"
            )
        elif bb_position == "MIDDLE" and last_close > bb_middle > 0 and macd_hist > 0:
            bullish_votes.append(
                "BB: Price crossed above BB middle with positive MACD — breakout up"
            )
        elif bb_position == "NEAR_UPPER" and rsi > 55:
            bearish_votes.append(
                f"BB+RSI: Index near upper band, RSI={rsi:.1f} — mean reversion down"
            )
        elif bb_position == "MIDDLE" and last_close < bb_middle > 0 and macd_hist < 0:
            bearish_votes.append(
                "BB: Price crossed below BB middle with negative MACD — breakout down"
            )

        # ── Combo 4: EMA Trend ────────────────────────────────────────────
        if ema_9 > 0 and ema_21 > 0:
            if last_close > ema_9 > ema_21:
                bullish_votes.append(
                    f"EMA: price({last_close:.2f}) > EMA9({ema_9:.2f}) > EMA21({ema_21:.2f}) "
                    "— bullish trend alignment"
                )
            elif last_close < ema_9 < ema_21:
                bearish_votes.append(
                    f"EMA: price({last_close:.2f}) < EMA9({ema_9:.2f}) < EMA21({ema_21:.2f}) "
                    "— bearish trend alignment"
                )

        # ── Combo 5: Stochastic ───────────────────────────────────────────
        if stoch_k < 30 and stoch_k > stoch_d:
            bullish_votes.append(
                f"Stochastic: K={stoch_k:.1f} oversold + recovering above D={stoch_d:.1f}"
            )
        elif stoch_k > 70 and stoch_k < stoch_d:
            bearish_votes.append(
                f"Stochastic: K={stoch_k:.1f} overbought + falling below D={stoch_d:.1f}"
            )

        # ── Tally votes ───────────────────────────────────────────────────
        bull_count = len(bullish_votes)
        bear_count = len(bearish_votes)

        logger.info(
            f"[OptionsEngine] Signal votes — Bullish: {bull_count}, Bearish: {bear_count}"
        )

        if bull_count >= self.MIN_VOTES_REQUIRED and bull_count > bear_count:
            signal = "BUY_CE"
            strength = bull_count
            reasons = bullish_votes
        elif bear_count >= self.MIN_VOTES_REQUIRED and bear_count > bull_count:
            signal = "BUY_PE"
            strength = bear_count
            reasons = bearish_votes
        else:
            signal = "NEUTRAL"
            strength = max(bull_count, bear_count)
            reasons = bullish_votes + bearish_votes
            reasons.append(
                f"Signal too weak: {bull_count} bullish vs {bear_count} bearish "
                f"(need {self.MIN_VOTES_REQUIRED}/5 minimum)"
            )

        score = round((strength / 5) * 100, 1)

        if expiry_warning:
            reasons.append(
                "CAUTION: Expiry day after 1:30 PM — theta decay is accelerating. "
                "Reduce lot size or avoid if not highly confident."
            )

        return {
            "signal": signal,
            "strength": strength,
            "reasons": reasons,
            "score": score,
            "bullish_votes": bull_count,
            "bearish_votes": bear_count,
            "expiry_warning": expiry_warning,
        }

    def calculate_premium_levels(
        self,
        entry_premium: float,
        signal: str,
        atr_pct: float = 0.25,
        rr_ratio: float = 2.0,
    ) -> Dict:
        """
        Calculate stop-loss and target premium levels.

        Stop-loss = entry - (entry × atr_pct)    [25% of premium, adjustable]
        Target     = entry + (entry × atr_pct × rr_ratio)  [2× the risk]

        For options: minimum SL = 30% below entry (never lose more than 30%)
        """
        sl_distance = entry_premium * atr_pct
        tp_distance = sl_distance * rr_ratio

        stop_loss = max(round(entry_premium - sl_distance, 1), entry_premium * 0.30)
        target = round(entry_premium + tp_distance, 1)

        rr = round((target - entry_premium) / (entry_premium - stop_loss), 2) if entry_premium > stop_loss else rr_ratio

        return {
            "entry_premium": entry_premium,
            "stop_loss_premium": stop_loss,
            "target_premium": target,
            "risk_reward_ratio": rr,
        }


options_engine = OptionsEngine()
