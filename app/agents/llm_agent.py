from openai import AsyncOpenAI
from app.core.config import get_settings
from app.core.logging import logger
from typing import Dict, List, Optional
import json

settings = get_settings()


class LLMAgent:
    """
    LLM-powered stock picker.

    New approach: acts as a momentum analyst focused on
    *maximum profit in minimum trading days* across the full NSE market.
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
    ) -> Dict:
        """
        Send pre-screened NSE market data to GPT-4o.
        Returns trade recommendations optimised for max profit in minimum days.
        """
        logger.info(
            f"LLM analyzing {len(market_data)} NSE candidates "
            f"(hold={hold_duration_days}d, sectors={sectors})"
        )

        hold_label = self._hold_label(hold_duration_days)
        sector_context = (
            f"Focus on sectors: {', '.join(sectors)}"
            if sectors and sectors != ["ALL"]
            else "Search across the entire NSE market (all sectors)"
        )

        # Build hold-duration-specific emphasis for system prompt
        if hold_duration_days == 0:
            hold_specific_section = """
## ★ INTRADAY SELECTION — THIS IS THE MOST IMPORTANT SECTION ★
You are picking stocks for SAME-DAY exit (MIS product). Apply these rules strictly:

1. **Volume is KING** — ONLY select stocks with volume_ratio ≥ 2.0 (i.e. today's volume at least 2× the 20-day average). Higher is better. Reject any stock with volume_ratio < 1.5.
2. **High ATR** — prefer stocks with high ATR relative to price (ATR/price > 1.5%). This ensures enough intraday range to hit targets within hours, not days.
3. **Volatility is GOOD** — for intraday, you WANT volatile stocks. Higher volatility_5d = better candidate. Do NOT pick low-volatility, slow-moving stocks.
4. **Intraday breakouts** — look for stocks breaking above resistance_20d or surging past EMA9/SMA20 with volume confirmation.
5. **Momentum today** — day_change_pct should be positive and ideally > 1%. Stocks already moving today have momentum to continue.
6. **Tight targets** — target should be achievable within 1 trading day. Use 1.5–2.5× ATR as target distance. Don't set unrealistic multi-day targets.
7. **days_to_target MUST be 0** for all intraday picks (same-day exit).
8. **Risk/Reward** — minimum 1:1.5 R:R for intraday (tighter than swing trades).
9. DO NOT select stocks that are slow movers, low volume, or have narrow trading ranges. These are completely unsuitable for intraday trading.
"""
        elif hold_duration_days <= 7:
            hold_specific_section = """
## Short-Term Selection (1–7 days)
- Prioritise momentum + volume surge, RSI 58–70, MACD crossover
- Volume ratio > 1.5x preferred
- Target achievable within the hold period
"""
        else:
            hold_specific_section = """
## Medium-Term Selection (8–30 days)
- Prioritise trend strength (STRONG_BULLISH), RSI 55–68
- Price near 52-week high signals momentum continuation
- Volume ratio > 1.3x to confirm institutional interest
"""

        system_prompt = f"""You are an elite AI trading analyst specialising in the Indian NSE stock market.

Your SOLE OBJECTIVE: identify stocks with the **highest probability of maximum profit in the shortest number of trading days**.

Hold Duration Context: {hold_label}
{sector_context}

## General Selection Criteria (rank by importance)
1. **Volume Surge** — volume_ratio > 1.5x (institutional accumulation signal)
2. **Momentum** — strong 5-day price momentum, MACD histogram turning positive
3. **RSI Sweet Spot** — RSI between 55–72 (momentum zone, not overbought)
4. **Trend Alignment** — price above SMA20 and EMA21 (STRONG_BULLISH preferred)
5. **Risk/Reward** — minimum 1:2.5 R:R ratio; prefer 1:3 or better
6. **Tight Stop** — stop-loss within 1.5–2× ATR of entry (limits downside)

{hold_specific_section}

## Output Rules
- Select EXACTLY {num_stocks} stocks (or fewer only if truly insufficient quality candidates)
- For each stock provide precise entry, stop-loss, and target based on technical levels
- Entry = current last_close (market order)
- Stop-loss = last_close − (1.5 × ATR) minimum, or nearest support level
- Target = entry + (stop_loss_distance × 3) minimum (1:3 R:R) — for intraday, 1.5× ATR target is acceptable
- Estimate realistic `days_to_target` based on recent momentum and ATR
- Confidence score: 0.7+ only for genuinely high-conviction setups

## CRITICAL: Price Ordering Rules (violations cause trade rejection)
- **stop_loss MUST be LESS than entry_price** (e.g. entry=100, stop_loss=98) ← ALWAYS
- **target_price MUST be GREATER than entry_price** (e.g. entry=100, target=108) ← ALWAYS
- For BUY trades: stop_loss < entry_price < target_price
- Never swap these values. A stop_loss above entry is INVALID and will be rejected.

IMPORTANT: Return ONLY valid JSON in this exact format:
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
            "reasoning": "Concise 2-3 sentence explanation: why this stock NOW, what technical setup, expected catalyst."
        }}
    ]
}}
"""

        # Build hold-duration-specific user instructions
        if hold_duration_days == 0:
            hold_instruction = (
                f"INTRADAY MODE: Pick the {num_stocks} stocks with the HIGHEST volume and intraday range. "
                f"REJECT any stock with volume_ratio < 1.5. Prefer volume_ratio ≥ 2.0 and high ATR. "
                f"All days_to_target must be 0. Only pick stocks suitable for same-day exit."
            )
        else:
            hold_instruction = (
                f"Pick the {num_stocks} best opportunities for maximum profit in {hold_label}. "
                f"Prioritise stocks with volume surges, strong momentum, and clear technical setups."
            )

        user_content = f"""
Available Balance: ₹{available_balance:,.2f}
Risk Per Trade: {risk_percent}%
Hold Duration: {hold_label}
Stocks Requested: {num_stocks}

Pre-Screened NSE Market Data (sorted by composite score):
{json.dumps(market_data, default=str, indent=2)}

{hold_instruction}
"""

        try:
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_content},
                ],
                response_format={"type": "json_object"},
                temperature=0.2,  # Low temperature for consistent, conservative picks
                max_tokens=4000,
            )

            content = response.choices[0].message.content
            logger.info("LLM analysis complete")
            logger.debug(f"LLM response: {content[:500]}…")

            data = json.loads(content)
            return data

        except Exception as e:
            logger.error(f"LLM analysis failed: {e}")
            return {"stocks": []}

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
