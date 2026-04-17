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
        direction: str = "CE",
    ) -> Optional[Dict]:
        """
        Find the ATM (or slightly OTM) strike for the given index and expiry.

        otm_offset=0  → ATM strike (closest to current price)
        otm_offset=1  → 1 strike OTM for the given direction:
                         CE (bullish): higher strike → OTM call
                         PE (bearish): lower strike  → OTM put

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

        # Apply OTM offset in the correct direction:
        # CE OTM = higher strike (increment index), PE OTM = lower strike (decrement index)
        if otm_offset > 0:
            if direction.upper() == "PE":
                selected_idx = max(atm_idx - otm_offset, 0)
            else:
                selected_idx = min(atm_idx + otm_offset, len(strikes) - 1)
        else:
            selected_idx = atm_idx
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
        """
        Get current index price using Kite paid API.

        Tries in order:
          1. kite.quote() — primary, paid plan + INDICES segment enabled in app
          2. kite.ltp()   — lighter endpoint, same permissions
          3. historical_data() on hardcoded token — always works on paid plan
          4. Put-call parity from NFO instruments — zero extra permissions
        """
        zerodha_service.set_credentials(api_key, access_token)
        index_upper = index.upper()
        symbol = self.INDEX_QUOTE_SYMBOLS[index_upper]

        # ── Attempt 1: kite.quote() ──────────────────────────────────────
        try:
            quotes = zerodha_service.kite.quote([symbol])
            price = float(quotes[symbol]["last_price"])
            logger.info(f"[OptionsService] {index} price via quote(): {price:.2f}")
            return price
        except Exception as e:
            logger.warning(f"[OptionsService] quote() failed for {index}: {e}")

        # ── Attempt 2: kite.ltp() ────────────────────────────────────────
        try:
            ltp_data = zerodha_service.kite.ltp([symbol])
            price = float(ltp_data[symbol]["last_price"])
            logger.info(f"[OptionsService] {index} price via ltp(): {price:.2f}")
            return price
        except Exception as e:
            logger.warning(f"[OptionsService] ltp() also failed for {index}: {e}")

        # ── Attempt 3: historical_data on hardcoded token ────────────────
        token = self.INDEX_TOKENS.get(index_upper)
        if token:
            try:
                now = datetime.now()
                candles = zerodha_service.kite.historical_data(
                    token, now - timedelta(minutes=5), now, "minute",
                    continuous=False, oi=False
                )
                if candles:
                    price = float(candles[-1]["close"])
                    logger.info(
                        f"[OptionsService] {index} price via historical_data(): {price:.2f}"
                    )
                    return price
            except Exception as e:
                logger.warning(f"[OptionsService] historical_data() failed for {index}: {e}")

        # ── Attempt 4: Put-call parity ────────────────────────────────────
        logger.warning(f"[OptionsService] All live price methods failed — using put-call parity")
        return self._index_price_from_parity(index_upper, api_key, access_token)

    def _index_price_from_parity(
        self, index: str, api_key: str, access_token: str
    ) -> float:
        """
        Estimate index price using put-call parity on the nearest expiry.

        For each strike where both CE and PE exist:
          synthetic_price = strike + CE_last_price − PE_last_price

        Average across up to 7 near-ATM strikes.
        Accuracy: typically within ±5 points of actual index.
        """
        instruments = self._get_instruments(api_key, access_token)
        today = date.today()

        # Find nearest expiry
        expiries = sorted(set(
            inst["expiry"] for inst in instruments
            if inst.get("name", "").upper() == index
            and inst.get("instrument_type") in ("CE", "PE")
            and inst.get("expiry") and inst["expiry"] >= today
        ))
        if not expiries:
            raise RuntimeError(f"No upcoming expiries found for {index} in NFO instruments")

        nearest_expiry = expiries[0]
        strikes_map: Dict[float, Dict] = {}

        for inst in instruments:
            if (
                inst.get("name", "").upper() == index
                and inst.get("expiry") == nearest_expiry
                and inst.get("instrument_type") in ("CE", "PE")
                and inst.get("last_price", 0) > 0
            ):
                strike = inst["strike"]
                opt_type = inst["instrument_type"]
                if strike not in strikes_map:
                    strikes_map[strike] = {}
                strikes_map[strike][opt_type] = inst["last_price"]

        # Only use strikes with both CE and PE prices
        valid = {
            strike: prices
            for strike, prices in strikes_map.items()
            if "CE" in prices and "PE" in prices
        }

        if not valid:
            raise RuntimeError(
                f"Could not derive {index} price from parity — "
                "no strikes with both CE and PE last prices"
            )

        # Initial estimate: median strike
        strikes_sorted = sorted(valid.keys())
        mid_idx = len(strikes_sorted) // 2
        initial_estimate = strikes_sorted[mid_idx]

        # Find 7 strikes nearest to initial_estimate
        nearest = sorted(
            strikes_sorted,
            key=lambda s: abs(s - initial_estimate),
        )[:7]

        # Compute synthetic prices and average
        synthetic_prices = [
            s + valid[s]["CE"] - valid[s]["PE"]
            for s in nearest
        ]
        avg_price = sum(synthetic_prices) / len(synthetic_prices)

        logger.info(
            f"[OptionsService] {index} price via put-call parity "
            f"(expiry={nearest_expiry}, n={len(nearest)}): {avg_price:.2f}"
        )
        return round(avg_price, 2)

    def get_option_premium(
        self, trading_symbol: str, api_key: str, access_token: str
    ) -> float:
        """
        Fetch live LTP for an option contract.
        trading_symbol should be the Zerodha tradingsymbol (e.g. "NIFTY26APR22350CE").
        Tries ltp() first, falls back to quote().
        """
        zerodha_service.set_credentials(api_key, access_token)
        nfo_key = f"NFO:{trading_symbol}"

        # ── Attempt 1: ltp() ────────────────────────────────────────────
        try:
            ltp_data = zerodha_service.kite.ltp([nfo_key])
            key = list(ltp_data.keys())[0]
            return ltp_data[key]["last_price"]
        except Exception as e:
            logger.warning(f"[OptionsService] ltp() failed for {nfo_key}: {e} — trying quote()")

        # ── Attempt 2: quote() ───────────────────────────────────────────
        quotes = zerodha_service.kite.quote([nfo_key])
        key = list(quotes.keys())[0]
        return quotes[key]["last_price"]

    # Hardcoded Zerodha instrument tokens for NSE indices (stable, never change)
    INDEX_TOKENS = {
        "NIFTY": 256265,     # NSE:NIFTY 50
        "BANKNIFTY": 260105, # NSE:NIFTY BANK
    }

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

        Uses hardcoded instrument tokens — avoids needing kite.quote() permission
        for NSE index symbols (which requires Marketdata scope on some plans).
        """
        zerodha_service.set_credentials(api_key, access_token)
        index_upper = index.upper()

        # Use hardcoded token first; fall back to ltp() / quote() if somehow not in map
        instrument_token = self.INDEX_TOKENS.get(index_upper)
        if instrument_token is None:
            symbol = self.INDEX_QUOTE_SYMBOLS[index_upper]
            try:
                ltp_data = zerodha_service.kite.ltp([symbol])
                key = list(ltp_data.keys())[0]
                instrument_token = ltp_data[key]["instrument_token"]
            except Exception:
                quotes = zerodha_service.kite.quote([symbol])
                instrument_token = quotes[symbol]["instrument_token"]

        logger.info(
            f"[OptionsService] Fetching {interval} candles for {index_upper} "
            f"(token={instrument_token})"
        )

        # Always use IST — server may run in UTC so datetime.now() would give wrong
        # market-hours comparison if we don't force the timezone.
        import pytz
        IST = pytz.timezone("Asia/Kolkata")
        now_ist = datetime.now(IST).replace(tzinfo=None)  # naive IST datetime

        market_open  = now_ist.replace(hour=9,  minute=15, second=0, microsecond=0)
        market_close = now_ist.replace(hour=15, minute=30, second=0, microsecond=0)
        is_weekend   = now_ist.weekday() >= 5  # Sat=5, Sun=6

        if not is_weekend and market_open <= now_ist <= market_close:
            # Market is live — fetch from today's open to now
            from_dt = market_open
            to_dt   = now_ist
        else:
            # Market is closed (weekend or outside hours) — find the last trading day
            # Walk back day by day until we land on Mon–Fri
            last_trading = now_ist - timedelta(days=1)
            while last_trading.weekday() >= 5:   # skip Sat / Sun
                last_trading -= timedelta(days=1)

            from_dt = last_trading.replace(hour=9,  minute=15, second=0, microsecond=0)
            to_dt   = last_trading.replace(hour=15, minute=30, second=0, microsecond=0)

        logger.info(
            f"[OptionsService] Candle window: {from_dt.strftime('%Y-%m-%d %H:%M')} → "
            f"{to_dt.strftime('%Y-%m-%d %H:%M')} IST"
        )

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
        except Exception as e:
            logger.error(f"[OptionsService] Failed to fetch {index} candles: {e}")
            return []

        if not candles:
            return []

        # ── Inject live LTP into the last (possibly in-progress) candle ──────
        # Zerodha's historical API may return the last candle's close slightly
        # behind the actual market price (cache lag + in-progress candle delay).
        # Fetching kite.ltp() directly gives us the exact current tick and
        # ensures all indicators (VWAP, RSI, EMA, breakout close) use the
        # most recent price rather than data that can be 3–8 min stale.
        try:
            live_price = await loop.run_in_executor(
                None,
                lambda: self.get_index_price(index_upper, api_key, access_token),
            )
            if live_price > 0:
                last_c = dict(candles[-1])  # make a mutable copy
                hist_close = float(last_c.get("close", live_price))
                last_c["close"] = live_price
                last_c["high"]  = max(float(last_c.get("high",  live_price)), live_price)
                last_c["low"]   = min(float(last_c.get("low",   live_price)), live_price)
                candles = list(candles[:-1]) + [last_c]
                logger.info(
                    f"[OptionsService] {index} last candle close updated: "
                    f"hist={hist_close:.2f} → live={live_price:.2f}"
                )
        except Exception as e:
            logger.debug(f"[OptionsService] Live LTP injection failed (using hist close): {e}")

        return candles


    async def get_prev_day_ohlc(
        self,
        index: str,
        api_key: str,
        access_token: str,
    ) -> dict:
        """
        Fetch previous trading day's OHLC for the given index.
        Returns {"high": float, "low": float, "open": float, "close": float}
        or {"high": 0.0, "low": 0.0, ...} on failure (caller treats 0 as unavailable).
        """
        zero = {"high": 0.0, "low": 0.0, "open": 0.0, "close": 0.0}
        try:
            zerodha_service.set_credentials(api_key, access_token)
            index_upper      = index.upper()
            instrument_token = self.INDEX_TOKENS.get(index_upper)
            if not instrument_token:
                return zero

            import pytz
            IST = pytz.timezone("Asia/Kolkata")
            today   = datetime.now(IST).replace(tzinfo=None).date()

            # Walk back to find previous weekday
            prev_day = today - timedelta(days=1)
            while prev_day.weekday() >= 5:      # skip Sat/Sun
                prev_day -= timedelta(days=1)

            from_dt = datetime.combine(prev_day, datetime.min.time()).replace(hour=9, minute=15)
            to_dt   = datetime.combine(prev_day, datetime.min.time()).replace(hour=15, minute=30)

            loop = asyncio.get_event_loop()
            candles = await loop.run_in_executor(
                None,
                functools.partial(
                    zerodha_service.kite.historical_data,
                    instrument_token,
                    from_dt,
                    to_dt,
                    "day",
                    continuous=False,
                    oi=False,
                ),
            )
            if candles:
                c = candles[-1]  # last (most recent) daily candle
                result = {
                    "high":  float(c.get("high",  0)),
                    "low":   float(c.get("low",   0)),
                    "open":  float(c.get("open",  0)),
                    "close": float(c.get("close", 0)),
                }
                logger.info(
                    f"[OptionsService] {index} prev-day OHLC: "
                    f"H={result['high']:.2f} L={result['low']:.2f}"
                )
                return result
        except Exception as e:
            logger.warning(f"[OptionsService] prev-day OHLC fetch failed for {index}: {e}")
        return zero

    async def get_fut_volume_ratio(
        self,
        index: str,
        api_key: str,
        access_token: str,
    ) -> float:
        """
        Find the near-month futures contract for the index, fetch today's 5-min candles,
        and return last_candle_volume / avg_volume_of_last_10_candles.
        Returns 0.0 on any failure so the engine skips the check gracefully.
        """
        try:
            zerodha_service.set_credentials(api_key, access_token)
            loop = asyncio.get_event_loop()

            instruments = await loop.run_in_executor(
                None,
                lambda: self._get_instruments(api_key, access_token),
            )
            today = date.today()
            index_upper = index.upper()
            fut_instruments = [
                i for i in instruments
                if i.get("name") == index_upper
                and i.get("instrument_type") == "FUT"
                and i.get("expiry") and i["expiry"] >= today
            ]
            if not fut_instruments:
                logger.warning(f"[OptionsService] No futures found for {index}")
                return 0.0

            fut_instruments.sort(key=lambda x: x["expiry"])
            near_fut = fut_instruments[0]
            token = near_fut["instrument_token"]
            logger.info(
                f"[OptionsService] {index} FUT: {near_fut.get('tradingsymbol')} "
                f"expiry={near_fut['expiry']}"
            )

            import pytz
            IST = pytz.timezone("Asia/Kolkata")
            now_ist = datetime.now(IST).replace(tzinfo=None)
            market_open = now_ist.replace(hour=9, minute=15, second=0, microsecond=0)

            candles = await loop.run_in_executor(
                None,
                functools.partial(
                    zerodha_service.kite.historical_data,
                    token,
                    market_open,
                    now_ist,
                    "5minute",
                    continuous=False,
                    oi=False,
                ),
            )
            if len(candles) < 3:
                return 0.0

            volumes = [float(c.get("volume", 0) or 0) for c in candles]
            last_vol = volumes[-1]
            lookback = volumes[max(0, len(volumes) - 11): len(volumes) - 1]
            avg_vol = sum(lookback) / len(lookback) if lookback else 0.0
            if avg_vol <= 0:
                return 0.0

            ratio = round(last_vol / avg_vol, 2)
            logger.info(
                f"[OptionsService] {index} FUT vol ratio: {ratio:.2f}× "
                f"(last={last_vol:.0f} avg={avg_vol:.0f})"
            )
            return ratio

        except Exception as e:
            logger.warning(f"[OptionsService] get_fut_volume_ratio failed for {index}: {e}")
            return 0.0

    def get_index_candles_sync(
        self,
        index: str,
        api_key: str,
        access_token: str,
        limit_minutes: int = 20,
    ) -> List[Dict]:
        """
        Synchronous fetch of the last N minutes of 5-min index candles.
        Called via loop.run_in_executor in the monitoring agent for structure trailing SL.
        """
        try:
            zerodha_service.set_credentials(api_key, access_token)
            import pytz
            IST = pytz.timezone("Asia/Kolkata")
            now_ist = datetime.now(IST).replace(tzinfo=None)
            from_dt = now_ist - timedelta(minutes=limit_minutes)
            token = self.INDEX_TOKENS.get(index.upper())
            if not token:
                return []
            return zerodha_service.kite.historical_data(
                token, from_dt, now_ist, "5minute", continuous=False, oi=False
            )
        except Exception as e:
            logger.warning(f"[OptionsService] get_index_candles_sync failed for {index}: {e}")
            return []


options_service = OptionsService()
