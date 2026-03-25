"""
NSE Sector Activity Service
============================
Fetches live sectoral index data using yfinance (primary) with NSE API as fallback.

yfinance symbols for NSE sectoral indices:
  ^CNXIT       Nifty IT
  ^NSEBANK     Nifty Bank
  ^CNXAUTO     Nifty Auto
  ^CNXPHARMA   Nifty Pharma
  ^CNXFMCG     Nifty FMCG
  ^CNXMETAL    Nifty Metal
  ^CNXREALTY   Nifty Realty
  ^CNXENERGY   Nifty Energy
  ^CNXINFRA    Nifty Infrastructure
  ^CNXFINANCE  Nifty Financial Services
  ^CNXPSE      Nifty PSE
  ^CNXMEDIA    Nifty Media

Change % is computed from the last two available daily closes.
Results cached 5 minutes.
"""

import time
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd
import yfinance as yf

from app.core.logging import logger


# ── Sector definitions ────────────────────────────────────────────────────────

# (sector_key, yfinance_symbol, display_name)
SECTOR_INDEX_MAP: List[Tuple[str, str, str]] = [
    ("NIFTY IT",                 "^CNXIT",      "IT"),
    ("NIFTY BANK",               "^NSEBANK",    "Banking"),
    ("NIFTY AUTO",               "^CNXAUTO",    "Auto"),
    ("NIFTY PHARMA",             "^CNXPHARMA",  "Pharma"),
    ("NIFTY FMCG",               "^CNXFMCG",    "FMCG"),
    ("NIFTY METAL",              "^CNXMETAL",   "Metal"),
    ("NIFTY REALTY",             "^CNXREALTY",  "Realty"),
    ("NIFTY ENERGY",             "^CNXENERGY",  "Energy"),
    ("NIFTY INFRA",              "^CNXINFRA",   "Infra"),
    ("NIFTY FINANCIAL SERVICES", "^CNXFINANCE", "Fin. Svcs"),
    ("NIFTY PSE",                "^CNXPSE",     "PSU"),
    ("NIFTY MEDIA",              "^CNXMEDIA",   "Media"),
]

SECTOR_STOCKS: Dict[str, List[str]] = {
    "NIFTY IT": [
        "TCS", "INFY", "WIPRO", "HCLTECH", "TECHM",
        "LTIM", "MPHASIS", "COFORGE", "PERSISTENT", "LTTS",
    ],
    "NIFTY BANK": [
        "HDFCBANK", "ICICIBANK", "SBIN", "KOTAKBANK", "AXISBANK",
        "INDUSINDBK", "BANDHANBNK", "FEDERALBNK", "IDFCFIRSTB", "RBLBANK",
    ],
    "NIFTY AUTO": [
        "MARUTI", "TATAMOTORS", "M&M", "HEROMOTOCO", "BAJAJ-AUTO",
        "EICHERMOT", "TVSMOTOR", "ASHOKLEY", "BALKRISIND", "MOTHERSON",
    ],
    "NIFTY PHARMA": [
        "SUNPHARMA", "DRREDDY", "CIPLA", "DIVISLAB", "AUROPHARMA",
        "LUPIN", "TORNTPHARM", "ALKEM", "GLENMARK", "IPCALAB",
    ],
    "NIFTY FMCG": [
        "HINDUNILVR", "ITC", "NESTLEIND", "BRITANNIA", "DABUR",
        "MARICO", "COLPAL", "GODREJCP", "EMAMILTD", "TATACONSUM",
    ],
    "NIFTY METAL": [
        "TATASTEEL", "JSWSTEEL", "HINDALCO", "VEDL", "SAIL",
        "NATIONALUM", "NMDC", "COALINDIA", "MOIL", "HINDCOPPER",
    ],
    "NIFTY REALTY": [
        "DLF", "GODREJPROP", "PRESTIGE", "BRIGADE", "SOBHA",
        "PHOENIXLTD", "OBEROIRLTY", "MAHLIFE", "SUNTECK",
    ],
    "NIFTY ENERGY": [
        "RELIANCE", "ONGC", "BPCL", "IOC", "HINDPETRO",
        "GAIL", "PETRONET", "ADANIGAS", "MGL", "IGL",
    ],
    "NIFTY INFRA": [
        "LT", "POWERGRID", "NTPC", "ADANIPORTS", "IRCTC",
        "BHARTIARTL", "ABB", "SIEMENS", "CUMMINSIND", "BHEL",
    ],
    "NIFTY FINANCIAL SERVICES": [
        "HDFCBANK", "ICICIBANK", "BAJFINANCE", "BAJAJFINSV", "SBIN",
        "KOTAKBANK", "AXISBANK", "LICHSGFIN", "MUTHOOTFIN", "CHOLAFIN",
    ],
    "NIFTY PSE": [
        "ONGC", "BPCL", "NTPC", "POWERGRID", "COALINDIA",
        "SAIL", "GAIL", "BHEL", "RECLTD", "PFC",
    ],
    "NIFTY MEDIA": [
        "ZEEL", "SUNTV", "PVRINOX", "NAUKRI", "SAREGAMA",
    ],
}


