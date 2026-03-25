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

    # ── Daily swing signal v2 (backtest_engine — daily OHLCV) ───────────────────

    def generate_daily_signal(self, indicators: Dict) -> Dict:
        """
        Daily swing trading signal v2 — designed for daily OHLCV candles.

        Hard gates (any failing → NEUTRAL immediately):
          - market_structure must not be SIDEWAYS  (range = no edge)
          - volume_ratio must be >= 0.8            (avoid thin days)
          - adx must be > 15                       (minimum trend strength)

        Combos (need ≥3 agreeing for non-NEUTRAL):

        Combo 1 — EMA Trend Alignment + slope
          BUY : EMA20 > EMA50  AND  ema20_slope > 0
          SELL: EMA20 < EMA50  AND  ema20_slope < 0

        Combo 2 — Price vs EMA20 (trend participation)
          BUY : close > EMA20
          SELL: close < EMA20

        Combo 3 — RSI Momentum Zone
          BUY : RSI 45–70  (building, not overbought)
          SELL: RSI 30–55  (declining, not oversold)

        Combo 4 — MACD Direction / Crossover
          BUY : histogram > 0  OR  bullish crossover
          SELL: histogram < 0  OR  bearish crossover

        Combo 5 — ADX Trend Strength + DI direction
          BUY : ADX > 20  AND  DI+ > DI-
          SELL: ADX > 20  AND  DI- > DI+

        Bonus (no extra combo required — adds to strength + score):
          +1 — candle pattern confirms direction (HAMMER/BULL_ENGULF for BUY)
          +1 — pullback_to_ema20 (quality entry, not chasing)
          +1 — volume_ratio > 1.5 (institutional activity)

        Returns:
            signal        : "BUY" | "SELL" | "NEUTRAL"
            strength      : combos + bonus points
            reasons       : explanation list
            score         : numeric rank
            reject_reason : present when NEUTRAL
        """
        close            = indicators.get("last_close", 0.0)
        ema20            = indicators.get("ema_20", 0.0)
        ema50            = indicators.get("ema_50", 0.0)
        ema20_slope      = indicators.get("ema20_slope", 0.0)
        rsi              = indicators.get("rsi", 50.0)
        macd_hist        = indicators.get("macd_histogram", 0.0)
        macd_bx          = indicators.get("macd_bullish_crossover", False)
        macd_brx         = indicators.get("macd_bearish_crossover", False)
        adx              = indicators.get("adx", 0.0)
        di_plus          = indicators.get("di_plus", 0.0)
        di_minus         = indicators.get("di_minus", 0.0)
        market_structure = indicators.get("market_structure", "UNKNOWN")
        volume_ratio     = indicators.get("volume_ratio", 1.0)
        candle_pattern   = indicators.get("candle_pattern", "NONE")
        pullback         = indicators.get("pullback_to_ema20", False)

        def _neutral(reason: str) -> Dict:
            return {"signal": "NEUTRAL", "strength": 0, "reasons": [],
                    "score": 0, "reject_reason": reason}

        # ── Hard gates ────────────────────────────────────────────────────
        if market_structure == "SIDEWAYS":
            return _neutral(f"SIDEWAYS market — no directional edge")
        if volume_ratio < 0.8:
            return _neutral(f"Low volume: ratio={volume_ratio:.2f} (need ≥0.8)")
        if adx < 15:
            return _neutral(f"Weak trend: ADX={adx:.1f} < 15 (choppy market)")

        buy_votes:  list = []
        sell_votes: list = []

        # ── Combo 1: EMA alignment + slope ────────────────────────────────
        if ema20 > 0 and ema50 > 0:
            if ema20 > ema50 and ema20_slope > 0:
                buy_votes.append(f"EMA20({ema20:.2f}) > EMA50({ema50:.2f}), rising slope — uptrend")
            elif ema20 < ema50 and ema20_slope < 0:
                sell_votes.append(f"EMA20({ema20:.2f}) < EMA50({ema50:.2f}), falling slope — downtrend")

        # ── Combo 2: Price vs EMA20 ────────────────────────────────────────
        if ema20 > 0:
            if close > ema20:
                buy_votes.append(f"Price({close:.2f}) > EMA20({ema20:.2f}) — above trend")
            else:
                sell_votes.append(f"Price({close:.2f}) < EMA20({ema20:.2f}) — below trend")

        # ── Combo 3: RSI momentum zone ─────────────────────────────────────
        if 45 <= rsi <= 70:
            buy_votes.append(f"RSI={rsi:.1f} — bullish zone (45–70)")
        elif 30 <= rsi <= 55:
            sell_votes.append(f"RSI={rsi:.1f} — bearish zone (30–55)")

        # ── Combo 4: MACD direction / crossover ───────────────────────────
        if macd_bx:
            buy_votes.append(f"MACD bullish crossover (hist={macd_hist:.4f})")
        elif macd_hist > 0:
            buy_votes.append(f"MACD histogram={macd_hist:.4f} — positive")
        if macd_brx:
            sell_votes.append(f"MACD bearish crossover (hist={macd_hist:.4f})")
        elif macd_hist < 0:
            sell_votes.append(f"MACD histogram={macd_hist:.4f} — negative")

        # ── Combo 5: ADX + DI direction ───────────────────────────────────
        if adx > 20:
            if di_plus > di_minus:
                buy_votes.append(f"ADX={adx:.1f} DI+({di_plus:.1f})>DI-({di_minus:.1f}) — trending up")
            elif di_minus > di_plus:
                sell_votes.append(f"ADX={adx:.1f} DI-({di_minus:.1f})>DI+({di_plus:.1f}) — trending down")

        n_buy  = len(buy_votes)
        n_sell = len(sell_votes)

        if n_buy >= 3 and n_buy > n_sell:
            direction, votes, base = "BUY",  buy_votes,  n_buy
        elif n_sell >= 3 and n_sell > n_buy:
            direction, votes, base = "SELL", sell_votes, n_sell
        else:
            return _neutral(f"Insufficient combo agreement — BUY={n_buy} SELL={n_sell}")

        # ── Bonus filters ─────────────────────────────────────────────────
        bonus = 0
        bonus_r: list = []
        if direction == "BUY" and candle_pattern in ("HAMMER", "BULL_ENGULF"):
            bonus += 1
            bonus_r.append(f"Candle: {candle_pattern} — bullish rejection")
        elif direction == "SELL" and candle_pattern in ("BEAR_ENGULF",):
            bonus += 1
            bonus_r.append(f"Candle: {candle_pattern} — bearish rejection")
        if pullback:
            bonus += 1
            bonus_r.append("Pullback to EMA20 — quality entry at support")
        if volume_ratio > 1.5:
            bonus += 1
            bonus_r.append(f"Volume spike {volume_ratio:.2f}x avg — institutional")

        score = (
            base * 10
            + bonus * 5
            + (5 if adx > 25 else 0)
            + (5 if (macd_bx and direction == "BUY") or (macd_brx and direction == "SELL") else 0)
        )
        return {
            "signal":   direction,
            "strength": base + bonus,
            "reasons":  votes + bonus_r,
            "score":    score,
        }

    # ── Intraday signal v2 (live 5-min candle trading) ───────────────────────

    def generate_intraday_signal_v2(self, indicators: Dict) -> Dict:
        """
        Intraday signal v2 — STRICT discipline for 5-minute candles.

        Hard gates (any failing → NEUTRAL immediately):
          1. Time: skip 9:15–9:20 (opening noise) and 12:00–13:00 (lunch)
          2. Volume: bar_volume > 1.5× 20-bar avg volume
          3. Market structure: not SIDEWAYS
          4. Candle: not DOJI (no directional conviction)
          5. VWAP: must be available

        Soft combos (need ≥3 agreeing for a signal):
          1. Market structure aligned (UPTREND→BUY, DOWNTREND→SELL)
          2. VWAP pullback zone (price within 0.8% of VWAP — ideal entry)
          3. Rejection candle in direction (hammer/engulf)
          4. RSI momentum zone (BUY: 40–65; SELL: 35–60)
          5. EMA9/21 micro-structure (EMA9>EMA21 for BUY; <EMA21 for SELL)

        VWAP directional gate (applied after combos):
          - price ABOVE VWAP → suppress all SELL votes
          - price BELOW VWAP → suppress all BUY votes

        SL / Target:
          - hard % based: default sl_pct=0.75%, target_pct=1.5% (2:1 RR)

        Returns strict JSON-compatible dict:
          action, reason, entry_price, stop_loss, target,
          confidence, market_condition, signal, strength, reasons
        """
        bar_hour         = indicators.get("bar_hour", 10)
        bar_minute       = indicators.get("bar_minute", 0)
        last_close       = indicators.get("last_close", 0.0)
        vwap             = indicators.get("vwap", 0.0)
        ema_9            = indicators.get("ema_9", 0.0)
        ema_21           = indicators.get("ema_21", 0.0)
        rsi              = indicators.get("rsi", 50.0)
        volume           = indicators.get("volume", 0.0)
        avg_volume       = indicators.get("avg_volume", 1.0)
        market_structure = indicators.get("market_structure", "UNKNOWN")
        candle_pattern   = indicators.get("candle_pattern", "NONE")
        sl_pct           = indicators.get("sl_pct", 0.75)
        target_pct       = indicators.get("target_pct", 1.5)

        vol_ratio = volume / avg_volume if avg_volume > 0 else 1.0

        def _neutral_v2(reason: str) -> Dict:
            return {
                "signal": "NEUTRAL", "action": "NO_TRADE", "strength": 0,
                "reasons": [], "reason": reason, "entry_price": 0.0,
                "stop_loss": 0.0, "target": 0.0, "confidence": "LOW",
                "market_condition": "SIDEWAYS", "reject_reason": reason, "score": 0,
            }

        # ── Hard gates ────────────────────────────────────────────────────
        if bar_hour == 9 and bar_minute < 20:
            return _neutral_v2("Time: skip opening 5 min (9:15–9:20) — high noise")
        if bar_hour == 12 or (bar_hour == 13 and bar_minute == 0):
            return _neutral_v2("Time: lunch hour (12:00–13:00) — thin liquidity")
        if vol_ratio < 1.5:
            return _neutral_v2(f"Volume too low: {vol_ratio:.2f}x avg (need ≥1.5x)")
        if market_structure == "SIDEWAYS":
            return _neutral_v2("SIDEWAYS structure — no directional edge")
        if candle_pattern == "DOJI":
            return _neutral_v2("Doji candle — no directional conviction")
        if vwap <= 0:
            return _neutral_v2("VWAP unavailable — cannot assess bias")

        price_vs_vwap = "ABOVE" if last_close > vwap else "BELOW"
        vwap_dev_pct  = abs(last_close - vwap) / vwap * 100

        buy_votes:  list = []
        sell_votes: list = []

        # Combo 1: Market structure
        if market_structure == "UPTREND":
            buy_votes.append("Market: UPTREND (HH/HL pattern confirmed)")
        elif market_structure == "DOWNTREND":
            sell_votes.append("Market: DOWNTREND (LH/LL pattern confirmed)")

        # Combo 2: VWAP pullback zone (within 0.8% = ideal entry, not chase)
        if price_vs_vwap == "ABOVE" and vwap_dev_pct <= 0.8:
            buy_votes.append(
                f"VWAP pullback: +{vwap_dev_pct:.2f}% from VWAP — quality LONG entry"
            )
        elif price_vs_vwap == "BELOW" and vwap_dev_pct <= 0.8:
            sell_votes.append(
                f"VWAP pullback: -{vwap_dev_pct:.2f}% from VWAP — quality SHORT entry"
            )

        # Combo 3: Rejection candle
        if candle_pattern in ("HAMMER", "BULL_ENGULF"):
            buy_votes.append(f"Rejection candle: {candle_pattern} — buyers defending level")
        elif candle_pattern in ("BEAR_ENGULF",):
            sell_votes.append(f"Rejection candle: {candle_pattern} — sellers rejecting level")

        # Combo 4: RSI momentum zone (not extended)
        if 40 <= rsi <= 65:
            buy_votes.append(f"RSI={rsi:.1f} — bullish zone (40–65), not overbought")
        elif 35 <= rsi <= 60:
            sell_votes.append(f"RSI={rsi:.1f} — bearish zone (35–60), not oversold")

        # Combo 5: EMA9/21 micro-structure
        if ema_9 > 0 and ema_21 > 0:
            if ema_9 > ema_21:
                buy_votes.append(f"EMA9({ema_9:.2f}) > EMA21({ema_21:.2f}) — micro uptrend")
            else:
                sell_votes.append(f"EMA9({ema_9:.2f}) < EMA21({ema_21:.2f}) — micro downtrend")

        # ── VWAP directional gate: suppress opposite-side votes ───────────
        if price_vs_vwap == "ABOVE":
            sell_votes = []   # No shorts above VWAP
        else:
            buy_votes = []    # No longs below VWAP

        n_buy  = len(buy_votes)
        n_sell = len(sell_votes)

        if n_buy >= 3 and n_buy > n_sell:
            direction, votes, strength = "BUY",  buy_votes,  n_buy
        elif n_sell >= 3 and n_sell > n_buy:
            direction, votes, strength = "SELL", sell_votes, n_sell
        else:
            return _neutral_v2(
                f"Insufficient combos — BUY={n_buy} SELL={n_sell} (need ≥3 same side)"
            )

        # ── SL / Target (hard % based) ────────────────────────────────────
        entry = last_close
        if direction == "BUY":
            stop_loss = round(entry * (1 - sl_pct / 100), 2)
            target    = round(entry * (1 + target_pct / 100), 2)
        else:
            stop_loss = round(entry * (1 + sl_pct / 100), 2)
            target    = round(entry * (1 - target_pct / 100), 2)

        # ── Confidence ────────────────────────────────────────────────────
        has_pattern  = candle_pattern not in ("NONE", "DOJI")
        near_vwap    = vwap_dev_pct <= 0.4
        if strength >= 5 and has_pattern and near_vwap:
            confidence = "HIGH"
        elif strength >= 4 or (has_pattern and near_vwap):
            confidence = "MEDIUM"
        else:
            confidence = "LOW"

        market_cond = (
            f"{market_structure} | VWAP {price_vs_vwap} "
            f"({vwap_dev_pct:.2f}% dev) | vol {vol_ratio:.1f}x avg"
        )

        return {
            "signal":           direction,
            "action":           direction,
            "strength":         strength,
            "reasons":          votes,
            "reason":           "; ".join(votes),
            "entry_price":      round(entry, 2),
            "stop_loss":        stop_loss,
            "target":           target,
            "confidence":       confidence,
            "market_condition": market_cond,
            "sl_pct":           sl_pct,
            "target_pct":       target_pct,
            "rr_ratio":         round(target_pct / sl_pct, 2),
            "score":            strength * 10 + (10 if confidence == "HIGH" else 5 if confidence == "MEDIUM" else 0),
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
