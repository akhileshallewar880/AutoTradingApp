"""
Options Engine v2 — Regime-Based Opening-Range Breakout System

Replaces the 5-combo indicator voting with a deterministic, rules-based pipeline:

  Phase 1 — Market Regime Detection
    → Measures opening-range size, ADX trend strength, and VWAP distance.
    → Returns TRENDING_UP | TRENDING_DOWN | CHOPPY | SIDEWAYS.
    → CHOPPY and SIDEWAYS immediately produce NO_TRADE. Engine is the gatekeeper.

  Phase 2 — Opening-Range Breakout (ORB) Detection
    → BUY_CE: price closes above OR high, above VWAP, bullish body, volume confirms.
    → BUY_PE: price closes below OR low, below VWAP, bearish body, volume confirms.
    → Each gate is binary — any failure returns NO_TRADE.

  Phase 3 — Structure-Based Risk Levels
    → SL = swing low (CE) / swing high (PE) of last 5 candles.
    → Target = entry + 2× risk.
    → Partial exit = entry + 1× risk (agent auto-exits 50% here).

  Phase 4 — Anti-Overtrading Guard
    → Max 1 trade per day per index.
    → Loss cooldown: sit out the rest of the day after a loss.

The engine is the FINAL authority. GPT-4o writes the narrative but cannot
change the signal or override any hard rule.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
from enum import Enum
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd
import pytz

from app.core.logging import logger

IST = pytz.timezone("Asia/Kolkata")

# ── Hard time gates ───────────────────────────────────────────────────────────
NO_TRADE_BEFORE   = time(9, 25)   # market-open noise period
NO_TRADE_AFTER    = time(14, 0)   # no new entries after 2 PM
EXPIRY_CUTOFF     = time(13, 30)  # theta-decay cutoff on expiry day

# ── Regime thresholds ─────────────────────────────────────────────────────────
MIN_OR_RANGE_PCT      = 0.003    # OR must span ≥ 0.3% of spot (else too tight/choppy)
MIN_ADX               = 20.0    # ADX < 20 → no meaningful trend
MAX_VWAP_DISTANCE_PCT = 0.0015  # price within 0.15% of VWAP → no directional bias

# ── Breakout quality gates ────────────────────────────────────────────────────
MIN_BODY_RATIO       = 0.55    # candle body / total range — rejects wick-heavy candles
MIN_FUT_VOLUME_RATIO = 1.5     # futures volume vs 10-candle avg (0.0 = check skipped)
BREAKOUT_BUFFER      = 0.0005  # close must exceed level by ≥ 0.05% (not just touch)

# ── Retest confirmation ───────────────────────────────────────────────────────
RETEST_BUFFER = 0.002  # pullback must come within 0.2% of breakout level to qualify

# ── ATM delta approximation (index→premium SL mapping) ───────────────────────
ATM_DELTA = 0.5   # ATM CE/PE delta ≈ 0.5 → index moves X pts, premium moves ≈ 0.5X

# ── Anti-overtrading ──────────────────────────────────────────────────────────
MAX_TRADES_PER_DAY = 1


class MarketRegime(str, Enum):
    TRENDING_UP   = "TRENDING_UP"
    TRENDING_DOWN = "TRENDING_DOWN"
    CHOPPY        = "CHOPPY"
    SIDEWAYS      = "SIDEWAYS"


@dataclass
class BreakoutResult:
    """Engine output. Consumed by route and LLM summarizer."""
    # Decision
    signal:        str          = "NO_TRADE"   # BUY_CE | BUY_PE | NO_TRADE
    regime:        MarketRegime = MarketRegime.CHOPPY
    trade_allowed: bool         = True         # False when daily limit / cooldown hit

    # Why the signal was given (or not)
    reasons:        List[str] = field(default_factory=list)
    failed_filters: List[str] = field(default_factory=list)

    # Index-level price context (populated on BUY_CE / BUY_PE)
    entry_index_price: float = 0.0
    sl_index_price:    float = 0.0
    target_index_price: float = 0.0

    # Supporting data for LLM summary + monitoring
    or_high:       float = 0.0
    or_low:        float = 0.0
    adx:           float = 0.0
    atr:           float = 0.0
    indicators:    Dict  = field(default_factory=dict)


class _AntiOvertradeGuard:
    """Stateful per-index daily trade count and post-loss cooldown."""

    def __init__(self):
        self._trade_dates:  Dict[str, date]     = {}
        self._trade_counts: Dict[str, int]      = {}
        self._cooldown_until: Dict[str, datetime] = {}

    def is_allowed(self, index: str) -> Tuple[bool, str]:
        today = date.today()
        now   = datetime.now(IST).replace(tzinfo=None)

        # Reset on new day
        if self._trade_dates.get(index) != today:
            self._trade_dates[index]  = today
            self._trade_counts[index] = 0
            if index in self._cooldown_until:
                if self._cooldown_until[index].date() < today:
                    del self._cooldown_until[index]

        # Cooldown check (active until tomorrow)
        if index in self._cooldown_until and now < self._cooldown_until[index]:
            return False, (
                f"Post-loss cooldown active — skipping rest of day for {index}. "
                "No new trades until tomorrow."
            )

        # Daily trade cap
        count = self._trade_counts.get(index, 0)
        if count >= MAX_TRADES_PER_DAY:
            return False, (
                f"Daily trade limit ({MAX_TRADES_PER_DAY}) reached for {index}. "
                "One high-quality trade per day — discipline over frequency."
            )

        return True, ""

    def record_trade(self, index: str):
        today = date.today()
        if self._trade_dates.get(index) != today:
            self._trade_dates[index]  = today
            self._trade_counts[index] = 0
        self._trade_counts[index] = self._trade_counts.get(index, 0) + 1

    def record_loss(self, index: str):
        """After a loss, block new trades for the rest of the trading day."""
        # Cooldown expires at tomorrow 9:00 AM
        tomorrow = datetime.combine(date.today() + timedelta(days=1), time(9, 0))
        self._cooldown_until[index] = tomorrow
        logger.warning(
            f"[OptionsEngine] Loss recorded for {index} — "
            "cooldown active until tomorrow 9 AM"
        )

    def record_win(self, index: str):
        """Win: no cooldown, daily limit still applies."""
        logger.info(f"[OptionsEngine] Win recorded for {index}")

    def restore_from_db(self, rows: list):
        """
        Rebuild in-memory state from DB rows after a server restart.

        Each row must be a dict with at least:
            index_name  : str   ('NIFTY' | 'BANKNIFTY')
            status      : str   ('OPEN' | 'CLOSED')
            exit_reason : str | None   ('SL_HIT' | 'TARGET_HIT' | ...)
            trade_date  : date          (date the trade was placed)
            pnl         : float | None  (populated on close)

        Called once at startup by main.py's startup_event().
        Safe to call with an empty list (no-op).
        """
        today = date.today()
        tomorrow_9am = datetime.combine(today + timedelta(days=1), time(9, 0))

        for row in rows:
            index      = row.get("index_name", "").upper()
            status     = row.get("status", "")
            exit_reason = row.get("exit_reason") or ""
            trade_date = row.get("trade_date")
            pnl        = row.get("pnl")

            if not index or trade_date != today:
                continue  # only care about today's trades

            # Restore trade count
            self._trade_dates[index]  = today
            self._trade_counts[index] = self._trade_counts.get(index, 0) + 1

            # Restore cooldown: trade closed at a loss → block rest of day
            if status == "CLOSED" and exit_reason == "SL_HIT":
                self._cooldown_until[index] = tomorrow_9am
                logger.warning(
                    f"[OptionsEngine] Restored post-loss cooldown for {index} "
                    "(SL hit recorded in DB — no new trades today)"
                )

        # Log restored state
        for idx, count in self._trade_counts.items():
            cd = self._cooldown_until.get(idx)
            logger.info(
                f"[OptionsEngine] Restored guard — {idx}: "
                f"{count} trade(s) today"
                + (f", cooldown until {cd}" if cd else "")
            )


class OptionsEngine:

    def __init__(self):
        self._guard = _AntiOvertradeGuard()

    # ══════════════════════════════════════════════════════════════════════════
    # Public API
    # ══════════════════════════════════════════════════════════════════════════

    def generate_signal(
        self,
        candles: List[Dict],
        index: str,
        expiry_date: Optional[date] = None,
        prev_day_high: float = 0.0,
        prev_day_low:  float = 0.0,
        fut_volume_ratio: float = 0.0,  # near-month futures vol ÷ 10-candle avg (0 = skip)
    ) -> BreakoutResult:
        """
        Main entry point. Returns a BreakoutResult whose .signal is the
        authoritative decision. The LLM may NOT change or override it.
        """
        result = BreakoutResult()
        now_ist      = datetime.now(IST).replace(tzinfo=None)
        current_time = now_ist.time()

        # ── Hard time gates ───────────────────────────────────────────────────
        if current_time < NO_TRADE_BEFORE:
            result.failed_filters.append(
                f"Before {NO_TRADE_BEFORE.strftime('%H:%M')} IST — "
                "market-open noise period, waiting for price discovery"
            )
            result.trade_allowed = False
            return result

        if current_time >= NO_TRADE_AFTER:
            result.failed_filters.append(
                f"After {NO_TRADE_AFTER.strftime('%H:%M')} IST — "
                "no new entries, insufficient time + theta decay"
            )
            result.trade_allowed = False
            return result

        if expiry_date and expiry_date == date.today() and current_time >= EXPIRY_CUTOFF:
            result.failed_filters.append(
                f"Expiry day after {EXPIRY_CUTOFF.strftime('%H:%M')} IST — "
                "theta decay accelerating, skipping"
            )
            result.trade_allowed = False
            return result

        # ── Anti-overtrading guard ────────────────────────────────────────────
        allowed, guard_reason = self._guard.is_allowed(index)
        if not allowed:
            result.failed_filters.append(guard_reason)
            result.trade_allowed = False
            return result

        # ── Minimum candles ───────────────────────────────────────────────────
        if not candles or len(candles) < 10:
            result.failed_filters.append(
                f"Only {len(candles) if candles else 0} candles — need ≥ 10 for reliable signal"
            )
            return result

        # ── Build DataFrame ───────────────────────────────────────────────────
        df = pd.DataFrame(candles)
        df.columns = [c.lower() for c in df.columns]
        if "date" in df.columns:
            df = df.rename(columns={"date": "timestamp"})
        for col in ("open", "high", "low", "close", "volume"):
            df[col] = df[col].astype(float)

        # ── Phase 1: Regime detection ─────────────────────────────────────────
        regime, regime_reasons, or_high, or_low, indicators = self._detect_regime(
            df, prev_day_high, prev_day_low
        )
        result.regime     = regime
        result.or_high    = or_high
        result.or_low     = or_low
        result.indicators = indicators
        result.adx        = indicators.get("adx", 0.0)
        result.atr        = indicators.get("atr", 0.0)

        if regime in (MarketRegime.CHOPPY, MarketRegime.SIDEWAYS):
            result.failed_filters.extend(regime_reasons)
            logger.info(
                f"[OptionsEngine] {index} regime={regime.value} → NO_TRADE. "
                f"{regime_reasons}"
            )
            return result

        result.reasons.extend(regime_reasons)

        # ── Phase 2: Breakout detection ───────────────────────────────────────
        signal, passed, failed = self._detect_breakout(
            df, regime, or_high, or_low, indicators, fut_volume_ratio
        )
        result.failed_filters.extend(failed)
        result.reasons.extend(passed)

        if not signal:
            logger.info(
                f"[OptionsEngine] {index} no confirmed breakout. Failed: {failed}"
            )
            return result

        # ── Phase 2.5: Retest confirmation ────────────────────────────────────
        # Require a pullback to the breakout level + resumption before entry.
        # Filters out chasing into a fresh breakout with no proven support/resistance.
        retest_ok, retest_msg = self._detect_retest(df, signal, or_high, or_low)
        if retest_ok:
            result.reasons.append(retest_msg)
        else:
            result.failed_filters.append(retest_msg)
            logger.info(f"[OptionsEngine] {index} retest not confirmed: {retest_msg}")
            return result

        # ── Phase 3: Structure-based index levels ─────────────────────────────
        last_close = float(df["close"].iloc[-1])
        entry, sl, target = self._calculate_index_levels(
            df, signal, last_close, or_high, or_low
        )

        if sl <= 0 or target <= 0:
            result.failed_filters.append(
                "Could not compute valid structure-based SL/target levels"
            )
            return result

        risk = abs(entry - sl)
        rr   = abs(target - entry) / risk if risk > 0 else 0

        if rr < 1.5:
            result.failed_filters.append(
                f"R:R {rr:.2f} below 1.5 minimum — SL is too wide relative to "
                "available target room at current price structure"
            )
            return result

        # ── Trade confirmed ───────────────────────────────────────────────────
        result.signal             = signal
        result.entry_index_price  = round(entry, 2)
        result.sl_index_price     = round(sl, 2)
        result.target_index_price = round(target, 2)

        logger.info(
            f"[OptionsEngine] {index} SIGNAL={signal} regime={regime.value} "
            f"entry={entry:.2f} SL={sl:.2f} target={target:.2f} "
            f"R:R={rr:.2f} ADX={result.adx:.1f} ATR={result.atr:.2f}"
        )
        return result

    def record_trade_outcome(self, index: str, was_loss: bool):
        """Called by the monitoring agent when a trade closes."""
        if was_loss:
            self._guard.record_loss(index)
        else:
            self._guard.record_win(index)

    def register_trade(self, index: str):
        """Call once when a trade is actually placed (not just signalled)."""
        self._guard.record_trade(index)

    # ──────────────────────────────────────────────────────────────────────────
    # Legacy compatibility — route used to call this separately
    # ──────────────────────────────────────────────────────────────────────────

    def calculate_indicators(self, candles: List[Dict]) -> Optional[Dict]:
        """
        Thin backward-compatible wrapper.
        New code should call generate_signal() which computes everything internally.
        """
        if not candles or len(candles) < 5:
            return None
        df = pd.DataFrame(candles)
        df.columns = [c.lower() for c in df.columns]
        close  = df["close"].astype(float)
        high   = df["high"].astype(float)
        low    = df["low"].astype(float)
        vol    = df["volume"].astype(float)
        n      = len(df)
        typical = (high + low + close) / 3
        cum_vol = vol.cumsum()
        vwap = float(
            (typical * vol).cumsum().iloc[-1] / cum_vol.iloc[-1]
            if cum_vol.iloc[-1] > 0
            else close.rolling(min(20, n)).mean().iloc[-1]
        )
        last_close = float(close.iloc[-1])
        return {
            "last_close":    round(last_close, 2),
            "vwap":          round(vwap, 2),
            "price_vs_vwap": "ABOVE" if last_close > vwap else "BELOW",
            "candle_count":  n,
            "data_quality":  "NORMAL" if n >= 35 else "LOW",
        }

    # ══════════════════════════════════════════════════════════════════════════
    # Phase 1 — Regime Detection
    # ══════════════════════════════════════════════════════════════════════════

    def _detect_regime(
        self,
        df: pd.DataFrame,
        prev_day_high: float,
        prev_day_low:  float,
    ) -> Tuple[MarketRegime, List[str], float, float, Dict]:
        """
        Returns (regime, reasons, OR_high, OR_low, indicators_dict).
        reasons explains the regime choice for the LLM summary.
        """
        close = df["close"].astype(float)
        high  = df["high"].astype(float)
        low   = df["low"].astype(float)
        vol   = df["volume"].astype(float)
        n     = len(df)
        last_close = float(close.iloc[-1])

        # ── Opening Range: first 3 × 5-min candles = 9:15–9:30 AM ───────────
        or_n    = min(3, n)
        or_high = float(high.iloc[:or_n].max())
        or_low  = float(low.iloc[:or_n].min())
        or_range     = or_high - or_low
        or_range_pct = or_range / last_close if last_close > 0 else 0.0

        # ── VWAP (fall back to SMA-20 when index volume = 0) ─────────────────
        typical = (high + low + close) / 3
        cum_vol = vol.cumsum()
        if cum_vol.iloc[-1] > 0:
            vwap = float((typical * vol).cumsum().iloc[-1] / cum_vol.iloc[-1])
        else:
            sma = close.rolling(min(20, n)).mean().iloc[-1]
            vwap = float(sma) if not math.isnan(sma) else last_close
        has_volume    = cum_vol.iloc[-1] > 0
        vwap_dist_pct = abs(last_close - vwap) / vwap if vwap > 0 else 0.0

        # ── ATR (14) ──────────────────────────────────────────────────────────
        atr = self._atr(df, min(14, n - 1))

        # ── ADX (14) ──────────────────────────────────────────────────────────
        adx = self._adx(df, min(14, n - 1))

        # ── RSI (14) ──────────────────────────────────────────────────────────
        delta = close.diff()
        ag    = delta.clip(lower=0).ewm(com=13, adjust=False).mean()
        al    = (-delta).clip(lower=0).ewm(com=13, adjust=False).mean()
        rs    = ag / al.replace(0, np.nan)
        rsi   = float((100 - 100 / (1 + rs)).iloc[-1])
        if math.isnan(rsi):
            rsi = 50.0

        # ── EMA 9 / 21 ────────────────────────────────────────────────────────
        ema_9  = float(close.ewm(span=9,  adjust=False).mean().iloc[-1])
        ema_21 = float(close.ewm(span=21, adjust=False).mean().iloc[-1])

        indicators = {
            "last_close":    round(last_close, 2),
            "vwap":          round(vwap, 2),
            "price_vs_vwap": "ABOVE" if last_close > vwap else "BELOW",
            "vwap_dist_pct": round(vwap_dist_pct * 100, 3),
            "or_high":       round(or_high, 2),
            "or_low":        round(or_low, 2),
            "or_range":      round(or_range, 2),
            "or_range_pct":  round(or_range_pct * 100, 3),
            "atr":           round(atr, 2),
            "adx":           round(adx, 1),
            "rsi":           round(rsi, 1),
            "ema_9":         round(ema_9, 2),
            "ema_21":        round(ema_21, 2),
            "prev_day_high": round(prev_day_high, 2),
            "prev_day_low":  round(prev_day_low, 2),
            "candle_count":  n,
            "has_volume":    has_volume,
            "data_quality":  "LOW" if n < 35 else "NORMAL",
        }

        # ── Gate 1: Opening range too small → CHOPPY ─────────────────────────
        if or_range_pct < MIN_OR_RANGE_PCT:
            return (
                MarketRegime.CHOPPY,
                [
                    f"Opening range {or_range_pct*100:.2f}% is below "
                    f"{MIN_OR_RANGE_PCT*100:.1f}% threshold — "
                    "market opened tight/gapped sideways, no breakout edge"
                ],
                or_high, or_low, indicators,
            )

        # ── Gate 2: ADX too low → CHOPPY ─────────────────────────────────────
        if adx < MIN_ADX:
            return (
                MarketRegime.CHOPPY,
                [
                    f"ADX {adx:.1f} < {MIN_ADX:.0f} — "
                    "no sustained directional momentum, market is ranging"
                ],
                or_high, or_low, indicators,
            )

        # ── Gate 3: Price too close to VWAP → SIDEWAYS ───────────────────────
        if vwap_dist_pct < MAX_VWAP_DISTANCE_PCT:
            return (
                MarketRegime.SIDEWAYS,
                [
                    f"Price within {vwap_dist_pct*100:.3f}% of VWAP "
                    f"(threshold {MAX_VWAP_DISTANCE_PCT*100:.2f}%) — "
                    "price is oscillating around institutional fair value, no bias"
                ],
                or_high, or_low, indicators,
            )

        # ── Directional scoring (≥ 3 of 5 needed for a regime) ───────────────
        bull = 0
        bear = 0

        if last_close > vwap:    bull += 1
        else:                    bear += 1

        if ema_9 > ema_21:       bull += 1
        else:                    bear += 1

        if last_close > or_high: bull += 1
        elif last_close < or_low: bear += 1

        if rsi > 55:             bull += 1
        elif rsi < 45:           bear += 1

        if prev_day_high > 0 and last_close > prev_day_high:
            bull += 1
        elif prev_day_low > 0 and last_close < prev_day_low:
            bear += 1

        if bull > bear:
            regime = MarketRegime.TRENDING_UP
            reasons = [
                f"TRENDING_UP — ADX {adx:.1f} (trending), price {vwap_dist_pct*100:.2f}% "
                f"above VWAP, bullish score {bull}/{bull+bear} "
                f"(EMA: {ema_9:.0f}>{ema_21:.0f}, RSI: {rsi:.0f})"
            ]
        elif bear > bull:
            regime = MarketRegime.TRENDING_DOWN
            reasons = [
                f"TRENDING_DOWN — ADX {adx:.1f} (trending), price {vwap_dist_pct*100:.2f}% "
                f"below VWAP, bearish score {bear}/{bull+bear} "
                f"(EMA: {ema_9:.0f}<{ema_21:.0f}, RSI: {rsi:.0f})"
            ]
        else:
            regime = MarketRegime.SIDEWAYS
            reasons = [
                f"No clear direction: bullish={bull} bearish={bear} — "
                "signals are mixed, cannot confidently assign regime"
            ]

        return regime, reasons, or_high, or_low, indicators

    # ══════════════════════════════════════════════════════════════════════════
    # Phase 2 — Breakout Detection
    # ══════════════════════════════════════════════════════════════════════════

    def _detect_breakout(
        self,
        df: pd.DataFrame,
        regime: MarketRegime,
        or_high: float,
        or_low:  float,
        indicators: Dict,
        fut_volume_ratio: float = 0.0,
    ) -> Tuple[Optional[str], List[str], List[str]]:
        """
        Returns (signal|None, gates_passed, gates_failed).
        All gates must pass. First failure returns immediately.
        """
        close  = df["close"].astype(float)
        open_  = df["open"].astype(float)
        high   = df["high"].astype(float)
        low    = df["low"].astype(float)
        vol    = df["volume"].astype(float)
        n      = len(df)

        if n < 4:
            return None, [], ["Need ≥ 4 candles for breakout detection"]

        last_close = float(close.iloc[-1])
        last_open  = float(open_.iloc[-1])
        last_high  = float(high.iloc[-1])
        last_low   = float(low.iloc[-1])
        last_vol   = float(vol.iloc[-1])

        passed: List[str] = []
        failed: List[str] = []

        prev_day_high = indicators.get("prev_day_high", 0.0)
        prev_day_low  = indicators.get("prev_day_low",  0.0)
        has_volume    = indicators.get("has_volume", False)

        # Determine direction and breakout level
        if regime == MarketRegime.TRENDING_UP:
            direction = "BUY_CE"
            # Primary level = OR high; extend to prev-day high if it's higher
            breakout_level = or_high
            if prev_day_high > or_high:
                breakout_level = prev_day_high
                passed.append(
                    f"Using previous-day high ₹{prev_day_high:.2f} as breakout level "
                    f"(above OR high ₹{or_high:.2f})"
                )
            did_break     = last_close > breakout_level * (1 + BREAKOUT_BUFFER)
            body_bullish  = last_close > last_open
            body_size     = last_close - last_open
            candle_range  = last_high - last_low
        else:  # TRENDING_DOWN → BUY_PE
            direction = "BUY_PE"
            breakout_level = or_low
            if prev_day_low > 0 and prev_day_low < or_low:
                breakout_level = prev_day_low
                passed.append(
                    f"Using previous-day low ₹{prev_day_low:.2f} as breakout level "
                    f"(below OR low ₹{or_low:.2f})"
                )
            did_break    = last_close < breakout_level * (1 - BREAKOUT_BUFFER)
            body_bullish = last_close < last_open   # bearish body for PE
            body_size    = last_open - last_close
            candle_range = last_high - last_low

        level_side = "above" if direction == "BUY_CE" else "below"

        # ── Gate 1: Breakout confirmed ────────────────────────────────────────
        if did_break:
            passed.append(
                f"Breakout: close ₹{last_close:.2f} is {level_side} "
                f"₹{breakout_level:.2f} with ≥{BREAKOUT_BUFFER*100:.2f}% buffer"
            )
        else:
            failed.append(
                f"No breakout: close ₹{last_close:.2f} has not cleared "
                f"₹{breakout_level:.2f} {level_side} by the required {BREAKOUT_BUFFER*100:.2f}% buffer"
            )
            return None, passed, failed

        # ── Gate 2: VWAP alignment ────────────────────────────────────────────
        pvwap = indicators.get("price_vs_vwap", "")
        vwap  = indicators.get("vwap", 0)
        if direction == "BUY_CE" and pvwap == "ABOVE":
            passed.append(
                f"VWAP alignment: price above VWAP ₹{vwap:.2f} — bullish institutional bias"
            )
        elif direction == "BUY_PE" and pvwap == "BELOW":
            passed.append(
                f"VWAP alignment: price below VWAP ₹{vwap:.2f} — bearish institutional bias"
            )
        else:
            failed.append(
                f"VWAP misalignment: {direction} signal but price is "
                f"{'above' if pvwap=='ABOVE' else 'below'} VWAP ₹{vwap:.2f} — "
                "breakout direction conflicts with institutional reference level"
            )
            return None, passed, failed

        # ── Gate 3: Candle body strength (no wick-heavy candles) ─────────────
        body_ratio = body_size / candle_range if candle_range > 0 else 0.0
        body_dir   = ("bullish" if direction == "BUY_CE" else "bearish")
        if body_bullish and body_ratio >= MIN_BODY_RATIO:
            passed.append(
                f"Strong {body_dir} candle body: {body_ratio:.0%} of range "
                f"≥ {MIN_BODY_RATIO:.0%} — conviction, not a wick spike"
            )
        elif not body_bullish:
            failed.append(
                f"Wrong candle body: {'bearish' if direction=='BUY_CE' else 'bullish'} "
                f"body on {body_dir} breakout — wick-dominated, no conviction"
            )
            return None, passed, failed
        else:
            failed.append(
                f"Weak body ratio {body_ratio:.0%} < {MIN_BODY_RATIO:.0%} — "
                "excessive wicks indicate buying/selling absorbed at this level"
            )
            return None, passed, failed

        # ── Gate 4: Futures volume confirmation ───────────────────────────────
        # Uses near-month NIFTY/BANKNIFTY futures volume vs 10-candle average.
        # fut_volume_ratio = 0.0 means the route could not fetch it → skip gracefully.
        if fut_volume_ratio > 0:
            if fut_volume_ratio >= MIN_FUT_VOLUME_RATIO:
                passed.append(
                    f"Futures volume: {fut_volume_ratio:.1f}× 10-candle average — "
                    "strong institutional participation confirms breakout"
                )
            else:
                failed.append(
                    f"Weak futures volume: {fut_volume_ratio:.1f}× 10-candle average "
                    f"(need ≥ {MIN_FUT_VOLUME_RATIO}×) — low-conviction move, "
                    "breakout not backed by institutions"
                )
                return None, passed, failed
        else:
            passed.append(
                "Futures volume check skipped — data unavailable; "
                "price-action gates applied instead"
            )

        # ── Gate 5: Confirmation (multi-candle hold above/below level) ────────
        confirmed = self._is_confirmed(df, direction, breakout_level, n)
        if confirmed:
            passed.append(
                f"Multi-candle confirmation: last 2 closes both {level_side} "
                f"₹{breakout_level:.2f} — breakout is holding, not a single spike"
            )
        else:
            # Single-candle breakout — allow but flag for LLM to note
            passed.append(
                "Single-candle breakout (no retest yet) — all other gates passed. "
                "Entry on pullback to breakout level preferred if time allows."
            )

        return direction, passed, failed

    def _is_confirmed(
        self, df: pd.DataFrame, direction: str, level: float, n: int
    ) -> bool:
        """True if the last 2 closes both cleared the breakout level."""
        if n < 2:
            return False
        last_two = df["close"].astype(float).iloc[n - 2: n].values
        if direction == "BUY_CE":
            return all(c > level for c in last_two)
        return all(c < level for c in last_two)

    def _detect_retest(
        self,
        df: pd.DataFrame,
        signal: str,
        or_high: float,
        or_low: float,
    ) -> Tuple[bool, str]:
        """
        Require a pullback to the breakout level + resumption before entry.
        Filters out chasing fresh breakouts; ensures entry from proven S/R.

        For BUY_CE (upside breakout):
          1. Some candle K broke above OR high (close > level + buffer)
          2. A later candle pulled back: its low ≤ OR high × (1 + RETEST_BUFFER)
          3. The last candle closes above OR high — resumption confirmed

        For BUY_PE (downside breakdown):
          1. Some candle K broke below OR low
          2. A later candle pulled up: its high ≥ OR low × (1 - RETEST_BUFFER)
          3. The last candle closes below OR low — resumption confirmed
        """
        close = df["close"].astype(float).values
        high  = df["high"].astype(float).values
        low   = df["low"].astype(float).values
        n     = len(df)

        if n < 6:
            return False, "Need ≥ 6 candles for retest detection"

        if signal == "BUY_CE":
            level = or_high
            # Step 1: Find the first breakout candle (after OR formation, index 3+)
            breakout_idx = None
            for i in range(3, n - 1):
                if close[i] > level * (1 + BREAKOUT_BUFFER):
                    breakout_idx = i
                    break

            if breakout_idx is None:
                return False, (
                    f"No confirmed breakout above OR high ₹{level:.2f} found in history"
                )

            # Step 2: Find a retest candle after the breakout (low touches level)
            retest_found = False
            for i in range(breakout_idx + 1, n):
                if low[i] <= level * (1 + RETEST_BUFFER):
                    retest_found = True
                    break

            if not retest_found:
                return False, (
                    f"Breakout above ₹{level:.2f} confirmed at candle {breakout_idx} "
                    "but no retest pullback yet — waiting for price to pull back "
                    "to OR high before entering"
                )

            # Step 3: Last close must hold above level (resumption)
            if close[-1] <= level:
                return False, (
                    f"Retest touched OR high ₹{level:.2f} but current close "
                    f"₹{close[-1]:.2f} did not resume above it — possible failed retest"
                )

            return True, (
                f"Retest confirmed: price broke ₹{level:.2f}, pulled back to test it "
                f"as support, and resumed — entering from proven demand zone"
            )

        else:  # BUY_PE — downside breakdown
            level = or_low
            breakout_idx = None
            for i in range(3, n - 1):
                if close[i] < level * (1 - BREAKOUT_BUFFER):
                    breakout_idx = i
                    break

            if breakout_idx is None:
                return False, (
                    f"No confirmed breakdown below OR low ₹{level:.2f} found in history"
                )

            retest_found = False
            for i in range(breakout_idx + 1, n):
                if high[i] >= level * (1 - RETEST_BUFFER):
                    retest_found = True
                    break

            if not retest_found:
                return False, (
                    f"Breakdown below ₹{level:.2f} confirmed at candle {breakout_idx} "
                    "but no retest bounce yet — waiting for price to pull back "
                    "to OR low before entering"
                )

            if close[-1] >= level:
                return False, (
                    f"Retest touched OR low ₹{level:.2f} but current close "
                    f"₹{close[-1]:.2f} did not resume below it — possible failed breakdown"
                )

            return True, (
                f"Retest confirmed: price broke ₹{level:.2f}, pulled back to test it "
                f"as resistance, and resumed — entering from proven supply zone"
            )

    # ══════════════════════════════════════════════════════════════════════════
    # Phase 3 — Structure-Based Index Risk Levels
    # ══════════════════════════════════════════════════════════════════════════

    def _calculate_index_levels(
        self,
        df: pd.DataFrame,
        signal: str,
        last_close: float,
        or_high: float,
        or_low:  float,
    ) -> Tuple[float, float, float]:
        """
        Returns (entry, stop_loss, target) in index points.
        SL is structure-based (swing low/high of last 5 candles).
        Target = entry + 2× risk.
        """
        n        = len(df)
        lookback = min(5, n)

        if signal == "BUY_CE":
            # SL = lowest low of last 5 candles; must be below the breakout level (OR high)
            swing_low = float(df["low"].astype(float).iloc[n - lookback: n].min())
            sl = min(swing_low, or_high)
            if sl >= last_close:
                sl = or_low  # wider: use OR low
            if sl >= last_close:
                sl = round(last_close * 0.98, 2)  # last resort: 2% floor
            entry  = last_close
            risk   = entry - sl
            target = round(entry + 2.0 * risk, 2)
        else:  # BUY_PE
            # SL = highest high of last 5 candles; must be above the breakdown level (OR low)
            swing_high = float(df["high"].astype(float).iloc[n - lookback: n].max())
            sl = max(swing_high, or_low)
            if sl <= last_close:
                sl = or_high
            if sl <= last_close:
                sl = round(last_close * 1.02, 2)
            entry  = last_close
            risk   = sl - entry
            target = round(entry - 2.0 * risk, 2)

        return entry, round(sl, 2), round(target, 2)

    # ══════════════════════════════════════════════════════════════════════════
    # Indicator Helpers
    # ══════════════════════════════════════════════════════════════════════════

    def _atr(self, df: pd.DataFrame, period: int = 14) -> float:
        high  = df["high"].astype(float)
        low   = df["low"].astype(float)
        close = df["close"].astype(float)
        prev_c = close.shift(1)
        tr = pd.concat([
            high - low,
            (high - prev_c).abs(),
            (low  - prev_c).abs(),
        ], axis=1).max(axis=1)
        val = tr.ewm(span=period, adjust=False).mean().iloc[-1]
        return float(val) if not math.isnan(val) else 0.0

    def _adx(self, df: pd.DataFrame, period: int = 14) -> float:
        """
        Standard Wilder ADX.
        ADX < 20  = no trend (choppy)
        ADX 20–25 = emerging trend
        ADX > 25  = strong trend
        """
        if len(df) < period + 2:
            return 0.0

        high  = df["high"].astype(float)
        low   = df["low"].astype(float)
        close = df["close"].astype(float)

        prev_close = close.shift(1)
        prev_high  = high.shift(1)
        prev_low   = low.shift(1)

        tr = pd.concat([
            high - low,
            (high - prev_close).abs(),
            (low  - prev_close).abs(),
        ], axis=1).max(axis=1)

        up_move   = high - prev_high
        down_move = prev_low - low

        plus_dm  = pd.Series(
            np.where((up_move > down_move) & (up_move > 0), up_move, 0.0),
            index=df.index,
        )
        minus_dm = pd.Series(
            np.where((down_move > up_move) & (down_move > 0), down_move, 0.0),
            index=df.index,
        )

        atr_s      = tr.ewm(span=period, adjust=False).mean()
        plus_di_s  = 100 * plus_dm.ewm(span=period, adjust=False).mean() / atr_s.replace(0, np.nan)
        minus_di_s = 100 * minus_dm.ewm(span=period, adjust=False).mean() / atr_s.replace(0, np.nan)

        dx_denom = (plus_di_s + minus_di_s).replace(0, np.nan)
        dx  = 100 * (plus_di_s - minus_di_s).abs() / dx_denom
        adx = dx.ewm(span=period, adjust=False).mean().iloc[-1]

        return float(adx) if not math.isnan(adx) else 0.0


options_engine = OptionsEngine()