class NSESectorService:
    _CACHE_TTL = 300  # 5 minutes

    def __init__(self) -> None:
        self._cached: Optional[List[Dict]] = None
        self._last_fetch: float = 0.0

    # ── Public ────────────────────────────────────────────────────────────────

    def get_sector_activity(self) -> List[Dict]:
        """
        Returns sectors sorted by activity (most active first).

        Each dict:
            sector         : "NIFTY IT"
            display_name   : "IT"
            change_pct     : float  — % change from prev close
            last           : float  — current/last index level
            prev_close     : float  — previous close
            momentum       : "BULLISH" | "BEARISH" | "NEUTRAL"
            activity_score : float  — abs(change_pct) used for sorting
            stocks         : list[str]  — liquid symbols for this sector
        """
        now = time.time()
        if self._cached and (now - self._last_fetch) < self._CACHE_TTL:
            return self._cached

        sectors = self._fetch_with_yfinance()
        if sectors:
            self._cached = sectors
            self._last_fetch = now
            logger.info(
                f"[NSE] Refreshed {len(sectors)} sectors via yfinance"
            )
        else:
            logger.warning("[NSE] yfinance fetch failed — returning fallback")
            if not self._cached:
                self._cached = self._static_fallback()

        return self._cached or []

    def invalidate_cache(self) -> None:
        self._last_fetch = 0.0

    # ── yfinance fetch ────────────────────────────────────────────────────────

    def _fetch_with_yfinance(self) -> Optional[List[Dict]]:
        yf_symbols = [sym for _, sym, _ in SECTOR_INDEX_MAP]

        try:
            # period="5d" ensures we have at least 2 trading days even after holidays
            raw = yf.download(
                yf_symbols,
                period="5d",
                interval="1d",
                progress=False,
                auto_adjust=True,
                threads=True,
            )
        except Exception as exc:
            logger.warning(f"[NSE] yfinance download failed: {exc}")
            return None

        # ── Extract Close prices ───────────────────────────────────────────
        # raw may have a MultiIndex (Close, symbol) or single-level (single ticker)
        try:
            if isinstance(raw.columns, pd.MultiIndex):
                close_df = raw["Close"]
            else:
                close_df = raw[["Close"]]
                close_df.columns = [yf_symbols[0]]
        except KeyError:
            logger.warning("[NSE] yfinance response missing 'Close' column")
            return None

        close_df = close_df.dropna(how="all")
        if len(close_df) < 2:
            logger.warning(f"[NSE] Not enough rows ({len(close_df)}) to compute change")
            return None

        # Last two available trading-day closes
        prev_row = close_df.iloc[-2]
        last_row = close_df.iloc[-1]

        sectors: List[Dict] = []
        for sector_key, yf_sym, display in SECTOR_INDEX_MAP:
            try:
                prev  = float(prev_row.get(yf_sym, np.nan))
                last  = float(last_row.get(yf_sym, np.nan))
                if np.isnan(prev) or np.isnan(last) or prev == 0:
                    continue
                change_pct = round((last - prev) / prev * 100, 2)
            except Exception:
                continue

            if change_pct > 0.5:
                momentum = "BULLISH"
            elif change_pct < -0.5:
                momentum = "BEARISH"
            else:
                momentum = "NEUTRAL"

            sectors.append({
                "sector":         sector_key,
                "display_name":   display,
                "change_pct":     change_pct,
                "last":           round(last, 2),
                "prev_close":     round(prev, 2),
                "advances":       0,   # not available from index data alone
                "declines":       0,
                "activity_score": round(abs(change_pct), 3),
                "momentum":       momentum,
                "stocks":         SECTOR_STOCKS.get(sector_key, []),
            })

        if not sectors:
            return None

        sectors.sort(key=lambda x: x["activity_score"], reverse=True)
        return sectors

    # ── Fallback ──────────────────────────────────────────────────────────────

    def _static_fallback(self) -> List[Dict]:
        return [
            {
                "sector":         key,
                "display_name":   display,
                "change_pct":     0.0,
                "last":           0.0,
                "prev_close":     0.0,
                "advances":       0,
                "declines":       0,
                "activity_score": 0.0,
                "momentum":       "UNKNOWN",
                "stocks":         SECTOR_STOCKS.get(key, []),
            }
            for key, _, display in SECTOR_INDEX_MAP
        ]


nse_sector_service = NSESectorService()
