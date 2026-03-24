"""
Backtesting engine for the intraday strategy.

Uses yfinance daily OHLCV data and applies the same indicator logic as the live
strategy (VWAP-proxy, RSI, MACD, BB, Stochastic, EMA). Signals are generated
bar-by-bar without lookahead. Trades are entered at the next bar's open and
exited when SL or target is hit or after max_hold_bars.
"""

from __future__ import annotations

import asyncio
import math
from dataclasses import dataclass, field, asdict
from datetime import date, datetime, timedelta
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd
import yfinance as yf

from app.core.logging import logger
from app.engines.strategy_engine import strategy_engine


# ── Default universe (Nifty 50 + a few Nifty Next 50 liquid stocks) ──────────
NIFTY_UNIVERSE = [
    "RELIANCE", "TCS", "HDFCBANK", "INFY", "ICICIBANK",
    "SBIN", "BHARTIARTL", "KOTAKBANK", "LT", "AXISBANK",
    "WIPRO", "HCLTECH", "TECHM", "POWERGRID", "NTPC",
    "JSWSTEEL", "HINDALCO", "COALINDIA", "GAIL", "RECLTD",
    "ZOMATO", "TRENT", "DIXON", "IRCTC", "DLF",
    "LTIM", "MPHASIS", "COFORGE", "PFC", "VEDL",
    "BAJFINANCE", "BAJAJFINSV", "MARUTI", "SUNPHARMA", "NESTLEIND",
    "HINDUNILVR", "ASIANPAINT", "ULTRACEMCO", "TITAN", "BPCL",
    "ONGC", "IOC", "TATASTEEL", "M&M", "TATAMOTORS",
    "ITC", "BRITANNIA", "DRREDDY", "CIPLA", "EICHERMOT",
]


# ── Data classes ──────────────────────────────────────────────────────────────

@dataclass
class BacktestRequest:
    symbols: List[str] = field(default_factory=list)        # empty → NIFTY_UNIVERSE
    start_date: str = "2024-01-01"                           # YYYY-MM-DD
    end_date: str = ""                                       # empty → yesterday
    sl_atr_multiplier: float = 2.0                          # SL = entry ± ATR * multiplier (wider SL gives trades room)
    target_rr: float = 1.5                                  # target = SL_distance * rr (easier to hit → better win rate)
    min_signal_strength: int = 3                            # min combos agreeing (3+ filters out most noise)
    max_hold_bars: int = 10                                 # exit at close after N days (10 days for daily candles)
    include_short: bool = True                              # backtest SELL signals too
    include_trades_detail: bool = True                      # include per-trade rows in report


@dataclass
class TradeResult:
    symbol: str
    entry_date: str
    exit_date: str
    action: str           # BUY | SELL
    signal_strength: int
    signal_reasons: List[str]
    entry_price: float
    stop_loss: float
    target: float
    exit_price: float
    outcome: str          # WIN | LOSS | TIMEOUT
    pnl_pct: float        # % gain/loss on entry price
    hold_bars: int


# ── Engine ────────────────────────────────────────────────────────────────────

