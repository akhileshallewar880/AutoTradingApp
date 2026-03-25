"""
NSE Sector Activity Service
============================
Fetches live sectoral index data from NSE India's public JSON API.

NSE requires a browser-like session (cookies set by visiting the homepage).
All results are cached for 5 minutes to avoid hammering the API.

Endpoint used:
  GET https://www.nseindia.com/api/allIndices
  → returns all indices with percentChange, advances, declines, last price.

We filter for the 12 main sectoral indices and compute an "activity score"
  = abs(percentChange) × total_movers (advances + declines)
to rank sectors by how much genuine movement is happening today.
"""

import time
from typing import Dict, List, Optional

import requests

from app.core.logging import logger


# ── Sector → constituent stocks (liquid NSE names usable with Zerodha) ───────

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
        "KOTAKBANK", "AXISBANK", "HDFC", "LICHSGFIN", "MUTHOOTFIN",
    ],
    "NIFTY PSE": [
        "ONGC", "BPCL", "NTPC", "POWERGRID", "COALINDIA",
        "SAIL", "GAIL", "BHEL", "RECLTD", "PFC",
    ],
    "NIFTY MEDIA": [
        "ZEEL", "SUNTV", "PVRINOX", "NAUKRI", "SAREGAMA",
    ],
}

# NSE API sometimes uses slightly different index names — normalise them
_NSE_INDEX_ALIASES: Dict[str, str] = {
    "Nifty IT": "NIFTY IT",
    "Nifty Bank": "NIFTY BANK",
    "Nifty Auto": "NIFTY AUTO",
    "Nifty Pharma": "NIFTY PHARMA",
    "Nifty FMCG": "NIFTY FMCG",
    "Nifty Metal": "NIFTY METAL",
    "Nifty Realty": "NIFTY REALTY",
    "Nifty Energy": "NIFTY ENERGY",
    "Nifty Infrastructure": "NIFTY INFRA",
    "Nifty Financial Services": "NIFTY FINANCIAL SERVICES",
    "Nifty PSE": "NIFTY PSE",
    "Nifty Media": "NIFTY MEDIA",
}

_BROWSER_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/122.0.0.0 Safari/537.36"
    ),
    "Accept":          "application/json, text/plain, */*",
    "Accept-Language": "en-US,en;q=0.9",
    "Accept-Encoding": "gzip, deflate, br",
    "Referer":         "https://www.nseindia.com/market-data/live-market-indices/heatmap",
    "X-Requested-With": "XMLHttpRequest",
}


