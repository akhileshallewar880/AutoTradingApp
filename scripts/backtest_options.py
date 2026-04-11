"""
Options Strategy Backtester — Walk-Forward Replay
===================================================
Replays the current regime-based ORB engine against a full day of historical
5-min candles so you can see exactly what the live system would have done.

Usage:
    python scripts/backtest_options.py \\
        --index NIFTY \\
        --date 2025-04-14 \\
        --strike 24000 \\
        --api-key YOUR_API_KEY \\
        --access-token YOUR_ACCESS_TOKEN

    # Optional flags:
        --lots 1
        --capital 200000
        --expiry 2025-04-17   (default: same as --date)

Note on April 13 2025:
    April 13 2025 is a Sunday — not a trading day.
    The closest trading session is April 14 2025 (Monday).
    Use --date 2025-04-14 for that session.

How it works:
    1. Fetch full-day NIFTY 5-min candles (9:15 AM → 3:30 PM)
    2. Fetch NIFTY FUT near-month candles for volume ratio
    3. Walk forward one candle at a time starting from candle 4 (9:30 AM)
    4. At each step run: regime → breakout → retest → levels
    5. First valid signal fires the simulated trade
    6. Replay remaining candles → check SL / 1R-partial / target / time exit
    7. If a strike is given, also fetch the historical option premium candles
       to report actual premium P&L (not just index-point P&L)
    8. Print a colour-coded trade report
"""

import argparse
import sys
import os
from datetime import date, datetime, time, timedelta
from typing import Dict, List, Optional, Tuple
import math

import pandas as pd
import numpy as np

# ── Make sure the app package is importable ───────────────────────────────────
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from app.services.zerodha_service import zerodha_service
from app.engines.options_engine import (
    OptionsEngine, BreakoutResult, MarketRegime,
    NO_TRADE_BEFORE, NO_TRADE_AFTER, EXPIRY_CUTOFF,
    MIN_OR_RANGE_PCT, MIN_ADX, MAX_VWAP_DISTANCE_PCT,
    MIN_FUT_VOLUME_RATIO, BREAKOUT_BUFFER, RETEST_BUFFER, ATM_DELTA,
)
import pytz

IST = pytz.timezone("Asia/Kolkata")

# ── ANSI colours ──────────────────────────────────────────────────────────────
GREEN  = "\033[92m"
RED    = "\033[91m"
YELLOW = "\033[93m"
BLUE   = "\033[94m"
CYAN   = "\033[96m"
BOLD   = "\033[1m"
RESET  = "\033[0m"


# ═════════════════════════════════════════════════════════════════════════════
# Data fetching
# ═════════════════════════════════════════════════════════════════════════════

INDEX_TOKENS = {
    "NIFTY":     256265,
    "BANKNIFTY": 260105,
}

LOT_SIZES = {
    "NIFTY":     75,
    "BANKNIFTY": 30,
}


def _fetch_candles(token: int, from_dt: datetime, to_dt: datetime, interval: str) -> List[Dict]:
    candles = zerodha_service.kite.historical_data(
        token, from_dt, to_dt, interval, continuous=False, oi=False
    )
    return [
        {
            "timestamp": c["date"] if isinstance(c["date"], datetime) else datetime.fromisoformat(str(c["date"])),
            "open":   float(c["open"]),
            "high":   float(c["high"]),
            "low":    float(c["low"]),
            "close":  float(c["close"]),
            "volume": float(c.get("volume") or 0),
        }
        for c in candles
    ]


def fetch_index_candles(index: str, trade_date: date) -> List[Dict]:
    token = INDEX_TOKENS[index.upper()]
    from_dt = datetime.combine(trade_date, time(9, 15))
    to_dt   = datetime.combine(trade_date, time(15, 30))
    print(f"  Fetching {index} 5-min candles for {trade_date}…")
    return _fetch_candles(token, from_dt, to_dt, "5minute")


