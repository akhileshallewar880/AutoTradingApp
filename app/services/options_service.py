"""
Options Service — Zerodha NFO instrument lookup, option chain filtering,
ATM strike selection, and index price/candle fetching.
"""
import asyncio
import functools
from datetime import datetime, date, timedelta
from typing import List, Dict, Optional, Tuple
from app.core.logging import logger
from app.services.zerodha_service import zerodha_service


class OptionsService:
    # Class-level instrument cache (refreshed daily)
    _instruments_cache: Optional[List[Dict]] = None
    _instruments_cache_date: Optional[date] = None

    # Zerodha lot sizes (as of 2024 — verify periodically)
    LOT_SIZES = {
        "NIFTY": 75,
        "BANKNIFTY": 30,
    }

    # NSE quote symbols for live index price
    INDEX_QUOTE_SYMBOLS = {
        "NIFTY": "NSE:NIFTY 50",
        "BANKNIFTY": "NSE:NIFTY BANK",
    }

    def get_lot_size(self, index: str) -> int:
        return self.LOT_SIZES.get(index.upper(), 75)

    # ── Instrument helpers ───────────────────────────────────────────────────

    def _get_instruments(self, api_key: str, access_token: str) -> List[Dict]:
        """
        Return cached NFO instrument list. Refreshes once per calendar day.
        The list contains ~50k rows — cache is critical for performance.
        """
        today = date.today()
        if self._instruments_cache and self._instruments_cache_date == today:
            logger.debug("[OptionsService] Using cached NFO instruments")
            return self._instruments_cache

        logger.info("[OptionsService] Fetching fresh NFO instruments from Zerodha")
        zerodha_service.set_credentials(api_key, access_token)
        instruments = zerodha_service.kite.instruments("NFO")
        OptionsService._instruments_cache = instruments
        OptionsService._instruments_cache_date = today
        logger.info(f"[OptionsService] Cached {len(instruments)} NFO instruments")
        return instruments

    def get_available_expiries(
        self, index: str, api_key: str, access_token: str
    ) -> List[date]:
        """Return sorted list of future expiry dates for the given index."""
        instruments = self._get_instruments(api_key, access_token)
        index_name = index.upper()
        today = date.today()

        expiries = set()
        for inst in instruments:
            if (
                inst.get("name", "").upper() == index_name
                and inst.get("instrument_type") in ("CE", "PE")
            ):
                exp = inst.get("expiry")
                if exp and exp >= today:
                    expiries.add(exp)

        sorted_expiries = sorted(expiries)
        logger.info(
            f"[OptionsService] {index} available expiries: "
            f"{[str(e) for e in sorted_expiries[:5]]}..."
        )
        return sorted_expiries

    def get_strikes_for_expiry(
        self,
        index: str,
        expiry: date,
        api_key: str,
        access_token: str,
    ) -> Dict:
        """
        Return all CE and PE contracts for a given index + expiry.
        Groups by strike price: { strike: {CE: inst, PE: inst} }
        """
        instruments = self._get_instruments(api_key, access_token)
        index_name = index.upper()
        result: Dict[float, Dict] = {}

        for inst in instruments:
            if (
                inst.get("name", "").upper() == index_name
                and inst.get("expiry") == expiry
                and inst.get("instrument_type") in ("CE", "PE")
            ):
                strike = inst["strike"]
                opt_type = inst["instrument_type"]
                if strike not in result:
                    result[strike] = {}
                result[strike][opt_type] = inst

        return result

    def select_atm_strike(
        self,
        index: str,
        expiry: date,
        current_price: float,
        api_key: str,
        access_token: str,
        otm_offset: int = 0,
    ) -> Optional[Dict]:
        """
        Find the ATM (or slightly OTM) strike for the given index and expiry.

        otm_offset=0  → ATM strike (closest to current price)
        otm_offset=1  → 1 strike OTM (slightly cheaper premium, better R:R)

        Returns:
          {
            atm_strike: float,
            ce: instrument_dict,
            pe: instrument_dict,
            all_strikes: [float, ...],
          }
        """
        strikes_map = self.get_strikes_for_expiry(index, expiry, api_key, access_token)
        if not strikes_map:
            logger.error(
                f"[OptionsService] No contracts found for {index} expiry={expiry}"
            )
            return None

        strikes = sorted(strikes_map.keys())

        # Find nearest strike to current index price
        atm_idx = min(range(len(strikes)), key=lambda i: abs(strikes[i] - current_price))

        # Apply OTM offset if requested (move away from current price by offset steps)
        selected_idx = min(atm_idx + otm_offset, len(strikes) - 1)
        selected_strike = strikes[selected_idx]

        contracts = strikes_map.get(selected_strike, {})
        ce = contracts.get("CE")
        pe = contracts.get("PE")

        if not ce or not pe:
            logger.warning(
                f"[OptionsService] Missing CE or PE at strike {selected_strike} for {index} {expiry}"
            )
            return None

        logger.info(
            f"[OptionsService] ATM strike selected: {selected_strike} "
            f"(index={current_price:.2f}, expiry={expiry})"
        )
        return {
            "atm_strike": selected_strike,
            "ce": ce,
            "pe": pe,
            "all_strikes": strikes,
        }

    # ── Live data ────────────────────────────────────────────────────────────

    def get_index_price(self, index: str, api_key: str, access_token: str) -> float:
        """Fetch live index price via Zerodha quote."""
        zerodha_service.set_credentials(api_key, access_token)
        symbol = self.INDEX_QUOTE_SYMBOLS[index.upper()]
        quotes = zerodha_service.kite.quote([symbol])
        price = quotes[symbol]["last_price"]
        logger.info(f"[OptionsService] {index} live price: {price:.2f}")
        return price

    def get_option_premium(
        self, instrument_token: int, api_key: str, access_token: str
    ) -> float:
        """Fetch live LTP for an option contract by instrument_token."""
        zerodha_service.set_credentials(api_key, access_token)
        quotes = zerodha_service.kite.quote([f"NFO:{instrument_token}"])
        # kite.quote with token returns key as "NFO:token"
        key = list(quotes.keys())[0]
        return quotes[key]["last_price"]

    async def get_index_candles(
        self,
        index: str,
        api_key: str,
        access_token: str,
        interval: str = "5minute",
    ) -> List[Dict]:
        """
        Fetch intraday candles for the index (from market open to now).
        Returns list of dicts with keys: date, open, high, low, close, volume.
        """
        zerodha_service.set_credentials(api_key, access_token)
        symbol = self.INDEX_QUOTE_SYMBOLS[index.upper()]

        # Get instrument_token for the index via quote
        quotes = zerodha_service.kite.quote([symbol])
        instrument_token = quotes[symbol]["instrument_token"]

        now = datetime.now()
        from_dt = now.replace(hour=9, minute=15, second=0, microsecond=0)
        to_dt = now

        loop = asyncio.get_event_loop()
        try:
            candles = await loop.run_in_executor(
                None,
                functools.partial(
                    zerodha_service.kite.historical_data,
                    instrument_token,
                    from_dt,
                    to_dt,
                    interval,
                    continuous=False,
                    oi=False,
                ),
            )
            logger.info(
                f"[OptionsService] Fetched {len(candles)} {interval} candles for {index}"
            )
            return candles
        except Exception as e:
            logger.error(f"[OptionsService] Failed to fetch {index} candles: {e}")
            return []


options_service = OptionsService()
