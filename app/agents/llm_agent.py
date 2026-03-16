from openai import AsyncOpenAI
from app.core.config import get_settings
from app.core.logging import logger
from typing import Dict, List, Optional
import json

settings = get_settings()


class LLMAgent:
    """
    LLM-powered stock picker.

    Intraday mode  (hold_duration_days=0):
      Analyses Nifty 50 + Next 50 stocks using VWAP, Bollinger Bands, RSI, MACD,
      Stochastic, and Pivot Points. Supports both BUY (long) and SELL (short).

    Swing / delivery mode (hold_duration_days > 0):
      Analyses full NSE market using standard daily indicators.
    """

    def __init__(self):
        self.client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
        self.model = settings.OPENAI_MODEL

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

Pre-Screened Market Data (sorted by signal strength / composite score):
{json.dumps(market_data, default=str, indent=2)}

{hold_instruction}
"""

        # o-series reasoning models (o1, o3, o4) don't support custom temperature
        # and require max_completion_tokens instead of max_tokens.
        is_reasoning_model = self.model.startswith("o")

        call_kwargs = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_content},
            ],
            "response_format": {"type": "json_object"},
            "max_completion_tokens": 4000,
        }
        if not is_reasoning_model:
            call_kwargs["temperature"] = 0.2

        try:
            response = await self.client.chat.completions.create(**call_kwargs)

            content = response.choices[0].message.content
            logger.info("LLM analysis complete")
            logger.debug(f"LLM response: {content[:500]}…")

            if response.usage:
                logger.info(
                    f"Token usage: {response.usage.total_tokens} total "
                    f"({response.usage.prompt_tokens} prompt, {response.usage.completion_tokens} completion)"
                )

            data = json.loads(content)
            return data

        except Exception as e:
            logger.error(f"LLM analysis failed: {e}")
            return {"stocks": []}

    # ── Intraday prompt ───────────────────────────────────────────────────────

    def _build_intraday_system_prompt(
        self, num_stocks: int, hold_label: str, sector_context: str
    ) -> str:
        return f"""You are an elite AI intraday trading analyst for the Indian NSE market (2026).
Your SOLE OBJECTIVE: identify Nifty 50 / Nifty Next 50 stocks with the highest probability of
reaching their price target WITHIN THE SAME TRADING DAY (MIS product — must exit by 3:15 PM IST).

{sector_context}
Hold Duration: {hold_label}

## Supported Actions
- BUY  : Long position — buy now, sell higher (profit when price rises)
- SELL : Short sell   — sell now, cover lower (profit when price falls) — MIS allows intraday shorting

## CRITICAL Price Ordering Rules (violations → trade rejection)
For BUY  :  stop_loss  < entry_price < target_price   ← ALWAYS
For SELL :  target_price < entry_price < stop_loss    ← ALWAYS
             (stop_loss is ABOVE entry for shorts — limits your loss if price rises)
             (target_price is BELOW entry for shorts — profit when price falls)
Never swap or violate these orderings.

## Entry Price
- entry_price = current last_price (market order fills at this price)

## Stop Loss
- BUY  : stop_loss = entry − max(1.5 × ATR, distance to nearest S1 pivot)
- SELL : stop_loss = entry + max(1.5 × ATR, distance to nearest R1 pivot)
Minimum stop distance: 1× ATR

## Target Price
- BUY  : target = entry + min(R1 pivot level, 3 × ATR)   — prefer pivot resistance
- SELL : target = entry − min(S1 pivot level, 3 × ATR)   — prefer pivot support
Minimum R:R = 1:1.5 for intraday

## Top 3 Indicator Combinations (use AT LEAST 2 to confirm a signal)

### Combo 1 — VWAP + RSI  (Institutional Level)
BUY  : price_vs_vwap = "ABOVE"  AND  RSI 50–70 (momentum zone, not overbought)
SELL : price_vs_vwap = "BELOW"  AND  RSI 30–50 (bearish momentum, not oversold)

### Combo 2 — MACD + RSI  (Momentum & Strength)
BUY  : macd_histogram > 0 (bullish crossover)  AND  RSI 40–70
SELL : macd_histogram < 0 (bearish crossover)  AND  RSI 30–60