def fetch_prev_day_ohlc(index: str, trade_date: date) -> Dict:
    token   = INDEX_TOKENS[index.upper()]
    prev_day = trade_date - timedelta(days=1)
    while prev_day.weekday() >= 5:
        prev_day -= timedelta(days=1)
    from_dt = datetime.combine(prev_day, time(9, 15))
    to_dt   = datetime.combine(prev_day, time(15, 30))
    print(f"  Fetching prev-day OHLC ({prev_day})…")
    try:
        candles = _fetch_candles(token, from_dt, to_dt, "day")
        if candles:
            c = candles[-1]
            return {"high": c["high"], "low": c["low"], "open": c["open"], "close": c["close"]}
    except Exception as e:
        print(f"  {YELLOW}Prev-day OHLC failed: {e}{RESET}")
    return {"high": 0.0, "low": 0.0, "open": 0.0, "close": 0.0}


def fetch_fut_volume_ratio(index: str, trade_date: date, instruments: List[Dict]) -> float:
    """Return last 5-min candle volume / avg of previous 10 for front-month futures."""
    index_upper = index.upper()
    futs = [
        i for i in instruments
        if i.get("name") == index_upper
        and i.get("instrument_type") == "FUT"
        and i.get("expiry") and i["expiry"] >= trade_date
    ]
    if not futs:
        print(f"  {YELLOW}No futures found — volume check will be skipped{RESET}")
        return 0.0

    futs.sort(key=lambda x: x["expiry"])
    near = futs[0]
    token = near["instrument_token"]
    print(f"  Fetching {near.get('tradingsymbol')} futures volume…")
    try:
        from_dt  = datetime.combine(trade_date, time(9, 15))
        to_dt    = datetime.combine(trade_date, time(15, 30))
        candles  = _fetch_candles(token, from_dt, to_dt, "5minute")
        vols     = [c["volume"] for c in candles]
        if len(vols) < 3:
            return 0.0
        last_vol = vols[-1]
        lookback = vols[max(0, len(vols) - 11): len(vols) - 1]
        avg_vol  = sum(lookback) / len(lookback) if lookback else 0.0
        return round(last_vol / avg_vol, 2) if avg_vol > 0 else 0.0
    except Exception as e:
        print(f"  {YELLOW}Futures volume fetch failed: {e}{RESET}")
        return 0.0


def fetch_option_candles(
    index: str, trade_date: date, expiry_date: date,
    strike: int, opt_type: str, instruments: List[Dict],
) -> List[Dict]:
    """Fetch 5-min candles for the historical option contract."""
    sym = f"{index.upper()}{expiry_date.strftime('%y%b').upper()}{strike}{opt_type}"
    matches = [
        i for i in instruments
        if i.get("tradingsymbol") == sym
        and i.get("instrument_type") == opt_type
        and i.get("expiry") == expiry_date
    ]
    if not matches:
        # Try alternate formats (Zerodha symbol format)
        day_str = str(expiry_date.day).zfill(2) if expiry_date.day >= 10 else str(expiry_date.day)
        for i in instruments:
            ts = i.get("tradingsymbol", "")
            if (
                ts.startswith(index.upper())
                and ts.endswith(f"{strike}{opt_type}")
                and i.get("expiry") == expiry_date
                and i.get("instrument_type") == opt_type
            ):
                matches.append(i)

    if not matches:
        print(f"  {YELLOW}No option contract found for {sym} / expiry={expiry_date}{RESET}")
        return []

    token = matches[0]["instrument_token"]
    print(f"  Fetching {matches[0]['tradingsymbol']} premium candles…")
    try:
        from_dt = datetime.combine(trade_date, time(9, 15))
        to_dt   = datetime.combine(trade_date, time(15, 30))
        return _fetch_candles(token, from_dt, to_dt, "5minute")
    except Exception as e:
        print(f"  {YELLOW}Option candle fetch failed: {e}{RESET}")
        return []


# ═════════════════════════════════════════════════════════════════════════════
# Walk-forward engine wrapper (bypasses live-time gates)
# ═════════════════════════════════════════════════════════════════════════════