class BacktestEngine:

    # Warmup: need at least 26 bars for MACD before indicators are stable
    _WARMUP_BARS = 40

    # ── Public entry point ────────────────────────────────────────────────────

    async def run_backtest(self, req: BacktestRequest) -> Dict:
        symbols = req.symbols if req.symbols else NIFTY_UNIVERSE
        end_date = req.end_date or (date.today() - timedelta(days=1)).strftime("%Y-%m-%d")
        start_date = req.start_date

        # Compute data fetch start = start_date - warmup buffer
        fetch_start = (
            datetime.strptime(start_date, "%Y-%m-%d") - timedelta(days=self._WARMUP_BARS * 2)
        ).strftime("%Y-%m-%d")

        logger.info(
            f"[Backtest] Starting: {len(symbols)} symbols | "
            f"{start_date} → {end_date} | "
            f"SL×{req.sl_atr_multiplier} | RR {req.target_rr} | "
            f"min_strength={req.min_signal_strength}"
        )

        # Download all symbols in parallel
        loop = asyncio.get_event_loop()
        tasks = [
            loop.run_in_executor(
                None,
                self._fetch_symbol_data,
                sym,
                fetch_start,
                end_date,
            )
            for sym in symbols
        ]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        all_trades: List[TradeResult] = []
        failed_symbols: List[str] = []

        for sym, result in zip(symbols, results):
            if isinstance(result, Exception):
                logger.warning(f"[Backtest] {sym}: data fetch failed — {result}")
                failed_symbols.append(sym)
                continue
            if result is None or result.empty:
                failed_symbols.append(sym)
                continue

            trades = self._simulate_symbol(
                symbol=sym,
                df=result,
                backtest_start=start_date,
                req=req,
            )
            all_trades.extend(trades)

        logger.info(
            f"[Backtest] Simulation done: {len(all_trades)} trades from "
            f"{len(symbols) - len(failed_symbols)} symbols. "
            f"Failed: {failed_symbols}"
        )

        report = self._build_report(all_trades, req, symbols, end_date, failed_symbols)
        return report

    # ── Data fetch ────────────────────────────────────────────────────────────

    def _fetch_symbol_data(self, symbol: str, start: str, end: str) -> Optional[pd.DataFrame]:
        try:
            ticker = yf.Ticker(f"{symbol}.NS")
            df = ticker.history(start=start, end=end, interval="1d", auto_adjust=True)
            if df.empty or len(df) < self._WARMUP_BARS:
                logger.debug(f"[Backtest] {symbol}: insufficient rows ({len(df)})")
                return None
            df = df[["Open", "High", "Low", "Close", "Volume"]].copy()
            df.index = pd.to_datetime(df.index).tz_localize(None)
            return df
        except Exception as e:
            logger.warning(f"[Backtest] {symbol} fetch error: {e}")
            return None

    # ── Indicator computation (vectorized on full series) ─────────────────────

    def _compute_indicators(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Returns a DataFrame aligned to df with all indicator columns.
        First _WARMUP_BARS rows will have NaNs — they are excluded during simulation.
        """
        close = df["Close"]
        high = df["High"]
        low = df["Low"]
        volume = df["Volume"]

        # VWAP proxy: 5-day rolling volume-weighted typical price.
        # A shorter window better approximates intraday VWAP direction vs
        # a 20-day rolling window which is essentially a trend indicator.
        typical = (high + low + close) / 3
        vol_safe = volume.replace(0, float("nan"))
        vwap_5 = (typical * vol_safe).rolling(5).sum() / vol_safe.rolling(5).sum()

        # EMA 50: trend filter — BUY only above EMA50, SELL only below EMA50
        ema50 = close.ewm(span=50, adjust=False).mean()

        # ATR 14
        hl = high - low
        hc = (high - close.shift(1)).abs()
        lc = (low - close.shift(1)).abs()
        tr = pd.concat([hl, hc, lc], axis=1).max(axis=1)
        atr_14 = tr.rolling(14).mean()

        # RSI 14
        delta = close.diff()
        gain = delta.clip(lower=0).rolling(14).mean()
        loss = (-delta.clip(upper=0)).rolling(14).mean()
        rs = gain / loss.replace(0, float("nan"))
        rsi_14 = 100 - (100 / (1 + rs))

        # MACD 12/26/9
        ema12 = close.ewm(span=12, adjust=False).mean()
        ema26 = close.ewm(span=26, adjust=False).mean()
        macd_line = ema12 - ema26
        macd_sig = macd_line.ewm(span=9, adjust=False).mean()
        macd_hist = macd_line - macd_sig
        macd_hist_prev = macd_hist.shift(1)
        macd_bullish_xover = (macd_hist_prev < 0) & (macd_hist > 0)
        macd_bearish_xover = (macd_hist_prev > 0) & (macd_hist < 0)

        # Bollinger Bands 20
        bb_mid = close.rolling(20).mean()
        bb_std = close.rolling(20).std()
        bb_upper = bb_mid + 2 * bb_std
        bb_lower = bb_mid - 2 * bb_std

        # Stochastic 14/3
        low14 = low.rolling(14).min()
        high14 = high.rolling(14).max()
        hl_range = (high14 - low14).replace(0, float("nan"))
        stoch_k = 100 * (close - low14) / hl_range
        stoch_d = stoch_k.rolling(3).mean()

        # EMA 9/21
        ema9 = close.ewm(span=9, adjust=False).mean()
        ema21 = close.ewm(span=21, adjust=False).mean()

        return pd.DataFrame({
            "open":          df["Open"],
            "high":          high,
            "low":           low,
            "close":         close,
            "volume":        volume,
            "vwap_5":        vwap_5,
            "ema50":         ema50,
            "atr_14":        atr_14,
            "rsi_14":        rsi_14,
            "macd_hist":     macd_hist,
            "macd_bx":       macd_bullish_xover,
            "macd_brx":      macd_bearish_xover,
            "bb_upper":      bb_upper,
            "bb_middle":     bb_mid,
            "bb_lower":      bb_lower,
            "stoch_k":       stoch_k,
            "stoch_d":       stoch_d,
            "ema9":          ema9,
            "ema21":         ema21,
        }, index=df.index)

    # ── Indicator dict builder ────────────────────────────────────────────────

    def _row_to_indicator_dict(self, row: pd.Series) -> Optional[Dict]:
        """Convert a computed indicator row to the dict format strategy_engine expects."""
        if row.isna().any():
            return None

        close = float(row["close"])
        vwap = float(row["vwap_5"])
        bb_upper = float(row["bb_upper"])
        bb_lower = float(row["bb_lower"])
        bb_mid = float(row["bb_middle"])
        stoch_k = float(row["stoch_k"])
        stoch_d = float(row["stoch_d"])
        ema9 = float(row["ema9"])
        ema21 = float(row["ema21"])
        macd_hist = float(row["macd_hist"])

        # BB position
        if close >= bb_upper * 0.985:
            bb_position = "NEAR_UPPER"
        elif close <= bb_lower * 1.015:
            bb_position = "NEAR_LOWER"
        else:
            bb_position = "MIDDLE"

        # Stochastic signal
        if stoch_k > 80 and stoch_d > 80:
            stoch_signal = "OVERBOUGHT"
        elif stoch_k < 20 and stoch_d < 20:
            stoch_signal = "OVERSOLD"
        elif stoch_k > stoch_d:
            stoch_signal = "BULLISH"
        else:
            stoch_signal = "BEARISH"

        return {
            "last_close": close,
            "price_vs_vwap": "ABOVE" if close > vwap else "BELOW",
            "rsi": float(row["rsi_14"]),
            "macd_histogram": macd_hist,
            "macd_bullish_crossover": bool(row["macd_bx"]),
            "macd_bearish_crossover": bool(row["macd_brx"]),
            "bb_position": bb_position,
            "bb_middle": bb_mid,
            "stoch_k": stoch_k,
            "stoch_d": stoch_d,
            "stoch_signal": stoch_signal,
            "ema_9": ema9,
            "ema_21": ema21,
        }

    # ── Per-symbol simulation ─────────────────────────────────────────────────

    def _simulate_symbol(
        self,
        symbol: str,
        df: pd.DataFrame,
        backtest_start: str,
        req: BacktestRequest,
    ) -> List[TradeResult]:
        ind = self._compute_indicators(df)
        trades: List[TradeResult] = []
        n = len(ind)
        last_trade_bar = -999  # cooldown: no new trade within 3 bars of last trade

        for i in range(self._WARMUP_BARS, n - 1):
            # Only process bars within the requested backtest window
            bar_date = ind.index[i]
            if str(bar_date.date()) < backtest_start:
                continue

            # 3-bar cooldown after last trade exit
            if i - last_trade_bar < 3:
                continue

            row = ind.iloc[i]
            ind_dict = self._row_to_indicator_dict(row)
            if ind_dict is None:
                continue

            sig = strategy_engine.generate_intraday_signal(ind_dict)
            signal = sig["signal"]
            strength = sig["strength"]
            reasons = sig["reasons"]

            if signal == "NEUTRAL":
                continue
            if strength < req.min_signal_strength:
                continue
            if signal == "SELL" and not req.include_short:
                continue

            # ── Trend filter: skip counter-trend signals ─────────────────
            # Only BUY when price is above 50-day EMA (uptrend confirmed).
            # Only SELL when price is below 50-day EMA (downtrend confirmed).
            ema50 = float(row["ema50"]) if not pd.isna(row["ema50"]) else 0.0
            close_price = float(row["close"])
            if ema50 > 0:
                if signal == "BUY" and close_price < ema50:
                    continue   # skip BUY in downtrend
                if signal == "SELL" and close_price > ema50:
                    continue   # skip SELL in uptrend

            # ── Suppress MACD-only (strength-1) signals ───────────────────
            # strategy_engine fires strength-1 signals from MACD alone when
            # zero indicator combos agree. These are too weak for daily bars.
            if strength == 1 and len(reasons) == 1 and "MACD" in reasons[0] and "weak" in reasons[0]:
                continue

            # Entry: next bar's open
            entry_idx = i + 1
            if entry_idx >= n:
                break

            entry_bar = ind.iloc[entry_idx]
            entry_price = float(entry_bar["open"])
            if entry_price <= 0:
                continue

            atr = float(row["atr_14"])
            if atr <= 0 or math.isnan(atr):
                continue

            sl_distance = atr * req.sl_atr_multiplier
            target_distance = sl_distance * req.target_rr

            is_short = signal == "SELL"
            if is_short:
                stop_loss = round(entry_price + sl_distance, 2)
                target = round(entry_price - target_distance, 2)
                if target <= 0:
                    continue
            else:
                stop_loss = round(entry_price - sl_distance, 2)
                target = round(entry_price + target_distance, 2)
                if stop_loss <= 0:
                    continue

            # Simulate exit from entry bar onwards
            outcome, exit_price, exit_bar_idx = self._simulate_exit(
                ind=ind,
                entry_idx=entry_idx,
                entry_price=entry_price,
                stop_loss=stop_loss,
                target=target,
                is_short=is_short,
                max_hold=req.max_hold_bars,
            )

            hold_bars = exit_bar_idx - entry_idx

            if is_short:
                pnl_pct = round((entry_price - exit_price) / entry_price * 100, 3)
            else:
                pnl_pct = round((exit_price - entry_price) / entry_price * 100, 3)

            trades.append(TradeResult(
                symbol=symbol,
                entry_date=str(ind.index[entry_idx].date()),
                exit_date=str(ind.index[exit_bar_idx].date()),
                action="SELL" if is_short else "BUY",
                signal_strength=strength,
                signal_reasons=reasons,
                entry_price=round(entry_price, 2),
                stop_loss=stop_loss,
                target=target,
                exit_price=round(exit_price, 2),
                outcome=outcome,
                pnl_pct=pnl_pct,
                hold_bars=hold_bars,
            ))

            last_trade_bar = exit_bar_idx  # enforce 3-bar cooldown after exit

        return trades

    # ── Exit simulator ────────────────────────────────────────────────────────

    def _simulate_exit(
        self,
        ind: pd.DataFrame,
        entry_idx: int,
        entry_price: float,
        stop_loss: float,
        target: float,
        is_short: bool,
        max_hold: int,
    ) -> Tuple[str, float, int]:
        """
        Scan bars from entry_idx onward (including entry bar).
        Returns (outcome, exit_price, bar_index_of_exit).
        """
        n = len(ind)
        last_possible = min(entry_idx + max_hold, n - 1)

        for j in range(entry_idx, last_possible + 1):
            bar = ind.iloc[j]
            bar_high = float(bar["high"])
            bar_low = float(bar["low"])
            bar_close = float(bar["close"])

            if is_short:
                sl_hit = bar_high >= stop_loss
                tgt_hit = bar_low <= target
            else:
                sl_hit = bar_low <= stop_loss
                tgt_hit = bar_high >= target

            if sl_hit and tgt_hit:
                # Both hit on same bar — conservative: assume SL first
                return "LOSS", stop_loss, j

            if sl_hit:
                return "LOSS", stop_loss, j

            if tgt_hit:
                return "WIN", target, j

        # Max hold reached — exit at last bar's close
        exit_bar = last_possible
        exit_price = float(ind.iloc[exit_bar]["close"])
        return "TIMEOUT", exit_price, exit_bar

    # ── Report builder ────────────────────────────────────────────────────────

    def _build_report(
        self,
        trades: List[TradeResult],
        req: BacktestRequest,
        symbols: List[str],
        end_date: str,
        failed_symbols: List[str],
    ) -> Dict:
        if not trades:
            return {
                "summary": {"total_trades": 0, "message": "No trades generated."},
                "parameters": self._params_dict(req, symbols, end_date),
                "generated_at": datetime.utcnow().isoformat(),
            }

        total = len(trades)
        wins = [t for t in trades if t.outcome == "WIN"]
        losses = [t for t in trades if t.outcome == "LOSS"]
        timeouts = [t for t in trades if t.outcome == "TIMEOUT"]

        win_rate = round(len(wins) / total * 100, 2)
        loss_rate = round(len(losses) / total * 100, 2)
        timeout_rate = round(len(timeouts) / total * 100, 2)

        avg_win = round(float(np.mean([t.pnl_pct for t in wins])), 3) if wins else 0.0
        avg_loss = round(float(np.mean([t.pnl_pct for t in losses])), 3) if losses else 0.0
        avg_timeout = round(float(np.mean([t.pnl_pct for t in timeouts])), 3) if timeouts else 0.0

        gross_profit = sum(t.pnl_pct for t in wins)
        gross_loss = abs(sum(t.pnl_pct for t in losses))
        profit_factor = round(gross_profit / gross_loss, 3) if gross_loss > 0 else float("inf")

        total_pnl = round(sum(t.pnl_pct for t in trades), 3)
        avg_pnl = round(total_pnl / total, 3)

        # Expected value per trade
        ev = round(
            (win_rate / 100) * avg_win + (loss_rate / 100) * avg_loss + (timeout_rate / 100) * avg_timeout,
            3,
        )

        # Max drawdown (equity curve)
        pnls = [t.pnl_pct for t in trades]
        cum = np.cumsum(pnls)
        running_max = np.maximum.accumulate(cum)
        drawdowns = running_max - cum
        max_dd = round(float(drawdowns.max()), 3) if len(drawdowns) > 0 else 0.0

        # Sharpe-like: mean / std of trade P&Ls
        pnl_arr = np.array(pnls)
        sharpe = round(float(pnl_arr.mean() / pnl_arr.std()), 3) if pnl_arr.std() > 0 else 0.0

        # By signal type
        by_signal = {}
        for action in ("BUY", "SELL"):
            group = [t for t in trades if t.action == action]
            if group:
                g_wins = [t for t in group if t.outcome == "WIN"]
                by_signal[action] = {
                    "trades": len(group),
                    "wins": len(g_wins),
                    "win_rate_pct": round(len(g_wins) / len(group) * 100, 2),
                    "avg_pnl_pct": round(float(np.mean([t.pnl_pct for t in group])), 3),
                }

        # By signal strength
        by_strength = {}
        for s in range(1, 6):
            group = [t for t in trades if t.signal_strength == s]
            if group:
                g_wins = [t for t in group if t.outcome == "WIN"]
                by_strength[str(s)] = {
                    "trades": len(group),
                    "wins": len(g_wins),
                    "win_rate_pct": round(len(g_wins) / len(group) * 100, 2),
                    "avg_pnl_pct": round(float(np.mean([t.pnl_pct for t in group])), 3),
                }

        # By symbol
        sym_map: Dict[str, List[TradeResult]] = {}
        for t in trades:
            sym_map.setdefault(t.symbol, []).append(t)
        by_symbol = []
        for sym, sym_trades in sorted(sym_map.items()):
            sw = [t for t in sym_trades if t.outcome == "WIN"]
            by_symbol.append({
                "symbol": sym,
                "trades": len(sym_trades),
                "wins": len(sw),
                "losses": len([t for t in sym_trades if t.outcome == "LOSS"]),
                "timeouts": len([t for t in sym_trades if t.outcome == "TIMEOUT"]),
                "win_rate_pct": round(len(sw) / len(sym_trades) * 100, 2),
                "total_pnl_pct": round(sum(t.pnl_pct for t in sym_trades), 3),
                "avg_pnl_pct": round(float(np.mean([t.pnl_pct for t in sym_trades])), 3),
            })
        by_symbol.sort(key=lambda x: x["total_pnl_pct"], reverse=True)

        report = {
            "summary": {
                "total_trades": total,
                "win_trades": len(wins),
                "loss_trades": len(losses),
                "timeout_trades": len(timeouts),
                "win_rate_pct": win_rate,
                "loss_rate_pct": loss_rate,
                "timeout_rate_pct": timeout_rate,
                "avg_win_pct": avg_win,
                "avg_loss_pct": avg_loss,
                "avg_timeout_pct": avg_timeout,
                "profit_factor": profit_factor,
                "expected_value_pct": ev,
                "total_pnl_pct": total_pnl,
                "avg_pnl_per_trade_pct": avg_pnl,
                "max_drawdown_pct": max_dd,
                "sharpe_ratio": sharpe,
                "best_trade_pct": round(max(pnls), 3),
                "worst_trade_pct": round(min(pnls), 3),
                "symbols_tested": len(symbols) - len(failed_symbols),
                "symbols_failed": len(failed_symbols),
                "failed_symbols": failed_symbols,
            },
            "by_signal": by_signal,
            "by_strength": by_strength,
            "by_symbol": by_symbol,
            "parameters": self._params_dict(req, symbols, end_date),
            "generated_at": datetime.utcnow().isoformat(),
        }

        if req.include_trades_detail:
            report["trades"] = [asdict(t) for t in trades]

        return report

    def _params_dict(self, req: BacktestRequest, symbols: List[str], end_date: str) -> Dict:
        return {
            "symbols": symbols,
            "start_date": req.start_date,
            "end_date": end_date,
            "sl_atr_multiplier": req.sl_atr_multiplier,
            "target_rr": req.target_rr,
            "min_signal_strength": req.min_signal_strength,
            "max_hold_bars": req.max_hold_bars,
            "include_short": req.include_short,
        }


backtest_engine = BacktestEngine()
