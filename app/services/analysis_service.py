from app.services.data_service import data_service
from app.core.logging import logger
from typing import List, Dict, Optional
import pandas as pd
from datetime import datetime


class AnalysisService:
    """
    Service for market analysis and stock screening.

    New pipeline:
      1. screen_and_enrich() — calls data_service.screen_top_movers() then
         fetches 60-day candles and calculates full technical indicators
      2. calculate_technical_indicators() — ATR, RSI, SMA, MACD, volume metrics
    """

    def __init__(self):
        self.ds = data_service

    async def screen_and_enrich(
        self,
        limit: int,
        analysis_date: datetime,
        sectors: Optional[List[str]] = None,
        hold_duration_days: int = 0,
    ) -> List[Dict]:
        """
        Full pipeline:
          1. Screen entire NSE universe for top movers (by volume × momentum)
          2. Fetch 60-day candle history for each candidate
          3. Calculate technical indicators
          4. Re-rank by composite score that factors in hold_duration_days
          5. Return top `limit` stocks enriched with all data for LLM

        The hold_duration_days hint adjusts scoring:
          - Intraday (0): prefer high intraday volatility + volume
          - Short (1–7d): prefer strong momentum + volume surge
          - Medium (7–30d): prefer trend strength + RSI positioning
        """
        try:
            # Stage 1: Screen — fetch 3× limit candidates so we have room to drop bad data
            screen_limit = min(limit * 3, 150)
            candidates = await self.ds.screen_top_movers(
                limit=screen_limit,
                sectors=sectors,
            )

            if not candidates:
                logger.warning("Screener returned no candidates, falling back to NIFTY 50")
                candidates = await self.ds.screen_top_movers(limit=screen_limit, sectors=["NIFTY 50"])

            # Stage 2: Enrich with 60-day candle data + indicators
            enriched = []
            for c in candidates:
                symbol = c["symbol"]
                df = await self.ds.get_candle_data(symbol, "day", period="60d")

                if df.empty or len(df) < 10:
                    logger.debug(f"Skipping {symbol}: insufficient candle data")
                    continue

                indicators = await self.calculate_technical_indicators(df)
                if not indicators:
                    continue

                # Merge screener data + indicators
                enriched.append({
                    **c,
                    "historical_data": df,
                    "indicators": indicators,
                    # Override last_price with most recent close from candles
                    "last_price": indicators.get("last_close", c["last_price"]),
                    "high": float(df["high"].iloc[-1]) if "high" in df.columns else c["high"],
                    "low": float(df["low"].iloc[-1]) if "low" in df.columns else c["low"],
                })

            logger.info(f"Enriched {len(enriched)} stocks with 60-day candle data")

            # Stage 3: Re-rank using hold-duration-aware scoring
            enriched = self._rank_by_hold_duration(enriched, hold_duration_days)

            # Return top `limit`
            return enriched[:limit]

        except Exception as e:
            logger.error(f"screen_and_enrich failed: {e}")
            return []

    def _rank_by_hold_duration(
        self, stocks: List[Dict], hold_duration_days: int
    ) -> List[Dict]:
        """
        Re-score stocks based on how well their indicators suit the hold duration.

        Intraday (0):   weight volume_ratio × volatility (want big moves today)
        Short (1–7):    weight volume_ratio × momentum_5d × RSI_fitness
        Medium (8–30):  weight trend_strength × RSI_fitness × volume_ratio
        """
        for s in stocks:
            ind = s.get("indicators", {})
            vr = s.get("volume_ratio", 1.0)
            mom = max(s.get("momentum_5d_pct", 0), 0)
            vol = max(s.get("volatility_5d", 1.0), 0.1)
            rsi = ind.get("rsi", 50)
            trend = 1.0 if ind.get("trend") == "BULLISH" else 0.3

            # RSI fitness: best between 55–72 (momentum zone, not overbought)
            rsi_fitness = 1.0 - abs(rsi - 63) / 37 if rsi else 0.5
            rsi_fitness = max(rsi_fitness, 0)

            if hold_duration_days == 0:
                # Intraday: want high volume + high intraday volatility
                score = vr * 0.6 + vol * 0.4
            elif hold_duration_days <= 7:
                # Short-term: volume surge + momentum + RSI fitness
                score = vr * 0.4 + mom * 0.35 + rsi_fitness * 0.25
            else:
                # Medium-term: trend + RSI fitness + volume
                score = trend * 0.4 + rsi_fitness * 0.35 + vr * 0.25

            s["hold_adjusted_score"] = round(score, 4)

        stocks.sort(key=lambda x: x.get("hold_adjusted_score", 0), reverse=True)
        return stocks

    async def calculate_technical_indicators(self, df: pd.DataFrame) -> Dict:
        """
        Calculate comprehensive technical indicators for a stock.
        Returns empty dict if data is insufficient.
        """
        if df.empty or len(df) < 10:
            return {}

        try:
            df = df.copy()
            for col in ["close", "high", "low", "open", "volume"]:
                if col in df.columns:
                    df[col] = df[col].astype(float)

            close = df["close"]
            high = df["high"]
            low = df["low"]
            volume = df["volume"]
            last_close = float(close.iloc[-1])

            # ── ATR (14-period) ───────────────────────────────────────────
            hl = high - low
            hc = (high - close.shift()).abs()
            lc = (low - close.shift()).abs()
            tr = pd.concat([hl, hc, lc], axis=1).max(axis=1)
            atr = float(tr.rolling(14).mean().iloc[-1])

            # ── Moving Averages ───────────────────────────────────────────
            sma_20 = float(close.rolling(20).mean().iloc[-1])
            sma_50 = float(close.rolling(50).mean().iloc[-1]) if len(df) >= 50 else None
            ema_9  = float(close.ewm(span=9, adjust=False).mean().iloc[-1])
            ema_21 = float(close.ewm(span=21, adjust=False).mean().iloc[-1])

            # ── RSI (14-period) ───────────────────────────────────────────
            delta = close.diff()
            gain = delta.where(delta > 0, 0).rolling(14).mean()
            loss = (-delta.where(delta < 0, 0)).rolling(14).mean()
            rs = gain / loss.replace(0, float("nan"))
            rsi = float((100 - 100 / (1 + rs)).iloc[-1])

            # ── MACD ──────────────────────────────────────────────────────
            ema_12 = close.ewm(span=12, adjust=False).mean()
            ema_26 = close.ewm(span=26, adjust=False).mean()
            macd_line = ema_12 - ema_26
            signal_line = macd_line.ewm(span=9, adjust=False).mean()
            macd_hist = float((macd_line - signal_line).iloc[-1])
            macd_val = float(macd_line.iloc[-1])

            # ── Volume metrics ────────────────────────────────────────────
            avg_vol_20 = float(volume.rolling(20).mean().iloc[-1])
            latest_vol = float(volume.iloc[-1])
            volume_ratio = latest_vol / avg_vol_20 if avg_vol_20 > 0 else 1.0

            # ── Trend ─────────────────────────────────────────────────────
            trend = "BULLISH" if last_close > sma_20 else "BEARISH"
            if sma_50 and last_close > sma_50 and last_close > sma_20:
                trend = "STRONG_BULLISH"

            # ── Support / Resistance (simple 20-day) ─────────────────────
            support_20d = float(low.rolling(20).min().iloc[-1])
            resistance_20d = float(high.rolling(20).max().iloc[-1])

            # ── 52-week high proximity ────────────────────────────────────
            high_52w = float(high.max()) if len(df) >= 52 else float(high.max())
            pct_from_52w_high = round((last_close - high_52w) / high_52w * 100, 2)

            return {
                "atr": round(atr, 2),
                "last_close": round(last_close, 2),
                "sma_20": round(sma_20, 2),
                "sma_50": round(sma_50, 2) if sma_50 else None,
                "ema_9": round(ema_9, 2),
                "ema_21": round(ema_21, 2),
                "rsi": round(rsi, 2),
                "macd": round(macd_val, 4),
                "macd_histogram": round(macd_hist, 4),
                "avg_volume_20d": round(avg_vol_20, 0),
                "volume_ratio": round(volume_ratio, 2),
                "trend": trend,
                "support_20d": round(support_20d, 2),
                "resistance_20d": round(resistance_20d, 2),
                "pct_from_52w_high": pct_from_52w_high,
            }

        except Exception as e:
            logger.error(f"Indicator calculation failed: {e}")
            return {}

    # ── Legacy compatibility ──────────────────────────────────────────────────

    async def get_top_volume_stocks_with_data(
        self, limit: int, analysis_date: datetime
    ) -> List[Dict]:
        """Legacy method — delegates to screen_and_enrich."""
        return await self.screen_and_enrich(limit=limit, analysis_date=analysis_date)


analysis_service = AnalysisService()
