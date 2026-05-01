import asyncio
import yfinance as yf
from app.services.data_service import data_service
from app.core.logging import logger
from typing import List, Dict, Optional
import pandas as pd
import pytz
from datetime import datetime, timedelta, time


# ── Last-resort fallback universe (only used if NSE CSV download and dynamic
#    screening both fail completely) ──────────────────────────────────────────
_INTRADAY_LAST_RESORT = [
    "RELIANCE", "TCS", "HDFCBANK", "INFY", "ICICIBANK",
    "SBIN", "BHARTIARTL", "KOTAKBANK", "LT", "AXISBANK",
    "WIPRO", "HCLTECH", "TECHM", "POWERGRID", "NTPC",
    "JSWSTEEL", "HINDALCO", "COALINDIA", "GAIL", "RECLTD",
    "ZOMATO", "TRENT", "DIXON", "IRCTC", "DLF",
    "LTIM", "MPHASIS", "COFORGE", "PFC", "VEDL",
]


class AnalysisService:
    """
    Service for market analysis and stock screening.

    Two pipelines:
      Intraday (hold_duration_days=0):
        screen_and_enrich_intraday() → Zerodha live quotes + 5min candles
        → VWAP, BB, RSI, MACD, Stochastic, Pivot Points
      Swing/Delivery (hold_duration_days > 0):
        screen_and_enrich() → yfinance daily candles → standard indicators
    """

    IST = pytz.timezone("Asia/Kolkata")

    def __init__(self):
        self.ds = data_service

    # ── Public API ────────────────────────────────────────────────────────────

    async def screen_and_enrich(
        self,
        limit: int,
        analysis_date: datetime,
        sectors: Optional[List[str]] = None,
        hold_duration_days: int = 0,
        user_api_key: Optional[str] = None,
        user_access_token: Optional[str] = None,
        symbols: Optional[List[str]] = None,
    ) -> List[Dict]:
        """
        Full pipeline — branches on hold_duration_days:
          0  → intraday Zerodha pipeline (live prices + 5min candles)
          >0 → swing yfinance pipeline  (60-day daily candles)
        When `symbols` is provided the sector-screening step is skipped and
        those specific symbols are enriched directly.
        """
        if hold_duration_days == 0:
            return await self.screen_and_enrich_intraday(
                limit=limit,
                user_api_key=user_api_key,
                user_access_token=user_access_token,
                symbols=symbols,
            )

        # ── Swing / Delivery pipeline ──────────────────────────────────────
        try:
            screen_limit = min(limit * 3, 150)

            # When the caller passes specific symbols, bypass the screener
            # and build the candidate list directly from those symbols.
            if symbols:
                logger.info(f"[Swing-MANUAL] Using {len(symbols)} user-specified symbols: {symbols}")
                candidates = [
                    {"symbol": s.upper(), "company_name": s.upper(), "last_price": 0,
                     "volume": 0, "volume_ratio": 1.0, "day_change_pct": 0.0,
                     "momentum_5d_pct": 0.0, "volatility_5d": 0.0}
                    for s in symbols
                ]
            else:
                # For swing, we do NOT use the Zerodha live-quote screener.
                # Zerodha historical_data is rate-limited to 3 req/sec during market
                # hours; sequential calls for 60+ stocks cause throttling errors.
                # yfinance daily data is sufficient for multi-day swing analysis
                # and handles concurrent calls without rate issues.
                candidates = await self.ds.screen_top_movers(
                    limit=screen_limit,
                    sectors=sectors,
                    hold_duration_days=hold_duration_days,
                    kite_instance=None,   # yfinance screener — no rate limits
                )

            if not candidates:
                logger.warning("Screener returned no candidates, falling back to NIFTY 50")
                candidates = await self.ds.screen_top_movers(
                    limit=screen_limit, sectors=["NIFTY 50"],
                )

            # For swing, always use yfinance for 60-day daily candles.
            # Zerodha's historical_data API is rate-limited to 3 req/sec during
            # market hours — fetching 60+ stocks sequentially triggers throttling
            # and causes analysis failures. yfinance daily data is adequate for
            # swing analysis and has no such rate limits.
            now_ist = datetime.now(self.IST)
            is_market_open = (
                now_ist.weekday() < 5
                and datetime.strptime("09:15", "%H:%M").time()
                <= now_ist.time()
                <= datetime.strptime("15:30", "%H:%M").time()
            )

            enriched = []
            for c in candidates:
                symbol = c["symbol"]
                df = await self.ds.get_candle_data(symbol, "day", period="60d")

                # During market hours, the last candle is the incomplete current
                # session (partial volume, midday price). Drop it so indicators
                # are calculated on fully closed candles only.
                if is_market_open and not df.empty and len(df) > 10:
                    df = df.iloc[:-1]

                if df.empty or len(df) < 10:
                    logger.debug(f"Skipping {symbol}: insufficient candle data")
                    continue

                indicators = await self.calculate_technical_indicators(df)
                if not indicators:
                    continue

                enriched.append({
                    **c,
                    "historical_data": df,
                    "indicators": indicators,
                    "last_price": indicators.get("last_close", c["last_price"]),
                    "high": float(df["high"].iloc[-1]) if "high" in df.columns else c["high"],
                    "low": float(df["low"].iloc[-1]) if "low" in df.columns else c["low"],
                })

            logger.info(f"Enriched {len(enriched)} stocks with 60-day candle data")
            enriched = self._rank_by_hold_duration(enriched, hold_duration_days)
            return enriched[:limit]

        except Exception as e:
            logger.error(f"screen_and_enrich failed: {e}")
            return []

    # ── Intraday pipeline ─────────────────────────────────────────────────────

    async def screen_and_enrich_intraday(
        self,
        limit: int,
        user_api_key: Optional[str] = None,
        user_access_token: Optional[str] = None,
        symbols: Optional[List[str]] = None,
    ) -> List[Dict]:
        """
        Intraday pipeline:
          1. Dynamically screen top movers from full NSE universe (yfinance 5d)
          2. Live quotes for screened candidates via Zerodha quote API (using user credentials)
          3. Filter by volume (>200K today), price range
          4. Fetch today's 5-minute candles for top candidates via Zerodha historical
          5. Calculate VWAP, BB, RSI, MACD, Stochastic, Pivot Points
          6. Generate preliminary BUY/SELL signal per stock
          7. Return top `limit` stocks sorted by signal strength + volume
        """
        from app.services.zerodha_service import ZerodhaService
        from app.engines.strategy_engine import strategy_engine

        # Early exit when NSE is closed — avoids running the full pipeline only to return []
        now_ist = datetime.now(self.IST)
        market_open = (
            now_ist.weekday() < 5
            and time(9, 15) <= now_ist.time() <= time(15, 30)
        )
        if not market_open:
            logger.warning(
                f"[Intraday-MARKET-CLOSED] NSE is closed at "
                f"{now_ist.strftime('%H:%M IST, %A')}. Intraday pipeline skipped."
            )
            return []

        # Create user-specific Zerodha service with their credentials
        kite_instance = None
        if user_api_key and user_access_token:
            user_zerodha = ZerodhaService()
            user_zerodha.set_credentials(user_api_key, user_access_token)
            logger.info(f"[Intraday-CREDS] Using USER-SPECIFIC zerodha instance with api_key={user_api_key[:6]}... token={user_access_token[:10]}...{user_access_token[-10:]}")
            # Also create a raw KiteConnect instance for Zerodha-native data methods
            from kiteconnect import KiteConnect
            kite_instance = KiteConnect(api_key=user_api_key)
            kite_instance.set_access_token(user_access_token)
        else:
            from app.services.zerodha_service import zerodha_service
            user_zerodha = zerodha_service
            logger.warning("[Intraday-CREDS] No user credentials provided, using global zerodha_service (may fail!)")

        # ── Step 1: Build candidate universe ──────────────────────────────
        if symbols:
            logger.info(f"[Intraday-MANUAL] Using {len(symbols)} user-specified symbols: {symbols}")
            pre_screened = [{"symbol": s.upper(), "company_name": s.upper(), "last_price": 0,
                             "volume": 0, "volume_ratio": 1.0, "day_change_pct": 0.0,
                             "momentum_5d_pct": 0.0, "volatility_5d": 0.0}
                            for s in symbols]
        else:
            logger.info("[Intraday] Dynamically screening top intraday candidates from NSE universe...")
            pre_screened = await self.ds.screen_top_movers(limit=80, hold_duration_days=0)
            if not pre_screened:
                logger.warning("[Intraday] Dynamic screening returned no candidates, using last-resort list")
                pre_screened = [{"symbol": s, "company_name": s, "last_price": 0,
                                 "volume": 0, "volume_ratio": 1.0, "day_change_pct": 0.0,
                                 "momentum_5d_pct": 0.0, "volatility_5d": 0.0}
                                for s in _INTRADAY_LAST_RESORT]

        universe = [c["symbol"] for c in pre_screened]
        logger.info(f"[Intraday] Screened {len(universe)} candidates from NSE universe")
        logger.info(f"[Intraday] Fetching live quotes for {len(universe)} dynamically screened stocks...")

        # ── Step 2: Live quotes via Zerodha ────────────────────────────────
        try:
            logger.debug(f"[Intraday-QUOTE] About to call user_zerodha.get_quote() with {len(universe)} symbols")
            quotes = await user_zerodha.get_quote(universe)
            logger.info(f"[Intraday-QUOTE] Successfully got quotes for {len(quotes)} symbols")
        except Exception as e:
            logger.error(f"[Intraday-QUOTE-FAIL] Zerodha quote fetch failed with error: {e}")
            logger.error(f"[Intraday-QUOTE-FAIL] Error type: {type(e).__name__}")
            logger.error(f"[Intraday-QUOTE-FAIL] Will fall back to yfinance for {len(universe)} candidates")
            return await self._intraday_fallback_yfinance(limit, pre_screened)

        # now_ist used for both time-aware volume filter and candle from_date
        now_ist = datetime.now(self.IST)

        # ── Step 3: Build candidate list ───────────────────────────────────
        # Use time-aware volume threshold — early in the day full volume hasn't
        # accumulated yet. Before 11 AM IST: 50K; after 11 AM: 150K.
        market_hour = now_ist.hour
        if market_hour < 11:
            min_volume_threshold = 50_000    # early session — volume still building
        elif market_hour < 13:
            min_volume_threshold = 100_000   # mid-morning
        else:
            min_volume_threshold = 150_000   # afternoon — full volume available

        candidates = []
        for symbol in universe:
            quote_key = f"NSE:{symbol}"
            if quote_key not in quotes:
                continue

            q = quotes[quote_key]
            last_price = float(q.get("last_price", 0))
            volume = int(q.get("volume", 0))
            instrument_token = q.get("instrument_token", 0)
            ohlc = q.get("ohlc", {})
            prev_close = float(ohlc.get("close", last_price))
            today_open = float(ohlc.get("open", last_price))
            today_high = float(ohlc.get("high", last_price))
            today_low = float(ohlc.get("low", last_price))

            if last_price < 10 or last_price > 15000:
                continue
            if volume < min_volume_threshold:
                continue

            day_change_pct = (
                (last_price - prev_close) / prev_close * 100 if prev_close > 0 else 0.0
            )

            candidates.append({
                "symbol": symbol,
                "company_name": symbol,
                "last_price": last_price,
                "volume": volume,
                "instrument_token": instrument_token,
                "prev_close": prev_close,
                "today_open": today_open,
                "today_high": today_high,
                "today_low": today_low,
                "day_change_pct": round(day_change_pct, 2),
            })

        logger.info(f"[Intraday] {len(candidates)} candidates passed volume/price filters")

        if not candidates:
            logger.warning("[Intraday] No candidates from live quotes, using yfinance fallback")
            return await self._intraday_fallback_yfinance(limit, pre_screened)

        # Sort by volume descending, take top 35 for candle analysis
        # (increased from 25 → gives LLM a richer candidate pool)
        candidates.sort(key=lambda x: x["volume"], reverse=True)
        top_candidates = candidates[: min(35, len(candidates))]

        # ── Step 4: 5-minute candles + indicator calculation ───────────────
        from_date = now_ist.replace(hour=9, minute=15, second=0, microsecond=0)

        enriched = []
        for cand in top_candidates:
            token = cand["instrument_token"]
            symbol = cand["symbol"]

            if not token:
                continue

            try:
                candles = await user_zerodha.get_historical_data(
                    instrument_token=token,
                    from_date=from_date.strftime("%Y-%m-%d %H:%M:%S"),
                    to_date=now_ist.strftime("%Y-%m-%d %H:%M:%S"),
                    interval="5minute",
                )

                if not candles or len(candles) < 5:
                    logger.debug(
                        f"[Intraday] {symbol}: only {len(candles) if candles else 0} candles, skipping"
                    )
                    continue

                df = pd.DataFrame(candles)
                df.columns = [c.lower() if isinstance(c, str) else c for c in df.columns]
                for col in ["open", "high", "low", "close", "volume"]:
                    if col in df.columns:
                        df[col] = df[col].astype(float)

                indicators = await self.calculate_intraday_indicators(df, cand, kite_instance=kite_instance)
                if not indicators:
                    continue

                signal_data = strategy_engine.generate_intraday_signal(indicators)

                # 20-day avg volume — prefer Zerodha, fall back to yfinance
                if kite_instance and token:
                    avg_vol_20d = await self._get_avg_volume_zerodha(kite_instance, token)
                else:
                    avg_vol_20d = await self._get_avg_volume(symbol)
                volume_ratio = cand["volume"] / avg_vol_20d if avg_vol_20d > 0 else 1.0

                enriched.append({
                    **cand,
                    "volume_ratio": round(volume_ratio, 2),
                    "avg_volume_20d": round(avg_vol_20d, 0),
                    "indicators": indicators,
                    "intraday_signal": signal_data.get("signal", "NEUTRAL"),
                    "signal_strength": signal_data.get("strength", 0),
                    "signal_reasons": signal_data.get("reasons", []),
                    "hold_adjusted_score": signal_data.get("score", 0),
                    "composite_score": signal_data.get("score", 0),
                    "momentum_5d_pct": cand["day_change_pct"],
                    "volatility_5d": round(indicators.get("atr", 0) / cand["last_price"] * 100, 2),
                })

            except Exception as e:
                logger.debug(f"[Intraday] Error enriching {symbol}: {e}")
                continue

        logger.info(f"[Intraday] Enriched {len(enriched)} stocks with 5min indicators")

        # Sort: prefer signal_strength >= 2, then volume_ratio
        enriched.sort(
            key=lambda x: (x.get("signal_strength", 0), x.get("volume_ratio", 0)),
            reverse=True,
        )
        return enriched[:limit]

    async def calculate_intraday_indicators(
        self, df: pd.DataFrame, quote_data: Dict, kite_instance=None
    ) -> Dict:
        """
        Calculate intraday-specific technical indicators from 5-minute candles:
        - VWAP  (Volume Weighted Average Price — institutional benchmark)
        - Bollinger Bands  (20-period — volatility bands)
        - RSI 14          (momentum)
        - MACD 12/26/9    (momentum crossover)
        - Stochastic 14/3 (faster oscillator for intraday)
        - EMA 9 / EMA 21  (dynamic support/resistance)
        - ATR 14          (for stop-loss / target calculation)
        - Pivot Points     (from previous day's OHLC)
        """
        if df.empty or len(df) < 5:
            return {}

        try:
            close = df["close"]
            high = df["high"]
            low = df["low"]
            volume = df["volume"]
            last_close = float(close.iloc[-1])
            n = len(df)

            # ── VWAP (typical price × volume) ─────────────────────────────
            typical_price = (high + low + close) / 3
            cumtp_vol = (typical_price * volume).cumsum()
            cumvol = volume.cumsum()
            vwap = float(cumtp_vol.iloc[-1] / cumvol.iloc[-1]) if float(cumvol.iloc[-1]) > 0 else last_close
            price_vs_vwap = "ABOVE" if last_close > vwap else "BELOW"

            # ── ATR (14-period) ────────────────────────────────────────────
            hl = high - low
            hc = (high - close.shift()).abs()
            lc = (low - close.shift()).abs()
            tr = pd.concat([hl, hc, lc], axis=1).max(axis=1)
            atr = float(tr.rolling(min(14, n)).mean().iloc[-1])

            # ── RSI (14-period) ────────────────────────────────────────────
            delta = close.diff()
            gain = delta.where(delta > 0, 0.0).rolling(min(14, n)).mean()
            loss = (-delta.where(delta < 0, 0.0)).rolling(min(14, n)).mean()
            rs = gain / loss.replace(0, float("nan"))
            rsi = float((100 - 100 / (1 + rs)).iloc[-1])

            # ── MACD (12/26/9) ─────────────────────────────────────────────
            ema_12 = close.ewm(span=12, adjust=False).mean()
            ema_26 = close.ewm(span=26, adjust=False).mean()
            macd_line = ema_12 - ema_26
            signal_line = macd_line.ewm(span=9, adjust=False).mean()
            macd_hist_series = macd_line - signal_line
            macd_hist = float(macd_hist_series.iloc[-1])
            macd_val = float(macd_line.iloc[-1])
            macd_signal_val = float(signal_line.iloc[-1])

            macd_bullish_crossover = False
            macd_bearish_crossover = False
            if n >= 2:
                prev_hist = float(macd_hist_series.iloc[-2])
                macd_bullish_crossover = prev_hist < 0 < macd_hist
                macd_bearish_crossover = prev_hist > 0 > macd_hist

            # ── Bollinger Bands (20-period) ────────────────────────────────
            bb_period = min(20, n)
            bb_middle_s = close.rolling(bb_period).mean()
            bb_std_s = close.rolling(bb_period).std()
            bb_middle = float(bb_middle_s.iloc[-1])
            bb_std = float(bb_std_s.iloc[-1]) if not pd.isna(bb_std_s.iloc[-1]) else 0.0
            bb_upper = bb_middle + 2 * bb_std
            bb_lower = bb_middle - 2 * bb_std

            if last_close >= bb_upper * 0.985:
                bb_position = "NEAR_UPPER"
            elif last_close <= bb_lower * 1.015:
                bb_position = "NEAR_LOWER"
            else:
                bb_position = "MIDDLE"

            # ── Stochastic %K / %D (14, 3) ────────────────────────────────
            stoch_period = min(14, n)
            low_min = low.rolling(stoch_period).min()
            high_max = high.rolling(stoch_period).max()
            range_hl = (high_max - low_min).replace(0, float("nan"))
            stoch_k_series = 100 * (close - low_min) / range_hl
            stoch_k = float(stoch_k_series.iloc[-1]) if not pd.isna(stoch_k_series.iloc[-1]) else 50.0
            stoch_d = float(stoch_k_series.rolling(3).mean().iloc[-1]) if not pd.isna(stoch_k_series.rolling(3).mean().iloc[-1]) else 50.0

            if stoch_k > 80 and stoch_d > 80:
                stoch_signal = "OVERBOUGHT"
            elif stoch_k < 20 and stoch_d < 20:
                stoch_signal = "OVERSOLD"
            elif stoch_k > stoch_d:
                stoch_signal = "BULLISH"
            else:
                stoch_signal = "BEARISH"

            # ── EMA 9 and EMA 21 ───────────────────────────────────────────
            ema_9 = float(close.ewm(span=9, adjust=False).mean().iloc[-1])
            ema_21 = float(close.ewm(span=21, adjust=False).mean().iloc[-1])

            # ── Pivot Points from previous day ─────────────────────────────
            symbol = quote_data.get("symbol", "")
            token = quote_data.get("instrument_token", 0)
            if kite_instance and token:
                pivots = await self._fetch_pivot_points_zerodha(kite_instance, token)
                if not pivots:
                    pivots = await self._get_pivot_points_async(symbol, quote_data)
            else:
                pivots = await self._get_pivot_points_async(symbol, quote_data)

            # ── Volume of latest candle ────────────────────────────────────
            latest_candle_vol = float(volume.iloc[-1])
            avg_candle_vol = float(volume.mean())

            return {
                "last_close": round(last_close, 2),
                "atr": round(atr, 2),
                # VWAP
                "vwap": round(vwap, 2),
                "price_vs_vwap": price_vs_vwap,
                # RSI
                "rsi": round(rsi, 2),
                # MACD
                "macd": round(macd_val, 4),
                "macd_signal": round(macd_signal_val, 4),
                "macd_histogram": round(macd_hist, 4),
                "macd_bullish_crossover": macd_bullish_crossover,
                "macd_bearish_crossover": macd_bearish_crossover,
                # Bollinger Bands
                "bb_upper": round(bb_upper, 2),
                "bb_middle": round(bb_middle, 2),
                "bb_lower": round(bb_lower, 2),
                "bb_position": bb_position,
                # Stochastic
                "stoch_k": round(stoch_k, 2),
                "stoch_d": round(stoch_d, 2),
                "stoch_signal": stoch_signal,
                # EMA
                "ema_9": round(ema_9, 2),
                "ema_21": round(ema_21, 2),
                # Volume
                "avg_candle_volume": round(avg_candle_vol, 0),
                "latest_candle_volume": round(latest_candle_vol, 0),
                # Pivot Points
                **pivots,
            }

        except Exception as e:
            logger.error(f"Intraday indicator calculation failed: {e}")
            return {}

    # ── Pivot Points ──────────────────────────────────────────────────────────

    async def _get_pivot_points_async(self, symbol: str, quote_data: Dict) -> Dict:
        loop = asyncio.get_event_loop()
        try:
            pivots = await loop.run_in_executor(None, self._fetch_pivot_points, symbol)
            return pivots
        except Exception as e:
            logger.debug(f"Pivot points fetch failed for {symbol}: {e}")
            lp = quote_data.get("last_price", 100.0)
            return {
                "pivot": round(lp, 2),
                "r1": round(lp * 1.01, 2),
                "r2": round(lp * 1.02, 2),
                "s1": round(lp * 0.99, 2),
                "s2": round(lp * 0.98, 2),
            }

    def _fetch_pivot_points(self, symbol: str) -> Dict:
        """Synchronous: fetch last 5 days of daily data, use previous session for pivots."""
        try:
            ticker = yf.Ticker(f"{symbol}.NS")
            hist = ticker.history(period="5d", interval="1d")
            if len(hist) < 2:
                raise ValueError("Insufficient daily data")

            prev = hist.iloc[-2]
            H = float(prev["High"])
            L = float(prev["Low"])
            C = float(prev["Close"])

            P = (H + L + C) / 3
            R1 = 2 * P - L
            R2 = P + (H - L)
            S1 = 2 * P - H
            S2 = P - (H - L)

            return {
                "pivot": round(P, 2),
                "r1": round(R1, 2),
                "r2": round(R2, 2),
                "s1": round(S1, 2),
                "s2": round(S2, 2),
            }
        except Exception as e:
            logger.debug(f"_fetch_pivot_points failed for {symbol}: {e}")
            return {}

    async def _get_avg_volume(self, symbol: str) -> float:
        """Get 20-day average daily volume from yfinance."""
        loop = asyncio.get_event_loop()
        try:
            def _fetch():
                ticker = yf.Ticker(f"{symbol}.NS")
                hist = ticker.history(period="30d", interval="1d")
                if hist.empty or "Volume" not in hist.columns:
                    return 0.0
                return float(hist["Volume"].mean())
            return await loop.run_in_executor(None, _fetch)
        except Exception:
            return 0.0

    async def _fetch_pivot_points_zerodha(self, kite_instance, token: int) -> Dict:
        """Fetch pivot points using Zerodha historical daily data."""
        loop = asyncio.get_event_loop()
        try:
            to_dt = datetime.now(self.IST)
            from_dt = to_dt - timedelta(days=5)

            def _fetch():
                return kite_instance.historical_data(
                    token,
                    from_dt.replace(tzinfo=None),
                    to_dt.replace(tzinfo=None),
                    "day",
                )

            hist = await loop.run_in_executor(None, _fetch)
            if not hist or len(hist) < 2:
                return {}

            prev = hist[-2]
            H = float(prev["high"])
            L = float(prev["low"])
            C = float(prev["close"])

            P = (H + L + C) / 3
            R1 = 2 * P - L
            R2 = P + (H - L)
            S1 = 2 * P - H
            S2 = P - (H - L)

            return {
                "pivot": round(P, 2),
                "r1": round(R1, 2),
                "r2": round(R2, 2),
                "s1": round(S1, 2),
                "s2": round(S2, 2),
            }
        except Exception as e:
            logger.debug(f"_fetch_pivot_points_zerodha failed: {e}")
            return {}

    async def _get_avg_volume_zerodha(self, kite_instance, token: int) -> float:
        """Get 30-day average volume from Zerodha historical data."""
        loop = asyncio.get_event_loop()
        try:
            to_dt = datetime.now(self.IST)
            from_dt = to_dt - timedelta(days=35)

            def _fetch():
                return kite_instance.historical_data(
                    token,
                    from_dt.replace(tzinfo=None),
                    to_dt.replace(tzinfo=None),
                    "day",
                )

            hist = await loop.run_in_executor(None, _fetch)
            if not hist:
                return 0.0
            volumes = [float(h.get("volume", 0)) for h in hist if h.get("volume")]
            return sum(volumes) / len(volumes) if volumes else 0.0
        except Exception:
            return 0.0

    # ── yfinance fallback for intraday (when Zerodha quotes unavailable) ──────

    async def _intraday_fallback_yfinance(
        self, limit: int, pre_screened: Optional[List[Dict]] = None
    ) -> List[Dict]:
        """
        Fallback: use yfinance 5-minute data when Zerodha quotes are unavailable.
        Uses pre-screened candidates from screen_top_movers() if available,
        otherwise screens dynamically from the full NSE universe.
        """
        logger.warning("[Intraday-FALLBACK] Zerodha quote fetch failed. Using yfinance as fallback for 5-minute candle analysis")
        from app.engines.strategy_engine import strategy_engine

        # Use pre-screened candidates if passed in (avoids double screening)
        if pre_screened is None:
            logger.info("[Intraday-FALLBACK] Screening top movers from NSE universe for yfinance fallback...")
            pre_screened = await self.ds.screen_top_movers(limit=40, hold_duration_days=0)
        else:
            logger.info(f"[Intraday-FALLBACK] Using {len(pre_screened)} pre-screened candidates from earlier screening")

        if not pre_screened:
            logger.warning("[Intraday-FALLBACK] Dynamic screening returned nothing, using last-resort list")
            pre_screened = [{"symbol": s, "company_name": s, "last_price": 0,
                             "volume": 0, "volume_ratio": 1.0, "day_change_pct": 0.0,
                             "momentum_5d_pct": 0.0, "volatility_5d": 0.0}
                            for s in _INTRADAY_LAST_RESORT]
            logger.info(f"[Intraday-FALLBACK] Using {len(pre_screened)} last-resort stocks")

        logger.info(f"[Intraday-FALLBACK] Processing {len(pre_screened)} candidates with yfinance (timeout fallback)...")
        enriched = []
        filtered_count = 0
        error_count = 0
        for mover in pre_screened:
            symbol = mover["symbol"]
            try:
                loop = asyncio.get_event_loop()
                df = await loop.run_in_executor(
                    None, self._fetch_5min_yfinance, symbol
                )
                if df.empty or len(df) < 5:
                    filtered_count += 1
                    logger.info(f"[Intraday-FALLBACK] {symbol}: FILTERED (insufficient candles: {len(df) if not df.empty else 0})")
                    continue

                last_close = float(df["close"].iloc[-1])
                volume = int(df["volume"].iloc[-1])

                # Relaxed thresholds in fallback mode (Zerodha timeout)
                # Normal: vol >= 200K, price >= 10
                # Fallback: vol >= 50K, price >= 5
                min_volume_fallback = 50_000
                min_price_fallback = 5

                if volume < min_volume_fallback or last_close < min_price_fallback:
                    filtered_count += 1
                    reason = "low_volume" if volume < min_volume_fallback else "low_price"
                    logger.info(f"[Intraday-FALLBACK] {symbol}: FILTERED ({reason}: vol={volume:,}, price=₹{last_close})")
                    continue

                cand = {
                    "symbol": symbol,
                    "company_name": mover.get("company_name", symbol),
                    "last_price": last_close,
                    "volume": mover.get("volume", volume),
                    "instrument_token": 0,
                    "prev_close": mover.get("last_price", last_close),
                    "day_change_pct": mover.get("day_change_pct", 0.0),
                }

                indicators = await self.calculate_intraday_indicators(df, cand)
                if not indicators:
                    filtered_count += 1
                    logger.info(f"[Intraday-FALLBACK] {symbol}: FILTERED (no valid indicators)")
                    continue

                signal_data = strategy_engine.generate_intraday_signal(indicators)
                enriched.append({
                    **cand,
                    "volume_ratio": mover.get("volume_ratio", 1.0),
                    "indicators": indicators,
                    "intraday_signal": signal_data.get("signal", "NEUTRAL"),
                    "signal_strength": signal_data.get("strength", 0),
                    "signal_reasons": signal_data.get("reasons", []),
                    "hold_adjusted_score": signal_data.get("score", 0),
                    "composite_score": signal_data.get("score", 0),
                    "momentum_5d_pct": mover.get("momentum_5d_pct", 0.0),
                    "volatility_5d": mover.get("volatility_5d", 0.0),
                })
            except Exception as e:
                error_count += 1
                logger.warning(f"[Intraday-FALLBACK] Error enriching {symbol}: {type(e).__name__}: {e}")
                continue

        enriched.sort(key=lambda x: x.get("signal_strength", 0), reverse=True)

        # Summary stats
        total_processed = len(pre_screened)
        success_count = len(enriched)

        logger.info(
            f"[Intraday-FALLBACK-SUMMARY] Results: {success_count} enriched / "
            f"{total_processed} candidates | "
            f"filtered={filtered_count} | errors={error_count} | "
            f"success_rate={(success_count*100//total_processed if total_processed else 0)}%"
        )

        if len(enriched) == 0:
            logger.warning("[Intraday-FALLBACK-ZERO] No stocks passed yfinance enrichment! Returning empty list to user")
        else:
            logger.info(f"[Intraday-FALLBACK] Returning top {min(limit, len(enriched))} stocks to user")

        return enriched[:limit]

    def _fetch_5min_yfinance(self, symbol: str) -> pd.DataFrame:
        try:
            ticker = yf.Ticker(f"{symbol}.NS")
            df = ticker.history(period="1d", interval="5m")
            if df.empty:
                logger.debug(f"[Intraday-FALLBACK-YFINANCE] {symbol}: No 5-minute data available from yfinance")
                return pd.DataFrame()

            logger.debug(f"[Intraday-FALLBACK-YFINANCE] {symbol}: Fetched {len(df)} 5-minute candles")

            df = df.reset_index()
            df.columns = df.columns.str.lower()
            if "datetime" in df.columns:
                df = df.rename(columns={"datetime": "date"})
            for col in ["open", "high", "low", "close", "volume"]:
                if col in df.columns:
                    df[col] = df[col].astype(float)
            return df
        except Exception as e:
            logger.warning(f"[Intraday-FALLBACK-YFINANCE] {symbol}: yfinance error: {type(e).__name__}: {e}")
            return pd.DataFrame()

    # ── Swing indicators (60-day daily) ──────────────────────────────────────

    def _rank_by_hold_duration(
        self, stocks: List[Dict], hold_duration_days: int
    ) -> List[Dict]:
        for s in stocks:
            ind = s.get("indicators", {})
            vr = s.get("volume_ratio", 1.0)
            mom = max(s.get("momentum_5d_pct", 0), 0)
            vol = max(s.get("volatility_5d", 1.0), 0.1)
            rsi = ind.get("rsi", 50)
            trend = 1.0 if ind.get("trend") == "BULLISH" else 0.3

            rsi_fitness = 1.0 - abs(rsi - 63) / 37 if rsi else 0.5
            rsi_fitness = max(rsi_fitness, 0)

            if hold_duration_days <= 7:
                score = vr * 0.4 + mom * 0.35 + rsi_fitness * 0.25
            else:
                score = trend * 0.4 + rsi_fitness * 0.35 + vr * 0.25

            s["hold_adjusted_score"] = round(score, 4)

        stocks.sort(key=lambda x: x.get("hold_adjusted_score", 0), reverse=True)
        return stocks

    async def calculate_technical_indicators(self, df: pd.DataFrame) -> Dict:
        """Standard daily indicators for swing/delivery trades."""
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

            hl = high - low
            hc = (high - close.shift()).abs()
            lc = (low - close.shift()).abs()
            tr = pd.concat([hl, hc, lc], axis=1).max(axis=1)
            atr = float(tr.rolling(14).mean().iloc[-1])

            sma_20 = float(close.rolling(20).mean().iloc[-1])
            sma_50 = float(close.rolling(50).mean().iloc[-1]) if len(df) >= 50 else None
            ema_9 = float(close.ewm(span=9, adjust=False).mean().iloc[-1])
            ema_21 = float(close.ewm(span=21, adjust=False).mean().iloc[-1])

            delta = close.diff()
            gain = delta.where(delta > 0, 0).rolling(14).mean()
            loss = (-delta.where(delta < 0, 0)).rolling(14).mean()
            rs = gain / loss.replace(0, float("nan"))
            rsi = float((100 - 100 / (1 + rs)).iloc[-1])

            ema_12 = close.ewm(span=12, adjust=False).mean()
            ema_26 = close.ewm(span=26, adjust=False).mean()
            macd_line = ema_12 - ema_26
            signal_line = macd_line.ewm(span=9, adjust=False).mean()
            macd_hist = float((macd_line - signal_line).iloc[-1])
            macd_val = float(macd_line.iloc[-1])

            avg_vol_20 = float(volume.rolling(20).mean().iloc[-1])
            latest_vol = float(volume.iloc[-1])
            volume_ratio = latest_vol / avg_vol_20 if avg_vol_20 > 0 else 1.0

            trend = "BULLISH" if last_close > sma_20 else "BEARISH"
            if sma_50 and last_close > sma_50 and last_close > sma_20:
                trend = "STRONG_BULLISH"

            support_20d = float(low.rolling(20).min().iloc[-1])
            resistance_20d = float(high.rolling(20).max().iloc[-1])
            high_52w = float(high.max())
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
        return await self.screen_and_enrich(limit=limit, analysis_date=analysis_date)


analysis_service = AnalysisService()