class BacktestEngine:
    """
    Thin wrapper around OptionsEngine internals.
    Bypasses `datetime.now()` gates — uses the candle timestamp instead.
    Anti-overtrading guard is also bypassed (backtest = infinite attempts).
    """

    def __init__(self):
        self._engine = OptionsEngine()

    def run_at(
        self,
        candles: List[Dict],   # candles up to and including current step
        candle_time: time,     # the timestamp of the last candle
        index: str,
        expiry_date: date,
        trade_date: date,
        prev_day_high: float,
        prev_day_low: float,
        fut_volume_ratio: float,
    ) -> BreakoutResult:
        """Run the full pipeline on `candles` as if the time is `candle_time`."""
        result = BreakoutResult()

        # ── Simulated time gates ──────────────────────────────────────────────
        if candle_time < NO_TRADE_BEFORE:
            result.failed_filters.append(
                f"Before {NO_TRADE_BEFORE.strftime('%H:%M')} IST"
            )
            return result

        if candle_time >= NO_TRADE_AFTER:
            result.failed_filters.append(
                f"After {NO_TRADE_AFTER.strftime('%H:%M')} IST"
            )
            return result

        if expiry_date == trade_date and candle_time >= EXPIRY_CUTOFF:
            result.failed_filters.append(
                f"Expiry day after {EXPIRY_CUTOFF.strftime('%H:%M')} IST"
            )
            return result

        if len(candles) < 10:
            result.failed_filters.append(
                f"Only {len(candles)} candles — need ≥ 10"
            )
            return result

        # ── Convert to DataFrame ──────────────────────────────────────────────
        df = pd.DataFrame(candles)
        df.columns = [c.lower() for c in df.columns]
        if "date" in df.columns:
            df = df.rename(columns={"date": "timestamp"})
        for col in ("open", "high", "low", "close", "volume"):
            df[col] = df[col].astype(float)

        # ── Phases (delegate to engine's private methods) ─────────────────────
        regime, regime_reasons, or_high, or_low, indicators = \
            self._engine._detect_regime(df, prev_day_high, prev_day_low)

        result.regime     = regime
        result.or_high    = or_high
        result.or_low     = or_low
        result.indicators = indicators
        result.adx        = indicators.get("adx", 0.0)
        result.atr        = indicators.get("atr", 0.0)

        if regime in (MarketRegime.CHOPPY, MarketRegime.SIDEWAYS):
            result.failed_filters.extend(regime_reasons)
            return result

        result.reasons.extend(regime_reasons)

        signal, passed, failed = self._engine._detect_breakout(
            df, regime, or_high, or_low, indicators, fut_volume_ratio
        )
        result.failed_filters.extend(failed)
        result.reasons.extend(passed)

        if not signal:
            return result

        retest_ok, retest_msg = self._engine._detect_retest(df, signal, or_high, or_low)
        if retest_ok:
            result.reasons.append(retest_msg)
        else:
            result.failed_filters.append(retest_msg)
            return result

        last_close = float(df["close"].iloc[-1])
        entry, sl, target = self._engine._calculate_index_levels(
            df, signal, last_close, or_high, or_low
        )

        if sl <= 0 or target <= 0:
            result.failed_filters.append("Could not compute valid structure-based SL/target")
            return result

        risk = abs(entry - sl)
        rr   = abs(target - entry) / risk if risk > 0 else 0
        if rr < 1.5:
            result.failed_filters.append(
                f"R:R {rr:.2f} < 1.5 minimum — structure SL too wide"
            )
            return result

        result.signal             = signal
        result.entry_index_price  = round(entry, 2)
        result.sl_index_price     = round(sl, 2)
        result.target_index_price = round(target, 2)
        return result


# ═════════════════════════════════════════════════════════════════════════════
# Trade simulator
# ═════════════════════════════════════════════════════════════════════════════

def get_option_premium_at(opt_candles: List[Dict], ts: datetime) -> float:
    """Return the option close price at or just after `ts`."""
    for c in opt_candles:
        if c["timestamp"] >= ts:
            return c["close"]
    return opt_candles[-1]["close"] if opt_candles else 0.0