class NSESectorService:
    """
    Singleton-style service that fetches and caches NSE sectoral index data.
    """

    _CACHE_TTL = 300          # seconds between API refreshes (5 min)
    _REQUEST_TIMEOUT = 12     # seconds per HTTP request

    def __init__(self) -> None:
        self._cached_sectors: Optional[List[Dict]] = None
        self._last_refresh: float = 0.0

    # ── Public API ────────────────────────────────────────────────────────────

    def get_sector_activity(self) -> List[Dict]:
        """
        Returns a list of sector dicts sorted by activity (most active first).

        Each dict has:
            sector        : str   — "NIFTY IT", "NIFTY BANK", …
            change_pct    : float — % change from previous close
            last          : float — current index level
            advances      : int   — advancing stocks count
            declines      : int   — declining stocks count
            activity_score: float — abs(change_pct) × (advances + declines)
            momentum      : str   — "BULLISH" | "BEARISH" | "NEUTRAL"
            stocks        : list  — recommended liquid symbols for this sector
        """
        now = time.time()
        if self._cached_sectors and (now - self._last_refresh) < self._CACHE_TTL:
            logger.debug("[NSE] Returning cached sector data")
            return self._cached_sectors

        sectors = self._fetch_from_nse()
        if sectors:
            self._cached_sectors = sectors
            self._last_refresh = now
            logger.info(f"[NSE] Refreshed {len(sectors)} sectors from NSE API")
        else:
            logger.warning("[NSE] NSE API unavailable — serving fallback static sector list")
            if not self._cached_sectors:
                # First-time failure: build a static fallback so caller always gets something
                self._cached_sectors = self._build_fallback()

        return self._cached_sectors or []

    def invalidate_cache(self) -> None:
        """Force refresh on next call."""
        self._last_refresh = 0.0

    # ── Internal ──────────────────────────────────────────────────────────────

    def _fetch_from_nse(self) -> Optional[List[Dict]]:
        try:
            session = self._make_session()
            raw = session.get(
                "https://www.nseindia.com/api/allIndices",
                timeout=self._REQUEST_TIMEOUT,
            )
            raw.raise_for_status()
            payload = raw.json()
        except Exception as exc:
            logger.warning(f"[NSE] allIndices fetch failed: {exc}")
            return None

        sectors: List[Dict] = []
        for item in payload.get("data", []):
            index_name: str = item.get("index", "")

            # Normalise alias names that NSE uses
            canonical = _NSE_INDEX_ALIASES.get(index_name, index_name)

            if canonical not in SECTOR_STOCKS:
                continue  # skip market-wide / thematic indices

            try:
                change_pct = float(item.get("percentChange", 0.0) or 0.0)
                last       = float(item.get("last",         0.0) or 0.0)
                advances   = int(item.get("advances",  0) or 0)
                declines   = int(item.get("declines",  0) or 0)
                unchanged  = int(item.get("unchanged", 0) or 0)
            except (ValueError, TypeError):
                continue

            total_movers   = advances + declines + unchanged
            activity_score = round(abs(change_pct) * max(total_movers, 1), 3)

            if change_pct > 0.5:
                momentum = "BULLISH"
            elif change_pct < -0.5:
                momentum = "BEARISH"
            else:
                momentum = "NEUTRAL"

            sectors.append({
                "sector":         canonical,
                "display_name":   _short_name(canonical),
                "change_pct":     round(change_pct, 2),
                "last":           round(last, 2),
                "advances":       advances,
                "declines":       declines,
                "unchanged":      unchanged,
                "activity_score": activity_score,
                "momentum":       momentum,
                "stocks":         SECTOR_STOCKS[canonical],
            })

        if not sectors:
            return None

        sectors.sort(key=lambda x: x["activity_score"], reverse=True)
        return sectors

    def _make_session(self) -> requests.Session:
        """
        Create a session with real browser cookies.
        NSE India blocks API calls that lack the session cookie set by the homepage.
        """
        s = requests.Session()
        s.headers.update(_BROWSER_HEADERS)
        try:
            # Warm up the session — sets nseappid, nsit, bm_sv cookies
            s.get("https://www.nseindia.com/", timeout=self._REQUEST_TIMEOUT)
        except Exception as e:
            logger.debug(f"[NSE] Homepage warm-up failed (continuing anyway): {e}")
        return s

    def _build_fallback(self) -> List[Dict]:
        """Static sector list used when NSE is unreachable (weekend / blocked)."""
        return [
            {
                "sector":         name,
                "display_name":   _short_name(name),
                "change_pct":     0.0,
                "last":           0.0,
                "advances":       0,
                "declines":       0,
                "unchanged":      0,
                "activity_score": 0.0,
                "momentum":       "UNKNOWN",
                "stocks":         stocks,
            }
            for name, stocks in SECTOR_STOCKS.items()
        ]


def _short_name(full: str) -> str:
    """'NIFTY FINANCIAL SERVICES' → 'Financial Svcs', etc."""
    mapping = {
        "NIFTY IT":                  "IT",
        "NIFTY BANK":                "Banking",
        "NIFTY AUTO":                "Auto",
        "NIFTY PHARMA":              "Pharma",
        "NIFTY FMCG":                "FMCG",
        "NIFTY METAL":               "Metal",
        "NIFTY REALTY":              "Realty",
        "NIFTY ENERGY":              "Energy",
        "NIFTY INFRA":               "Infra",
        "NIFTY FINANCIAL SERVICES":  "Fin. Svcs",
        "NIFTY PSE":                 "PSU",
        "NIFTY MEDIA":               "Media",
    }
    return mapping.get(full, full.replace("NIFTY ", "").title())


# ── Singleton ─────────────────────────────────────────────────────────────────
nse_sector_service = NSESectorService()