### Combo 3 — Bollinger Bands + RSI  (Volatility & Reversal)
BUY  : bb_position = "NEAR_LOWER"  AND  RSI < 40  (mean-reversion long)
SELL : bb_position = "NEAR_UPPER"  AND  RSI > 60  (mean-reversion short)

## Additional Confirmation (use any of these as supporting signals)
- Stochastic: stoch_signal = OVERSOLD → supports BUY; OVERBOUGHT → supports SELL
- EMA Alignment: price > EMA9 > EMA21 → bullish; price < EMA9 < EMA21 → bearish
- Pivot Levels: R1/R2 as targets for BUY; S1/S2 as targets for SELL
- Volume surge: volume_ratio ≥ 1.5 confirms any breakout

## Selection Rules
1. ONLY select stocks with signal_strength ≥ 2 (at least 2 combos agree)
2. volume_ratio ≥ 1.5 is mandatory — low volume breakouts are fakeouts
3. ATR must be ≥ 0.5% of price (stock must have enough intraday range)
4. days_to_target MUST be 0 for all intraday picks
5. Confidence score ≥ 0.70 for high-conviction setups
6. REJECT slow-moving, low-volatility, or low-volume stocks

## Output Format
Return ONLY valid JSON in this exact structure:
{{
    "stocks": [
        {{
            "stock_symbol": "SYMBOL",
            "company_name": "Full Company Name",
            "action": "BUY",
            "entry_price": 100.00,
            "stop_loss": 97.50,
            "target_price": 106.00,
            "confidence_score": 0.82,
            "days_to_target": 0,
            "reasoning": "2–3 sentences: which indicator combos triggered, VWAP position, key levels used."
        }},
        {{
            "stock_symbol": "SYMBOL2",
            "company_name": "Full Company Name",
            "action": "SELL",
            "entry_price": 200.00,
            "stop_loss": 205.00,
            "target_price": 192.00,
            "confidence_score": 0.78,
            "days_to_target": 0,
            "reasoning": "2–3 sentences: bearish indicators, VWAP below, key resistance levels."
        }}
    ]
}}

Select EXACTLY {num_stocks} stocks (fewer only if truly insufficient quality candidates).
"""

    def _build_intraday_user_instruction(self, num_stocks: int) -> str:
        return (
            f"INTRADAY MODE: Select {num_stocks} stocks (BUY or SELL/short) with signal_strength ≥ 2 "
            f"and volume_ratio ≥ 1.5. Use VWAP position, MACD histogram, BB position, and pivot levels "
            f"to set precise entry/stop/target. Prioritise stocks where ≥ 2 of the 3 indicator combos agree. "
            f"All days_to_target must be 0. Enforce strict price ordering: "
            f"BUY → stop < entry < target; SELL → target < entry < stop."
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

## General Selection Criteria (rank by importance)
1. Volume Surge — volume_ratio > 1.5× (institutional accumulation signal)
2. Momentum — strong 5-day price momentum, MACD histogram turning positive
3. RSI Sweet Spot — RSI between 55–72 (momentum zone, not overbought)
4. Trend Alignment — price above SMA20 and EMA21 (STRONG_BULLISH preferred)
5. Risk/Reward — minimum 1:2.5 R:R ratio; prefer 1:3 or better
6. Tight Stop — stop-loss within 1.5–2× ATR of entry

{hold_section}

## CRITICAL: Price Ordering Rules (violations cause trade rejection)
- stop_loss MUST be LESS than entry_price    (e.g. entry=100, stop_loss=98)
- target_price MUST be GREATER than entry_price  (e.g. entry=100, target=112)
For BUY trades: stop_loss < entry_price < target_price — ALWAYS.

Return ONLY valid JSON:
{{
    "stocks": [
        {{
            "stock_symbol": "SYMBOL",
            "company_name": "Full Company Name",
            "action": "BUY",
            "entry_price": 100.00,
            "stop_loss": 97.00,
            "target_price": 112.00,
            "confidence_score": 0.85,
            "days_to_target": 3,
            "reasoning": "Concise 2-3 sentence explanation of the setup."
        }}
    ]
}}

Select EXACTLY {num_stocks} stocks (or fewer only if truly insufficient quality candidates).
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
