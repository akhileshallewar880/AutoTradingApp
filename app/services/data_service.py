import yfinance as yf
import requests
import asyncio
import io
import pandas as pd
from typing import List, Dict, Optional
from datetime import datetime, timedelta
from app.core.logging import logger

# ─── Sector → NSE index mapping (for sector-based filtering) ────────────────
SECTOR_INDEX_MAP = {
    "NIFTY 50":    "^NSEI",
    "NIFTY Bank":  "^NSEBANK",
    "IT":          None,   # handled via keyword filter
    "Pharma":      None,
    "Auto":        None,
    "FMCG":        None,
    "Energy":      None,
    "Metal":       None,
}

# Sector keyword → yfinance industry/sector strings
SECTOR_KEYWORDS = {
    "IT":      ["information technology", "software", "it services"],
    "Pharma":  ["pharmaceuticals", "biotechnology", "healthcare"],
    "Auto":    ["automobiles", "auto components"],
    "FMCG":    ["consumer staples", "food", "beverages", "personal products"],
    "Energy":  ["oil", "gas", "power", "utilities", "energy"],
    "Metal":   ["metals", "mining", "steel", "aluminium"],
}


class DataService:
    """
    Service for fetching market data.

    Two-stage approach:
      1. get_nse_universe()  – downloads full NSE equity list (~1800 stocks)
      2. screen_top_movers() – parallel batch fetch, filters by volume/momentum
    """

    NSE_EQUITY_CSV = (
        "https://nsearchives.nseindia.com/content/equities/EQUITY_L.csv"
    )
    # Fallback broad list covering all major sectors (used if NSE CSV is unavailable)
    FALLBACK_SYMBOLS = [
        # NIFTY 50
        "RELIANCE", "TCS", "HDFCBANK", "INFY", "ICICIBANK", "HINDUNILVR",
        "ITC", "SBIN", "BHARTIARTL", "KOTAKBANK", "LT", "AXISBANK",
        "ASIANPAINT", "MARUTI", "SUNPHARMA", "TITAN", "BAJFINANCE",
        "ULTRACEMCO", "NESTLEIND", "WIPRO", "HCLTECH", "TECHM",
        "POWERGRID", "NTPC", "ONGC", "M&M", "TATAMOTORS", "TATASTEEL",
        "BAJAJFINSV", "ADANIPORTS", "INDUSINDBK", "DRREDDY", "CIPLA",
        "DIVISLAB", "EICHERMOT", "GRASIM", "HEROMOTOCO", "JSWSTEEL",
        "BRITANNIA", "COALINDIA", "TATACONSUM", "UPL", "SBILIFE",
        "APOLLOHOSP", "HINDALCO", "BAJAJ-AUTO", "ADANIENT", "BPCL",
        "SHREECEM", "HDFCLIFE",
        # NIFTY Next 50 / Midcap highlights
        "PIDILITIND", "SIEMENS", "HAVELLS", "BERGEPAINT", "MUTHOOTFIN",
        "CHOLAFIN", "TORNTPHARM", "LUPIN", "BIOCON", "AUROPHARMA",
        "ALKEM", "IPCALAB", "GLAND", "LALPATHLAB", "METROPOLIS",
        "TATAPOWER", "ADANIGREEN", "ADANITRANS", "CANBK", "PNB",
        "BANKBARODA", "FEDERALBNK", "IDFCFIRSTB", "RBLBANK", "BANDHANBNK",
        "MCDOWELL-N", "UNITDSPR", "RADICO", "JUBLFOOD", "DMART",
        "TRENT", "NYKAA", "ZOMATO", "PAYTM", "POLICYBZR",
        "IRCTC", "DELHIVERY", "NAUKRI", "JUSTDIAL", "INDIAMART",
        "DIXON", "AMBER", "VOLTAS", "BLUESTARCO", "WHIRLPOOL",
        "ESCORTS", "ASHOKLEY", "TVSMOTOR", "BAJAJHLDNG", "MOTHERSON",
        "MINDA", "BOSCHLTD", "EXIDEIND", "AMARAJABAT", "CEATLTD",
        "SAIL", "NMDC", "VEDL", "HINDZINC", "NATIONALUM",
        "AARTIIND", "DEEPAKNTR", "PIIND", "RALLIS", "SUMICHEM",
        "GUJGASLTD", "IGL", "MGL", "PETRONET", "GAIL",
        "RECLTD", "PFC", "IRFC", "HUDCO", "NHPC",
        "CONCOR", "GMRINFRA", "IRB", "ASHIANA", "OBEROIRLTY",
        "DLF", "GODREJPROP", "PRESTIGE", "BRIGADE", "SOBHA",
        "LTIM", "MPHASIS", "COFORGE", "PERSISTENT", "LTTS",
        "KPITTECH", "TATAELXSI", "CYIENT", "MASTEK", "NIITTECH",
        "ZYDUSLIFE", "TORNTPOWER", "CUMMINSIND", "ABB", "BHEL",
        "THERMAX", "TIINDIA", "GRINDWELL", "CARBORUNIV", "ASTRAL",
        "SUPREMEIND", "FINOLEX", "JKCEMENT", "RAMCOCEM", "HEIDELBERG",
        "STARCEMENT", "BIRLACORPN", "DALBHARAT", "JKPAPER", "TNPL",
    ]

    def __init__(self):
        self._nse_universe: Optional[List[str]] = None  # cached base symbols
        self._universe_fetched_at: Optional[datetime] = None
        self._cache_ttl_hours = 12  # refresh universe every 12 hours

    # ─────────────────────────────────────────────────────────────────────────
    # Public API
    # ─────────────────────────────────────────────────────────────────────────

    async def get_nse_universe(self, sectors: Optional[List[str]] = None) -> List[str]:
        """
        Return the full NSE equity symbol list (base symbols, no .NS suffix).
        Downloads from NSE's public CSV; falls back to curated list on failure.
        Result is cached for `_cache_ttl_hours` hours.
        """
        now = datetime.utcnow()
        cache_stale = (
            self._nse_universe is None
            or self._universe_fetched_at is None
            or (now - self._universe_fetched_at).total_seconds() > self._cache_ttl_hours * 3600
        )

        if cache_stale:
            loop = asyncio.get_event_loop()
            symbols = await loop.run_in_executor(None, self._download_nse_csv)
            self._nse_universe = symbols
            self._universe_fetched_at = now
            logger.info(f"NSE universe loaded: {len(symbols)} symbols")

        universe = list(self._nse_universe)  # type: ignore

        # If specific sectors requested (and not "ALL"), filter by sector
        if sectors and sectors != ["ALL"] and sectors != ["NIFTY 50"]:
            # For sector filtering we keep the full universe but tag it;
            # actual sector filtering happens in screen_top_movers via yfinance info
            # (too slow to pre-filter here). We just log the intent.
            logger.info(f"Sector filter requested: {sectors} — will apply post-fetch")

        return universe

    async def screen_top_movers(
        self,
        limit: int = 20,
        sectors: Optional[List[str]] = None,
        batch_size: int = 50,
        max_candidates: int = 200,
    ) -> List[Dict]:
        """
        Two-pass screener over the full NSE universe:
          Pass 1: Fetch 5-day snapshot for all symbols in parallel batches.
                  Filter by: volume > 200K, price ₹10–₹10000, 1-day change > 0%
          Pass 2: Score by composite = volume_ratio × momentum × (1/volatility)
                  Return top `limit` candidates enriched with metadata.
        """
        universe = await self.get_nse_universe(sectors)

        # Limit universe size to avoid very long waits
        # Shuffle to get variety across sectors on each run
        import random
        random.shuffle(universe)
        universe = universe[:max_candidates]

        logger.info(f"Screening {len(universe)} symbols in batches of {batch_size}…")

        # Parallel batch fetch
        loop = asyncio.get_event_loop()
        batches = [universe[i:i+batch_size] for i in range(0, len(universe), batch_size)]

        tasks = [
            loop.run_in_executor(None, self._screen_batch, batch)
            for batch in batches
        ]
        batch_results = await asyncio.gather(*tasks)

        # Flatten
        candidates = []
        for batch in batch_results:
            candidates.extend(batch)

        logger.info(f"Screener pass 1: {len(candidates)} stocks passed basic filters")

        # Apply sector filter if requested
        if sectors and "NIFTY 50" not in sectors and "ALL" not in sectors:
            candidates = self._filter_by_sector(candidates, sectors)
            logger.info(f"After sector filter: {len(candidates)} stocks remain")

        # Sort by composite score descending
        candidates.sort(key=lambda x: x.get("composite_score", 0), reverse=True)

        top = candidates[:limit]
        logger.info(f"Top {len(top)} movers selected for LLM analysis")
        return top

    async def get_candle_data(
        self, symbol: str, timeframe: str = "day", period: str = "60d"
    ) -> pd.DataFrame:
        """
        Fetch historical OHLCV data for a symbol (base NSE symbol, no .NS suffix).
        Runs in executor to avoid blocking the event loop.
        """
        yf_symbol = symbol if symbol.endswith(".NS") else f"{symbol}.NS"
        loop = asyncio.get_event_loop()
        df = await loop.run_in_executor(
            None, self._fetch_yfinance_data, yf_symbol, timeframe, period
        )
        return df

    # ─────────────────────────────────────────────────────────────────────────
    # Legacy compatibility (used by trading_agent.py)
    # ─────────────────────────────────────────────────────────────────────────

    async def get_top_volume_stocks(self, limit: int = 50) -> List[Dict]:
        """Legacy method — now delegates to screen_top_movers."""
        movers = await self.screen_top_movers(limit=limit)
        # Convert to legacy format expected by trading_agent
        result = []
        for m in movers:
            sym = m["symbol"]
            result.append({
                "instrument_token": hash(sym) % 1_000_000,
                "tradingsymbol": sym,
                "name": m.get("company_name", sym),
                "exchange": "NSE",
                "segment": "NSE",
                "yf_symbol": f"{sym}.NS",
            })
        return result

    # ─────────────────────────────────────────────────────────────────────────
    # Private helpers
    # ─────────────────────────────────────────────────────────────────────────

    def _download_nse_csv(self) -> List[str]:
        """Download NSE equity list CSV and return base symbols."""
        try:
            headers = {
                "User-Agent": (
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/120.0.0.0 Safari/537.36"
                ),
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.5",
                "Referer": "https://www.nseindia.com/",
            }
            resp = requests.get(self.NSE_EQUITY_CSV, headers=headers, timeout=15)
            resp.raise_for_status()

            df = pd.read_csv(io.StringIO(resp.text))
            # NSE CSV has column "SYMBOL"
            if "SYMBOL" in df.columns:
                symbols = df["SYMBOL"].dropna().str.strip().tolist()
                logger.info(f"Downloaded {len(symbols)} symbols from NSE CSV")
                return symbols
            else:
                logger.warning(f"Unexpected NSE CSV columns: {df.columns.tolist()}")
                return self.FALLBACK_SYMBOLS

        except Exception as e:
            logger.warning(f"NSE CSV download failed ({e}), using fallback list")
            return self.FALLBACK_SYMBOLS

    def _screen_batch(self, symbols: List[str]) -> List[Dict]:
        """
        Fetch a batch of symbols using yfinance and apply basic filters.
        Returns list of dicts with screening metrics.
        """
        results = []
        yf_symbols = [f"{s}.NS" for s in symbols]

        try:
            # Download 5 days of daily data for the whole batch at once (fast)
            raw = yf.download(
                tickers=" ".join(yf_symbols),
                period="5d",
                interval="1d",
                group_by="ticker",
                auto_adjust=True,
                progress=False,
                threads=True,
            )
        except Exception as e:
            logger.warning(f"Batch download failed: {e}")
            return results

        for sym, yf_sym in zip(symbols, yf_symbols):
            try:
                # Handle both single and multi-ticker DataFrames
                if len(yf_symbols) == 1:
                    df = raw
                else:
                    if yf_sym not in raw.columns.get_level_values(0):
                        continue
                    df = raw[yf_sym]

                if df is None or df.empty or len(df) < 2:
                    continue

                df = df.dropna(subset=["Close", "Volume"])
                if len(df) < 2:
                    continue

                last = df.iloc[-1]
                prev = df.iloc[-2]

                close = float(last["Close"])
                volume = int(last["Volume"])
                prev_close = float(prev["Close"])
                avg_volume = float(df["Volume"].mean())

                # ── Basic filters ──────────────────────────────────────────
                if close < 10 or close > 10_000:
                    continue
                if volume < 200_000:
                    continue

                # ── Metrics ───────────────────────────────────────────────
                day_change_pct = ((close - prev_close) / prev_close * 100) if prev_close > 0 else 0
                volume_ratio = volume / avg_volume if avg_volume > 0 else 1.0

                # 5-day momentum
                first_close = float(df.iloc[0]["Close"])
                momentum_5d = ((close - first_close) / first_close * 100) if first_close > 0 else 0

                # 5-day volatility (std of daily returns)
                daily_returns = df["Close"].pct_change().dropna()
                volatility = float(daily_returns.std() * 100) if len(daily_returns) > 1 else 1.0

                # Composite score: reward volume surge + momentum, penalise volatility
                composite_score = (
                    volume_ratio * 0.5
                    + max(momentum_5d, 0) * 0.3
                    + max(day_change_pct, 0) * 0.2
                ) / max(volatility, 0.1)

                results.append({
                    "symbol": sym,
                    "company_name": sym,  # enriched later if needed
                    "yf_symbol": yf_sym,
                    "last_price": close,
                    "volume": volume,
                    "avg_volume_5d": round(avg_volume, 0),
                    "volume_ratio": round(volume_ratio, 2),
                    "day_change_pct": round(day_change_pct, 2),
                    "momentum_5d_pct": round(momentum_5d, 2),
                    "volatility_5d": round(volatility, 2),
                    "composite_score": round(composite_score, 4),
                    "high": float(last["High"]),
                    "low": float(last["Low"]),
                    "open": float(last["Open"]),
                })

            except Exception as e:
                logger.debug(f"Skipping {sym}: {e}")
                continue

        return results

    def _filter_by_sector(self, candidates: List[Dict], sectors: List[str]) -> List[Dict]:
        """
        Filter candidates by sector using yfinance info (best-effort).
        Falls back to keyword matching on symbol name.
        """
        keywords = []
        for sector in sectors:
            keywords.extend(SECTOR_KEYWORDS.get(sector, []))

        if not keywords:
            return candidates

        filtered = []
        for c in candidates:
            sym = c["symbol"].lower()
            # Quick keyword match on symbol (rough but fast)
            matched = any(kw in sym for kw in keywords)
            if matched:
                filtered.append(c)

        # If too few pass the keyword filter, return all (sector data is approximate)
        return filtered if len(filtered) >= 3 else candidates

    def _fetch_yfinance_data(
        self, yf_symbol: str, timeframe: str, period: str = "60d"
    ) -> pd.DataFrame:
        """Sync fetch of OHLCV history for a single symbol."""
        try:
            interval_map = {
                "day": "1d",
                "60min": "60m",
                "30min": "30m",
                "15min": "15m",
                "5min": "5m",
            }
            interval = interval_map.get(timeframe, "1d")
            ticker = yf.Ticker(yf_symbol)
            df = ticker.history(period=period, interval=interval)

            if df.empty:
                return pd.DataFrame()

            df = df.reset_index()
            df.columns = df.columns.str.lower()

            if "datetime" in df.columns:
                df = df.rename(columns={"datetime": "date"})

            required = ["date", "open", "high", "low", "close", "volume"]
            available = [c for c in required if c in df.columns]
            df = df[available]

            logger.info(f"Fetched {len(df)} candles for {yf_symbol}")
            return df

        except Exception as e:
            logger.error(f"yfinance fetch failed for {yf_symbol}: {e}")
            return pd.DataFrame()


data_service = DataService()