def simulate_trade(
    signal: str,
    entry_candle_idx: int,
    index_candles: List[Dict],
    opt_candles: List[Dict],
    entry_index: float,
    sl_index: float,
    target_index: float,
    entry_premium: float,
    lots: int,
    lot_size: int,
) -> Dict:
    """
    Replay candles from the entry point forward, applying:
      - SL hit (index touches sl_index)
      - Partial exit at 1R (50% lots exited)
      - Target hit at 2R
      - Time exit at 3:00 PM
      - Structure trailing SL update every candle (last 2 candle lows/highs)
    Returns a detailed result dict.
    """
    is_ce     = signal == "BUY_CE"
    quantity  = lots * lot_size
    risk_idx  = abs(entry_index - sl_index)

    # Premium levels (derived from index levels via ATM delta)
    idx_risk_pts   = risk_idx
    sl_premium     = max(entry_premium - idx_risk_pts * ATM_DELTA, entry_premium * 0.75, 0.05)
    target_premium = entry_premium + 2.0 * (entry_premium - sl_premium)
    partial_premium= entry_premium + 1.0 * (entry_premium - sl_premium)

    current_sl_idx = sl_index
    partial_done   = False
    qty_remaining  = quantity
    partial_pnl    = 0.0
    exit_reason    = None
    exit_time      = None
    exit_idx_price = None
    exit_premium   = None

    events = []

    for i in range(entry_candle_idx + 1, len(index_candles)):
        c   = index_candles[i]
        ts  = c["timestamp"]
        hi  = c["high"]
        lo  = c["low"]
        cls = c["close"]

        # ── Time exit at 3 PM ─────────────────────────────────────────────────
        if ts.time() >= time(15, 0):
            exit_reason    = "TIME EXIT (3:00 PM)"
            exit_time      = ts
            exit_idx_price = cls
            exit_premium   = get_option_premium_at(opt_candles, ts) if opt_candles else 0.0
            break

        # ── Structure trailing SL ─────────────────────────────────────────────
        lookback = index_candles[max(0, i - 1): i + 1]  # last 2 candles
        if is_ce:
            new_sl_idx = min(float(x["low"]) for x in lookback)
            if new_sl_idx > current_sl_idx:
                current_sl_idx = new_sl_idx
                events.append(
                    f"  {CYAN}[{ts.strftime('%H:%M')}] Trailing SL → index ₹{current_sl_idx:.2f}{RESET}"
                )
        else:
            new_sl_idx = max(float(x["high"]) for x in lookback)
            if new_sl_idx < current_sl_idx:
                current_sl_idx = new_sl_idx
                events.append(
                    f"  {CYAN}[{ts.strftime('%H:%M')}] Trailing SL → index ₹{current_sl_idx:.2f}{RESET}"
                )

        # ── SL hit ────────────────────────────────────────────────────────────
        sl_hit = (is_ce and lo <= current_sl_idx) or (not is_ce and hi >= current_sl_idx)
        if sl_hit:
            exit_reason    = "SL HIT"
            exit_time      = ts
            exit_idx_price = current_sl_idx
            exit_premium   = get_option_premium_at(opt_candles, ts) if opt_candles else 0.0
            break

        # ── Partial exit at 1R ────────────────────────────────────────────────
        if not partial_done:
            partial_hit = (is_ce and hi >= entry_index + risk_idx) or \
                          (not is_ce and lo <= entry_index - risk_idx)
            if partial_hit:
                half_qty    = quantity // 2
                p_pnl       = (partial_premium - entry_premium) * half_qty if opt_candles else \
                              risk_idx * ATM_DELTA * half_qty
                partial_pnl = round(p_pnl, 2)
                qty_remaining = quantity - half_qty
                partial_done  = True
                # Move SL to breakeven
                current_sl_idx = entry_index
                events.append(
                    f"  {GREEN}[{ts.strftime('%H:%M')}] PARTIAL EXIT 50% @ 1R"
                    f"  index≈{entry_index + risk_idx:.2f}"
                    f"  prem≈₹{partial_premium:.2f}"
                    f"  pnl=₹{partial_pnl:+.0f}"
                    f"  SL → breakeven ₹{entry_index:.2f}{RESET}"
                )

        # ── Target hit ────────────────────────────────────────────────────────
        target_hit = (is_ce and hi >= entry_index + 2 * risk_idx) or \
                     (not is_ce and lo <= entry_index - 2 * risk_idx)
        if target_hit:
            exit_reason    = "TARGET HIT (2R)"
            exit_time      = ts
            exit_idx_price = entry_index + (2 * risk_idx if is_ce else -2 * risk_idx)
            exit_premium   = get_option_premium_at(opt_candles, ts) if opt_candles else 0.0
            break

    else:
        # Loop completed without SL/target — use last candle
        last = index_candles[-1]
        exit_reason    = "END OF DAY"
        exit_time      = last["timestamp"]
        exit_idx_price = last["close"]
        exit_premium   = get_option_premium_at(opt_candles, last["timestamp"]) if opt_candles else 0.0

    # ── P&L calculation ───────────────────────────────────────────────────────
    if opt_candles and exit_premium and exit_premium > 0:
        # Use actual option premium P&L
        remaining_pnl  = round((exit_premium - entry_premium) * qty_remaining, 2)
        total_pnl      = round(partial_pnl + remaining_pnl, 2)
        pnl_source     = "option premium"
    else:
        # Approximate via index points × ATM delta
        if exit_idx_price:
            idx_move      = (exit_idx_price - entry_index) if is_ce else (entry_index - exit_idx_price)
            remaining_pnl = round(idx_move * ATM_DELTA * qty_remaining, 2)
        else:
            remaining_pnl = 0.0
        total_pnl  = round(partial_pnl + remaining_pnl, 2)
        pnl_source = "index delta approx"

    return {
        "exit_reason":    exit_reason,
        "exit_time":      exit_time,
        "exit_idx_price": exit_idx_price,
        "exit_premium":   exit_premium,
        "entry_premium":  entry_premium,
        "sl_premium":     sl_premium,
        "target_premium": target_premium,
        "partial_premium":partial_premium,
        "partial_done":   partial_done,
        "partial_pnl":    partial_pnl,
        "remaining_pnl":  remaining_pnl,
        "total_pnl":      total_pnl,
        "quantity":       quantity,
        "qty_remaining":  qty_remaining,
        "pnl_source":     pnl_source,
        "events":         events,
    }


