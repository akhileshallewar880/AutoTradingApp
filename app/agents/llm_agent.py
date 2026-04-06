from openai import AsyncOpenAI
from app.core.config import get_settings
from app.core.logging import logger
from typing import Dict, List, Optional
import json
import math

settings = get_settings()


class LLMAgent:
    """
    LLM-powered stock picker.

    Intraday mode  (hold_duration_days=0):
      Analyses Nifty 50 + Next 50 stocks using VWAP, Bollinger Bands, RSI, MACD,
      Stochastic, and Pivot Points. Supports both BUY (long) and SELL (short).

    Swing / delivery mode (hold_duration_days > 0):
      Analyses full NSE market using standard daily indicators.

    Model routing (based on env OPENAI_MODEL or auto-select):
      Intraday → gpt-4o          (fast JSON mode, low latency)
      Swing    → gpt-4o / o1 / o3-mini (complex multi-day reasoning)
    """

    # Accuracy-boosting lessons learned from historical tradebook losses
    TRADEBOOK_LESSONS = """
## Lessons From Historical Losses (MANDATORY — apply to every pick)
1. AVOID stocks with a gap-down > 3% from previous close (they keep falling) — do NOT trade IEX-style drops
2. AVOID stocks outside the price band ₹10–₹15,000 (illiquid extremes)
3. PREFER stocks where day_change_pct is between -1.5% and +4% (not in extreme moves)
4. PREFER stocks near their VWAP (within 0.5%) for mean-reversion plays — best R:R
5. DO NOT enter a BUY when RSI > 75 (overbought — likely reversal coming)
6. DO NOT enter a SELL when RSI < 25 (oversold — likely snap-back coming)
7. ALWAYS set stop_loss within 1× ATR of entry (never wider) — wider stops = more losers
8. Minimum Risk:Reward = 1:2.0 required for ANY trade (was causing losses at 1:1.5)
9. For SHORT positions: only short with at least 2 confirming bearish signals (VWAP below + MACD negative + RSI falling)
10. Time of day: Avoid new entries after 2:45 PM IST — insufficient time to reach target
"""

    def __init__(self):
        self.client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
        # Route model: intraday uses fast gpt-4o, swing can use reasoning models
        self._configured_model = getattr(settings, "OPENAI_MODEL", "gpt-4o")

    def _get_model_for_mode(self, hold_duration_days: int) -> str:
        """
        Route to the best model based on trading mode.
        Intraday: needs speed + JSON → gpt-4o
        Swing:    needs reasoning  → o1 / o3-mini / gpt-4o depending on config
        """
        model = self._configured_model
        # Never use a slow reasoning model for intraday (latency kills execution)
        if hold_duration_days == 0 and model.startswith("o"):
            logger.info(f"Overriding {model} → gpt-4o for intraday (reasoning models too slow)")
            return "gpt-4o"
        return model

    async def analyze_opportunities(
        self,
        market_data: List[Dict],
        available_balance: float,
        risk_percent: float,
        hold_duration_days: int = 0,
        sectors: Optional[List[str]] = None,
        num_stocks: int = 5,
        user_id: Optional[int] = None,
        analysis_id: Optional[str] = None,
    ) -> Dict:
        logger.info(
            f"LLM analyzing {len(market_data)} candidates "
            f"(hold={hold_duration_days}d, sectors={sectors})"
        )

        hold_label = self._hold_label(hold_duration_days)
        sector_context = (
            f"Focus on sectors: {', '.join(sectors)}"
            if sectors and sectors != ["ALL"]
            else "Search across the entire NSE market (all sectors)"
        )

        model = self._get_model_for_mode(hold_duration_days)
        is_reasoning_model = model.startswith("o")

        if hold_duration_days == 0:
            system_prompt = self._build_intraday_system_prompt(
                num_stocks, hold_label, sector_context
            )
            hold_instruction = self._build_intraday_user_instruction(num_stocks)
        elif hold_duration_days <= 7:
            system_prompt = self._build_swing_system_prompt(
                num_stocks, hold_label, sector_context, short_term=True
            )
            hold_instruction = (
                f"Pick the {num_stocks} best opportunities for maximum profit in {hold_label}. "
                f"Prioritise stocks with volume surges, strong momentum, and clear technical setups."
            )
        else:
            system_prompt = self._build_swing_system_prompt(
                num_stocks, hold_label, sector_context, short_term=False
            )
            hold_instruction = (
                f"Pick the {num_stocks} best opportunities for maximum profit in {hold_label}. "
                f"Prioritise trend strength, RSI 55–68, and institutional volume."
            )

        user_content = f"""
Available Balance: ₹{available_balance:,.2f}
Risk Per Trade: {risk_percent}%
Hold Duration: {hold_label}
Stocks Requested: {num_stocks}

Pre-Screened Market Data (sorted by composite_score descending — best signals first):
{json.dumps(market_data, default=str, indent=2)}

{hold_instruction}
"""

        call_kwargs = {
            "model": model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_content},
            ],
            "response_format": {"type": "json_object"},
            "max_completion_tokens": 8000,   # increased from 4000 → gives model room to reason
        }
        if not is_reasoning_model:
            call_kwargs["temperature"] = 0.1   # lowered from 0.2 → more deterministic, consistent

        try:
            response = await self.client.chat.completions.create(**call_kwargs)

            content = response.choices[0].message.content
            logger.info(f"LLM analysis complete (model={model})")
            logger.debug(f"LLM response: {content[:500]}…")

            if response.usage:
                logger.info(
                    f"Token usage: {response.usage.total_tokens} total "
                    f"({response.usage.prompt_tokens} prompt, {response.usage.completion_tokens} completion)"
                )

            data = json.loads(content)

            # ── Post-processing: validate, fix, and guarantee trades ──────────
            data = self._validate_and_fix_trades(data, market_data, hold_duration_days)

            return data

        except Exception as e:
            logger.error(f"LLM analysis failed ({type(e).__name__}): {e}")
            # Emergency fallback: generate basic trades from pre-screened data
            return self._emergency_trade_fallback(market_data, num_stocks, hold_duration_days)

    # ── Post-Processing Validator ─────────────────────────────────────────────

    def _validate_and_fix_trades(
        self,
        data: Dict,
        market_data: List[Dict],
        hold_duration_days: int,
    ) -> Dict:
        """
        After LLM response:
        1. Enforce price ordering (stop < entry < target for BUY; target < entry < stop for SELL)
        2. Fix trades where R:R < 1.5 by recalculating target
        3. Remove trades where confidence_score < 0.60
        4. If 0 trades remain → force-generate from top pre-screened stocks
        """
        stocks = data.get("stocks", [])
        valid = []

        for s in stocks:
            action = s.get("action", "BUY").upper()
            entry = float(s.get("entry_price", 0) or 0)
            stop = float(s.get("stop_loss", 0) or 0)
            target = float(s.get("target_price", 0) or 0)
            confidence = float(s.get("confidence_score", 0) or 0)

            if entry <= 0:
                logger.warning(f"Rejecting trade {s.get('stock_symbol')} — zero entry price")
                continue

            if confidence < 0.60:
                logger.warning(
                    f"Rejecting {s.get('stock_symbol')} — low confidence {confidence:.2f} < 0.60"
                )
                continue

            # Fix price ordering
            if action == "BUY":
                if stop >= entry:
                    # Stop is wrong — set to entry − 1× ATR (fallback 1.5%)
                    stop = round(entry * 0.985, 2)
                    s["stop_loss"] = stop
                    logger.info(f"Fixed stop_loss for BUY {s.get('stock_symbol')}: {stop}")
                if target <= entry:
                    # Target is wrong — set to entry + 2× risk
                    risk = entry - stop
                    target = round(entry + 2.0 * risk, 2)
                    s["target_price"] = target
                    logger.info(f"Fixed target for BUY {s.get('stock_symbol')}: {target}")

            elif action == "SELL":
                if stop <= entry:
                    stop = round(entry * 1.015, 2)
                    s["stop_loss"] = stop
                    logger.info(f"Fixed stop_loss for SELL {s.get('stock_symbol')}: {stop}")
                if target >= entry:
                    risk = stop - entry
                    target = round(entry - 2.0 * risk, 2)
                    s["target_price"] = target
                    logger.info(f"Fixed target for SELL {s.get('stock_symbol')}: {target}")

            # Enforce minimum R:R ≥ 1.5
            if action == "BUY":
                risk = entry - stop
                reward = target - entry
            else:
                risk = stop - entry
                reward = entry - target

            if risk > 0:
                rr = reward / risk
                if rr < 1.5:
                    # Extend target to achieve 2× R:R
                    if action == "BUY":
                        target = round(entry + 2.0 * risk, 2)
                    else:
                        target = round(entry - 2.0 * risk, 2)
                    s["target_price"] = target
                    logger.info(
                        f"Extended target for {s.get('stock_symbol')} to achieve 2× R:R "
                        f"(was {rr:.2f}): new target={target}"
                    )

            valid.append(s)

        # ── If LLM returned 0 valid trades, force-generate from pre-screened data ──
        if len(valid) == 0 and market_data:
            logger.warning(
                "LLM returned 0 valid trades — running emergency trade generation "
                "from top pre-screened stocks"
            )
            valid = self._force_generate_trades(market_data, hold_duration_days)

        data["stocks"] = valid
        logger.info(f"Post-validation: {len(valid)} trades ready for execution")
        return data

    def _force_generate_trades(
        self, market_data: List[Dict], hold_duration_days: int
    ) -> List[Dict]:
        """
        Emergency fallback: generate trades directly from the strategy engine
        signal data embedded in market_data (when LLM returns nothing).
        Uses top-scored stocks with a concrete signal.
        """
        trades = []
        # Sort by composite_score or signal_strength descending
        sorted_data = sorted(
            market_data,
            key=lambda x: (x.get("signal_strength", 0), x.get("composite_score", 0)),
            reverse=True,
        )

        for stock in sorted_data[:5]:
            symbol = stock.get("symbol", "")
            signal = stock.get("intraday_signal", "BUY")
            if signal == "NEUTRAL":
                signal = "BUY"  # default to BUY if still NEUTRAL

            indicators = stock.get("indicators", {})
            entry = float(stock.get("last_price", 0) or 0)
            if entry <= 0:
                continue

            atr = float(indicators.get("atr", entry * 0.01) or entry * 0.01)
            r1 = float(indicators.get("r1", entry * 1.02) or entry * 1.02)
            s1 = float(indicators.get("s1", entry * 0.98) or entry * 0.98)

            if signal == "BUY":
                stop = round(max(entry - 1.0 * atr, entry * 0.985), 2)
                target = round(min(r1, entry + 2.0 * atr), 2)
                if target <= entry:
                    target = round(entry + 2.0 * atr, 2)
            else:
                stop = round(min(entry + 1.0 * atr, entry * 1.015), 2)
                target = round(max(s1, entry - 2.0 * atr), 2)
                if target >= entry:
                    target = round(entry - 2.0 * atr, 2)

            reasons = stock.get("signal_reasons", [f"Auto-generated: {signal} signal"])
            reasoning = "; ".join(reasons[:2]) if reasons else f"{signal} signal from technical indicators"

            trades.append({
                "stock_symbol": symbol,
                "company_name": stock.get("company_name", symbol),
                "action": signal,
                "entry_price": round(entry, 2),
                "stop_loss": stop,
                "target_price": target,
                "confidence_score": round(min(0.65 + stock.get("signal_strength", 1) * 0.05, 0.85), 2),
                "days_to_target": hold_duration_days,
                "reasoning": reasoning,
            })

        logger.info(f"Force-generated {len(trades)} trades from pre-screened data")
        return trades

    def _emergency_trade_fallback(
        self, market_data: List[Dict], num_stocks: int, hold_duration_days: int
    ) -> Dict:
        """Called when the LLM call itself fails entirely."""
        logger.warning("Using emergency trade fallback (LLM call failed)")
        trades = self._force_generate_trades(market_data, hold_duration_days)
        return {"stocks": trades[:num_stocks]}

    # ── Intraday prompt ───────────────────────────────────────────────────────

    def _build_intraday_system_prompt(
        self, num_stocks: int, hold_label: str, sector_context: str
    ) -> str:
        return f"""You are an elite AI intraday trading analyst for the Indian NSE market.
Your SOLE OBJECTIVE: identify NSE stocks with the highest probability of reaching their
price target WITHIN THE SAME TRADING DAY (MIS product — must exit by 3:15 PM IST).

{sector_context}
Hold Duration: {hold_label}

## CRITICAL MANDATE — ALWAYS GENERATE TRADES
You MUST return EXACTLY {num_stocks} trade recommendations. The Indian stock market has
thousands of instruments — there are ALWAYS tradeable setups when the market is open.
"Insufficient quality" is NOT an acceptable reason to return fewer than {num_stocks} stocks.
If top-quality signals are scarce, pick the best available candidates and note lower confidence.

## Supported Actions
- BUY  : Long position — buy now, sell higher (profit when price rises)
- SELL : Short sell   — sell now, cover lower (profit when price falls) — MIS intraday shorting allowed

## CRITICAL Price Ordering Rules (violations → trade rejection by validator)
For BUY  :  stop_loss  < entry_price < target_price   ← ALWAYS
For SELL :  target_price < entry_price < stop_loss    ← ALWAYS
             (stop_loss is ABOVE entry for shorts)
             (target_price is BELOW entry for shorts)

## Entry Price
- entry_price = current last_price (market order at this price)

## Stop Loss — TIGHTER than before
- BUY  : stop_loss = entry − 1.0 × ATR (max 1.5 × ATR; keep tight)
- SELL : stop_loss = entry + 1.0 × ATR (max 1.5 × ATR)
- Tight stops = better R:R and fewer large losses

## Target Price — Minimum 2× Risk Required
- BUY  : target = entry + min(R1 pivot, 2.5 × ATR)
- SELL : target = entry − min(S1 pivot, 2.5 × ATR)
- Minimum R:R = 1:2.0 MANDATORY (was 1:1.5 — this was causing losses in historical data)
- Prefer 1:2.5 or better

## 5 Indicator Combos (ranked by reliability)

### Combo 1 — VWAP + RSI  (Institutional Level — MOST RELIABLE)
BUY  : price_vs_vwap = "ABOVE"  AND  RSI 45–75 (momentum zone)
SELL : price_vs_vwap = "BELOW"  AND  RSI 25–55 (bearish momentum)

### Combo 2 — MACD Crossover / Histogram (Momentum Trigger)
BUY  : macd_bullish_crossover = true  (immediate entry signal — highest conviction)
       OR  macd_histogram > 0  AND  RSI 40–75
SELL : macd_bearish_crossover = true
       OR  macd_histogram < 0  AND  RSI 25–60

### Combo 3 — Bollinger Bands + RSI  (Volatility & Mean Reversion)
BUY  : bb_position = "NEAR_LOWER"  AND  RSI < 45  (mean-reversion long)
       OR  bb_position = "MIDDLE"  AND  macd_histogram > 0  (momentum breakout)
SELL : bb_position = "NEAR_UPPER"  AND  RSI > 55

### Combo 4 — EMA Alignment (Trend Confirmation)
BUY  : last_price > ema_9 > ema_21  (bullish trend)
SELL : last_price < ema_9 < ema_21  (bearish trend)

### Combo 5 — Stochastic  (Oscillator Confirmation)
BUY  : stoch_k < 30  AND  stoch_k > stoch_d  (oversold + recovering)
       OR  stoch_signal = "OVERSOLD"
SELL : stoch_k > 70  AND  stoch_k < stoch_d  (overbought + falling)
       OR  stoch_signal = "OVERBOUGHT"

## Selection Rules (relaxed to ensure trades are always generated)
1. Prefer signal_strength ≥ 2 — but signal_strength = 1 with high composite_score is acceptable
2. volume_ratio ≥ 1.2 preferred (≥ 1.0 acceptable if all other signals align strongly)
3. ATR must be ≥ 0.3% of price
4. days_to_target MUST be 0 for all intraday picks
5. Confidence score: aim for ≥ 0.65; minimum accepted 0.60
6. Time filter: do NOT enter new positions after 2:45 PM IST

{self.TRADEBOOK_LESSONS}

## Output Format
Return ONLY valid JSON in this exact structure:
{{
    "stocks": [
        {{
            "stock_symbol": "SYMBOL",
            "company_name": "Full Company Name",
            "action": "BUY",
            "entry_price": 100.00,
            "stop_loss": 99.00,
            "target_price": 102.00,
            "confidence_score": 0.82,
            "days_to_target": 0,
            "reasoning": "2–3 sentences: which combos triggered, VWAP position, key levels used, R:R achieved."
        }},
        {{
            "stock_symbol": "SYMBOL2",
            "company_name": "Full Company Name",
            "action": "SELL",
            "entry_price": 200.00,
            "stop_loss": 203.00,
            "target_price": 194.00,
            "confidence_score": 0.78,
            "days_to_target": 0,
            "reasoning": "2–3 sentences: bearish combos triggered, VWAP below, stop above entry."
        }}
    ]
}}

Select EXACTLY {num_stocks} stocks. DO NOT return fewer unless the market is completely closed
(in which case note that in the reasoning field and set confidence_score = 0.50).
"""

    def _build_intraday_user_instruction(self, num_stocks: int) -> str:
        return (
            f"INTRADAY MODE: Select EXACTLY {num_stocks} stocks (BUY or SELL/short). "
            f"Prefer signal_strength ≥ 2 but accept ≥ 1 if composite_score is high. "
            f"Use VWAP, MACD crossover/histogram, BB position, EMA alignment, and Stochastic "
            f"to find the strongest setups. Set stop_loss = 1× ATR, target = 2× ATR minimum. "
            f"Enforce strict price ordering: BUY → stop < entry < target; SELL → target < entry < stop. "
            f"Minimum R:R = 1:2.0. All days_to_target = 0. YOU MUST RETURN {num_stocks} TRADES."
        )

    # ── Swing / delivery prompt ───────────────────────────────────────────────

    def _build_swing_system_prompt(
        self,
        num_stocks: int,
        hold_label: str,
        sector_context: str,
        short_term: bool,
    ) -> str:
        if short_term:
            hold_section = """
## Short-Term Selection (1–7 days)
- Prioritise momentum + volume surge, RSI 58–70, MACD bullish crossover
- Volume ratio > 1.5× preferred
- Target achievable within the hold period
- days_to_target should match the hold duration"""
        else:
            hold_section = """
## Medium-Term Selection (8–30 days)
- Prioritise trend strength (STRONG_BULLISH), RSI 55–68
- Price near 52-week high signals momentum continuation
- Volume ratio > 1.3× to confirm institutional interest
- days_to_target should be realistic (not more than hold_duration_days)"""

        return f"""You are an elite AI trading analyst specialising in the Indian NSE stock market.

Your SOLE OBJECTIVE: identify stocks with the highest probability of maximum profit in {hold_label}.

{sector_context}

## CRITICAL MANDATE — ALWAYS GENERATE TRADES
You MUST return EXACTLY {num_stocks} trade recommendations. There are always opportunities
in the NSE market. Never return fewer than requested.

## General Selection Criteria (rank by importance)
1. Volume Surge — volume_ratio > 1.5× (institutional accumulation signal)
2. Momentum — strong 5-day price momentum, MACD histogram turning positive
3. RSI Sweet Spot — RSI between 55–72 (momentum zone, not overbought)
4. Trend Alignment — price above SMA20 and EMA21 (STRONG_BULLISH preferred)
5. Risk/Reward — minimum 1:2.0 R:R ratio; prefer 1:2.5 or better
6. Tight Stop — stop-loss within 1.0–1.5× ATR of entry

{hold_section}

## CRITICAL: Price Ordering Rules (violations cause trade rejection)
- stop_loss MUST be LESS than entry_price    (e.g. entry=100, stop_loss=98)
- target_price MUST be GREATER than entry_price  (e.g. entry=100, target=112)
For BUY trades: stop_loss < entry_price < target_price — ALWAYS.

{self.TRADEBOOK_LESSONS}

Return ONLY valid JSON:
{{
    "stocks": [
        {{
            "stock_symbol": "SYMBOL",
            "company_name": "Full Company Name",
            "action": "BUY",
            "entry_price": 100.00,
            "stop_loss": 98.00,
            "target_price": 114.00,
            "confidence_score": 0.85,
            "days_to_target": 3,
            "reasoning": "Concise 2-3 sentence explanation including R:R achieved."
        }}
    ]
}}

Select EXACTLY {num_stocks} stocks.
"""

    @staticmethod
    def _hold_label(days: int) -> str:
        if days == 0:
            return "Intraday (same day exit)"
        elif days == 1:
            return "1 Day"
        elif days == 3:
            return "3 Days"
        elif days == 7:
            return "1 Week"
        elif days == 14:
            return "2 Weeks"
        elif days == 30:
            return "1 Month"
        else:
            return f"{days} Days"


llm_agent = LLMAgent()
