"""
Options LLM Agent v2 — Narrative Summarizer Only

GPT-4o's role has changed completely:
  - BEFORE: GPT decided BUY_CE / BUY_PE / NONE and set premium levels.
  - NOW:    The engine decides signal and levels. GPT writes a plain-English
            summary explaining WHY the setup passed or failed, a confidence
            score for logging, and any risk notes.

GPT cannot change the signal. It cannot override hard rules. If GPT fails
or returns garbage, the trade still executes (or is rejected) based on the
engine's authoritative BreakoutResult.
"""

import json
from datetime import date
from typing import Dict, Optional

from openai import AsyncOpenAI

from app.core.config import settings
from app.core.logging import logger
from app.engines.options_engine import BreakoutResult


_SUMMARY_SYSTEM_PROMPT = """You are a professional trading journal assistant.
You receive the output of a deterministic breakout engine and write a concise
trade-setup summary for the trader's log. You do NOT decide whether to trade.
That decision was already made by the rules engine. Your job is to explain it clearly.

Rules:
- If signal=NO_TRADE, explain which specific condition(s) blocked the trade.
- If signal=BUY_CE or BUY_PE, explain what the setup looks like and why it qualifies.
- Confidence score should reflect how clean the setup is (0.50–0.65 = marginal pass,
  0.65–0.80 = solid setup, 0.80–0.95 = textbook A+ setup).
- Be concise. 3–5 sentences maximum for summary. 1 sentence for risk_notes.
- Never say "I recommend" or "you should trade" — you are a journal writer, not an advisor.

Respond ONLY with valid JSON. No markdown, no text outside the JSON.
"""


class OptionsLLMAgent:

    def __init__(self):
        self.client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)

    async def summarize_trade(
        self,
        index: str,
        result: BreakoutResult,
        current_price: float,
        expiry_date: date,
        entry_premium: float = 0.0,
        stop_loss_premium: float = 0.0,
        target_premium: float = 0.0,
        lots: int = 1,
        lot_size: int = 75,
    ) -> Dict:
        """
        Ask GPT-4o to write a narrative summary of the engine's decision.
        Returns a dict with: summary, confidence, risk_notes, ai_reasoning.
        Never changes the signal or levels.
        """
        ind = result.indicators

        # Build a concise context block for GPT — no need for the full lesson set
        context = f"""
## Engine Decision
Signal: {result.signal}
Regime: {result.regime.value}
Trade allowed: {result.trade_allowed}

## Gates passed
{chr(10).join(f'✓ {r}' for r in result.reasons) or '(none)'}

## Gates failed
{chr(10).join(f'✗ {f}' for f in result.failed_filters) or '(none — setup passed all gates)'}

## Index Context
- {index} price: ₹{current_price:.2f}
- Opening range: ₹{result.or_high:.2f} (high) / ₹{result.or_low:.2f} (low)
- VWAP: ₹{ind.get('vwap', 0):.2f} ({ind.get('price_vs_vwap', 'N/A')})
- ADX: {ind.get('adx', 0):.1f}  ATR: {ind.get('atr', 0):.2f}
- RSI: {ind.get('rsi', 0):.1f}  EMA9: {ind.get('ema_9', 0):.2f}  EMA21: {ind.get('ema_21', 0):.2f}
- OR range: {ind.get('or_range_pct', 0):.2f}%
- Candles available: {ind.get('candle_count', 0)}

## Expiry / Trade Context
- Expiry: {expiry_date}
- Entry premium (ATM): ₹{entry_premium:.2f}
- SL premium: ₹{stop_loss_premium:.2f}
- Target premium: ₹{target_premium:.2f}
- Lots: {lots} × lot_size {lot_size} = {lots * lot_size} qty

{"## Index Levels (engine-computed, structure-based)" if result.signal != 'NO_TRADE' else ''}
{f'- Entry: ₹{result.entry_index_price:.2f}' if result.signal != 'NO_TRADE' else ''}
{f'- Stop loss: ₹{result.sl_index_price:.2f}' if result.signal != 'NO_TRADE' else ''}
{f'- Target: ₹{result.target_index_price:.2f}' if result.signal != 'NO_TRADE' else ''}
""".strip()

        user_message = (
            f"{context}\n\n"
            "Write a trading-journal summary of this setup. "
            "Respond ONLY with JSON in this exact format:\n"
            "{\n"
            '  "summary": "<3-5 sentence explanation of why the setup passed or was rejected>",\n'
            '  "confidence": <float 0.0-1.0 — how clean/textbook is this setup>,\n'
            '  "risk_notes": "<1 sentence — key risk to watch for this trade>",\n'
            '  "ai_reasoning": "<same as summary but more technical, 2-3 sentences>"\n'
            "}"
        )

        try:
            response = await self.client.chat.completions.create(
                model="gpt-4o",
                messages=[
                    {"role": "system", "content": _SUMMARY_SYSTEM_PROMPT},
                    {"role": "user",   "content": user_message},
                ],
                response_format={"type": "json_object"},
                temperature=0.2,
                max_tokens=400,
            )
            raw = response.choices[0].message.content
            data = json.loads(raw)

            # Validate / clamp confidence
            confidence = float(data.get("confidence", 0.5))
            confidence = max(0.0, min(1.0, confidence))
            data["confidence"] = confidence

            logger.info(
                f"[OptionsLLMAgent] Summary generated for {index} {result.signal} "
                f"(confidence={confidence:.2f})"
            )
            return data

        except Exception as e:
            logger.warning(
                f"[OptionsLLMAgent] GPT summary failed ({type(e).__name__}): {e} — "
                "using fallback summary"
            )
            return self._fallback_summary(result, index)

    def _fallback_summary(self, result: BreakoutResult, index: str) -> Dict:
        """Returns a minimal summary when GPT is unavailable."""
        if result.signal == "NO_TRADE":
            reason = result.failed_filters[0] if result.failed_filters else "Conditions not met"
            summary = (
                f"Engine returned NO_TRADE for {index}. "
                f"Primary reason: {reason}. "
                "No trade will be placed — this is the correct disciplined outcome."
            )
            confidence = 0.0
            risk_note  = "No trade taken — no risk."
        else:
            regime_label = result.regime.value.replace("_", " ").title()
            summary = (
                f"{index} shows a {regime_label} regime with all breakout gates confirmed. "
                f"Opening range: ₹{result.or_high:.0f}–₹{result.or_low:.0f}, "
                f"ADX {result.adx:.0f} confirms trend strength. "
                f"Structure-based SL at ₹{result.sl_index_price:.2f}. "
                "Entry qualifies as an A+ setup per engine rules."
            )
            confidence = 0.70
            risk_note  = (
                "Monitor for false breakout reversal — use partial exit at 1R "
                "to lock in profit before trailing the remainder."
            )

        return {
            "summary":      summary,
            "confidence":   confidence,
            "risk_notes":   risk_note,
            "ai_reasoning": summary,
        }


options_llm_agent = OptionsLLMAgent()