# ═════════════════════════════════════════════════════════════════════════════
# Report printer
# ═════════════════════════════════════════════════════════════════════════════

def _sep(char="─", n=70):
    return char * n


def print_report(
    index: str,
    trade_date: date,
    expiry_date: date,
    strike: int,
    signal_candle: Optional[Dict],
    result: BreakoutResult,
    trade: Optional[Dict],
    candle_log: List[str],
):
    print()
    print(BOLD + _sep("═") + RESET)
    print(BOLD + f"  BACKTEST REPORT — {index} {trade_date}  (strike {strike})" + RESET)
    print(BOLD + _sep("═") + RESET)

    # ── Candle-by-candle gate log ─────────────────────────────────────────────
    print()
    print(BOLD + "CANDLE-BY-CANDLE GATE LOG" + RESET)
    print(_sep())
    for line in candle_log:
        print(line)

    # ── Engine final verdict ──────────────────────────────────────────────────
    print()
    print(BOLD + "ENGINE VERDICT" + RESET)
    print(_sep())
    print(f"  Regime:  {result.regime.value}")
    print(f"  Signal:  {BOLD}{result.signal}{RESET}")
    print(f"  OR high: ₹{result.or_high:.2f}  OR low: ₹{result.or_low:.2f}")
    print(f"  ADX:     {result.adx:.1f}   ATR: {result.atr:.2f}")

    if result.reasons:
        print()
        print("  Gates passed:")
        for r in result.reasons:
            print(f"    {GREEN}✓ {r}{RESET}")

    if result.failed_filters:
        print()
        print("  Gates failed:")
        for f in result.failed_filters:
            print(f"    {RED}✗ {f}{RESET}")

    if result.signal == "NO_TRADE":
        print()
        print(RED + BOLD + "  NO TRADE — Strategy correctly sat out this session." + RESET)
        print(_sep("═"))
        return

    # ── Entry setup ───────────────────────────────────────────────────────────
    print()
    print(BOLD + "ENTRY SETUP" + RESET)
    print(_sep())
    if signal_candle:
        ts = signal_candle["timestamp"]
        print(f"  Signal candle:    {ts.strftime('%H:%M IST')}  "
              f"O={signal_candle['open']:.2f}  H={signal_candle['high']:.2f}  "
              f"L={signal_candle['low']:.2f}  C={signal_candle['close']:.2f}")
    print(f"  Index entry:      ₹{result.entry_index_price:.2f}")
    print(f"  Index SL:         ₹{result.sl_index_price:.2f}   "
          f"(risk {abs(result.entry_index_price - result.sl_index_price):.2f} pts)")
    print(f"  Index target:     ₹{result.target_index_price:.2f}   "
          f"(reward {abs(result.target_index_price - result.entry_index_price):.2f} pts)")
    risk_pts = abs(result.entry_index_price - result.sl_index_price)
    rr = abs(result.target_index_price - result.entry_index_price) / risk_pts if risk_pts else 0
    print(f"  R:R (index):      {rr:.2f}")

    if trade:
        print()
        print(f"  Option type:      {result.signal}  strike {strike}")
        print(f"  Entry premium:    ₹{trade['entry_premium']:.2f}")
        print(f"  SL premium:       ₹{trade['sl_premium']:.2f}  "
              f"(max loss/unit ₹{trade['entry_premium'] - trade['sl_premium']:.2f})")
        print(f"  Partial @ 1R:     ₹{trade['partial_premium']:.2f}   "
              f"(50% exit — SL → breakeven)")
        print(f"  Target @ 2R:      ₹{trade['target_premium']:.2f}  "
              f"(no cap — remaining runs)")
        print(f"  Quantity:         {trade['quantity']}  ({trade['quantity']//LOT_SIZES.get(index,75)} lots × "
              f"{LOT_SIZES.get(index,75)} lot size)")

    # ── Trade events ──────────────────────────────────────────────────────────
    if trade and trade["events"]:
        print()
        print(BOLD + "TRADE EVENTS" + RESET)
        print(_sep())
        for ev in trade["events"]:
            print(ev)

    # ── Trade outcome ─────────────────────────────────────────────────────────
    if trade:
        print()
        print(BOLD + "TRADE OUTCOME" + RESET)
        print(_sep())
        reason = trade["exit_reason"]
        xt     = trade["exit_time"].strftime("%H:%M IST") if trade["exit_time"] else "—"
        print(f"  Exit reason:   {reason}")
        print(f"  Exit time:     {xt}")
        if trade["exit_idx_price"]:
            print(f"  Exit index:    ₹{trade['exit_idx_price']:.2f}")
        if trade["exit_premium"]:
            print(f"  Exit premium:  ₹{trade['exit_premium']:.2f}")
        print()
        pnl = trade["total_pnl"]
        colour = GREEN if pnl >= 0 else RED
        print(f"  Partial P&L:   ₹{trade['partial_pnl']:+.0f}  (50% qty at 1R)")
        print(f"  Remaining P&L: ₹{trade['remaining_pnl']:+.0f}  ({trade['qty_remaining']} qty)")
        print(f"  {BOLD}Total P&L:     {colour}₹{pnl:+.0f}{RESET}  ({trade['pnl_source']})")
        if pnl >= 0:
            print(f"\n  {GREEN}{BOLD}RESULT: WIN ✓{RESET}")
        else:
            print(f"\n  {RED}{BOLD}RESULT: LOSS ✗{RESET}")

    print()
    print(BOLD + _sep("═") + RESET)


# ═════════════════════════════════════════════════════════════════════════════
# Main
# ═════════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(description="Backtest options ORB strategy")
    parser.add_argument("--index",        default="NIFTY",   help="NIFTY or BANKNIFTY")
    parser.add_argument("--date",         required=True,     help="Trade date YYYY-MM-DD")
    parser.add_argument("--strike",       type=int, default=0, help="Option strike (0 = skip premium fetch)")
    parser.add_argument("--expiry",       default=None,      help="Expiry date YYYY-MM-DD (default = trade date)")
    parser.add_argument("--lots",         type=int, default=1)
    parser.add_argument("--capital",      type=float, default=200000)
    parser.add_argument("--api-key",      required=True)
    parser.add_argument("--access-token", required=True)
    args = parser.parse_args()

    index      = args.index.upper()
    trade_date = date.fromisoformat(args.date)
    expiry_date= date.fromisoformat(args.expiry) if args.expiry else trade_date
    strike     = args.strike
    lots       = args.lots
    lot_size   = LOT_SIZES.get(index, 75)

    # Weekend guard
    if trade_date.weekday() >= 5:
        print(f"{RED}Error: {trade_date} is a {'Saturday' if trade_date.weekday()==5 else 'Sunday'}."
              f" Use the nearest weekday.{RESET}")
        prev = trade_date - timedelta(days=trade_date.weekday() - 4)
        next_ = trade_date + timedelta(days=7 - trade_date.weekday())
        print(f"  Nearest Mon–Fri before: {prev}")
        print(f"  Nearest Mon–Fri after:  {next_}")
        sys.exit(1)

    print()
    print(BOLD + f"{'═'*70}" + RESET)
    print(BOLD + f"  Options Backtester — {index} {trade_date}  strike={strike}" + RESET)
    print(BOLD + f"{'═'*70}" + RESET)
    print()

    # ── Auth ──────────────────────────────────────────────────────────────────
    zerodha_service.set_credentials(args.api_key, args.access_token)

    # ── Fetch data ────────────────────────────────────────────────────────────
    print("Fetching data…")
    index_candles = fetch_index_candles(index, trade_date)
    if not index_candles:
        print(f"{RED}No index candles returned. Check date and credentials.{RESET}")
        sys.exit(1)
    print(f"  {GREEN}✓ {len(index_candles)} index candles{RESET}")

    prev_day = fetch_prev_day_ohlc(index, trade_date)
    print(f"  {GREEN}✓ Prev-day H={prev_day['high']:.2f} L={prev_day['low']:.2f}{RESET}")

    # Instruments for futures + option lookup
    opt_candles = []
    fut_volume_ratio_by_step: Dict[int, float] = {}
    try:
        instruments = zerodha_service.kite.instruments("NFO")
        print(f"  {GREEN}✓ {len(instruments)} NFO instruments cached{RESET}")

        # Compute fut volume ratio for each candle step (recomputed at each step)
        # For simplicity: fetch once and compute ratio per step
        futs = [
            i for i in instruments
            if i.get("name") == index
            and i.get("instrument_type") == "FUT"
            and i.get("expiry") and i["expiry"] >= trade_date
        ]
        if futs:
            futs.sort(key=lambda x: x["expiry"])
            token = futs[0]["instrument_token"]
            from_dt = datetime.combine(trade_date, time(9, 15))
            to_dt   = datetime.combine(trade_date, time(15, 30))
            fut_candles_full = _fetch_candles(token, from_dt, to_dt, "5minute")
            print(f"  {GREEN}✓ {len(fut_candles_full)} futures candles{RESET}")
        else:
            fut_candles_full = []

        if strike:
            opt_type_guess = "CE"   # will be updated once signal fires
            opt_candles_ce = fetch_option_candles(
                index, trade_date, expiry_date, strike, "CE", instruments
            )
            opt_candles_pe = fetch_option_candles(
                index, trade_date, expiry_date, strike, "PE", instruments
            )
    except Exception as e:
        print(f"  {YELLOW}NFO instrument fetch failed: {e}{RESET}")
        instruments       = []
        fut_candles_full  = []
        opt_candles_ce    = []
        opt_candles_pe    = []

    # ── Walk-forward simulation ───────────────────────────────────────────────
    print()
    print("Running walk-forward simulation…")
    engine     = BacktestEngine()
    candle_log = []
    signal_fired = False
    final_result = BreakoutResult()
    signal_candle = None
    trade_result  = None

    for step in range(4, len(index_candles)):
        candles_so_far = index_candles[: step + 1]
        current_candle = index_candles[step]
        ts   = current_candle["timestamp"]
        ctime = ts.time() if isinstance(ts, datetime) else time(ts.hour, ts.minute)

        # Compute futures volume ratio at this step
        if fut_candles_full and step < len(fut_candles_full):
            fut_vols = [c["volume"] for c in fut_candles_full[: step + 1]]
            last_vol = fut_vols[-1]
            lookback = fut_vols[max(0, len(fut_vols) - 11): len(fut_vols) - 1]
            avg_vol  = sum(lookback) / len(lookback) if lookback else 0.0
            fut_vol_ratio = round(last_vol / avg_vol, 2) if avg_vol > 0 else 0.0
        else:
            fut_vol_ratio = 0.0

        result = engine.run_at(
            candles       = candles_so_far,
            candle_time   = ctime,
            index         = index,
            expiry_date   = expiry_date,
            trade_date    = trade_date,
            prev_day_high = prev_day["high"],
            prev_day_low  = prev_day["low"],
            fut_volume_ratio = fut_vol_ratio,
        )

        close = current_candle["close"]
        if result.signal != "NO_TRADE":
            entry_tag = f"{GREEN}{BOLD}SIGNAL: {result.signal}{RESET}"
        elif result.failed_filters:
            short = result.failed_filters[-1][:60]
            entry_tag = f"{YELLOW}NO_TRADE: {short}{RESET}"
        else:
            entry_tag = f"{YELLOW}NO_TRADE{RESET}"

        candle_log.append(
            f"  {ts.strftime('%H:%M')}  close={close:.2f}  regime={result.regime.value:<14}  "
            + entry_tag
        )

        if result.signal != "NO_TRADE" and not signal_fired:
            signal_fired  = True
            final_result  = result
            signal_candle = current_candle

            opt_type = "CE" if result.signal == "BUY_CE" else "PE"
            opt_candles = opt_candles_ce if opt_type == "CE" else opt_candles_pe

            # Get entry premium from option candles at signal time
            entry_premium = 0.0
            if opt_candles:
                entry_premium = get_option_premium_at(opt_candles, ts)
            if entry_premium <= 0:
                # Estimate via ATM delta
                risk_pts = abs(result.entry_index_price - result.sl_index_price)
                entry_premium = round(risk_pts * ATM_DELTA * 1.2, 2)  # rough ATM estimate
                print(f"  {YELLOW}No option premium data — estimating ₹{entry_premium:.2f}{RESET}")

            print(f"  {GREEN}SIGNAL at {ts.strftime('%H:%M')} — {result.signal} "
                  f"entry≈₹{entry_premium:.2f} option premium{RESET}")

            # Simulate the trade on remaining candles
            trade_result = simulate_trade(
                signal         = result.signal,
                entry_candle_idx = step,
                index_candles  = index_candles,
                opt_candles    = opt_candles,
                entry_index    = result.entry_index_price,
                sl_index       = result.sl_index_price,
                target_index   = result.target_index_price,
                entry_premium  = entry_premium,
                lots           = lots,
                lot_size       = lot_size,
            )
            break   # one trade per day

    if not signal_fired:
        final_result  = engine.run_at(
            candles       = index_candles,
            candle_time   = index_candles[-1]["timestamp"].time(),
            index         = index,
            expiry_date   = expiry_date,
            trade_date    = trade_date,
            prev_day_high = prev_day["high"],
            prev_day_low  = prev_day["low"],
            fut_volume_ratio = 0.0,
        )

    # ── Print full report ─────────────────────────────────────────────────────
    print_report(
        index        = index,
        trade_date   = trade_date,
        expiry_date  = expiry_date,
        strike       = strike,
        signal_candle= signal_candle,
        result       = final_result,
        trade        = trade_result,
        candle_log   = candle_log,
    )


if __name__ == "__main__":
    main()
