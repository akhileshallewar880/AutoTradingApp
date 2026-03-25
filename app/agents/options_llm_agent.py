"""
Options LLM Agent — GPT-4o powered analysis for Nifty / BankNifty options.

Given index technical indicators + signal from OptionsEngine, the LLM:
  1. Confirms or overrides the CE/PE direction
  2. Recommends entry premium, SL, and target with reasoning
  3. Provides confidence score based on indicator confluence
"""

import json
from openai import AsyncOpenAI
from app.core.config import get_settings
from app.core.logging import logger
from typing import Dict, Optional
from datetime import date

settings = get_settings()


class OptionsLLMAgent:

    OPTIONS_LESSONS = """
## Options Trading Rules (MANDATORY — apply to every analysis)
1. NEVER buy options when VIX > 25 and RSI > 70 simultaneously (premium crush risk)
2. AVOID buying CE when RSI > 75 (overbought — reversal likely)
3. AVOID buying PE when RSI < 25 (oversold — snap-back likely)
4. PREFER ATM or 1-strike OTM options for best premium-to-risk ratio
5. Minimum Risk:Reward = 1:2 for any options trade (target must be 2× the risk)
6. STOP LOSS on premium = 25–30% of entry premium (e.g., entry ₹100 → SL ₹70–75)
7. TARGET on premium = entry + 2× (entry - SL) (e.g., entry ₹100, SL ₹75 → target ₹150)
8. Time filter: Never recommend buying options after 2:00 PM IST
9. Expiry-day caution: On expiry day, avoid buying options after 1:30 PM (theta decay)
10. Prefer strong signal (3+/5 indicator votes) — weak signals = gambling, not trading
"""

    def __init__(self):
        self.client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)

    async def analyze_options_opportunity(
        self,
        index: str,
        current_price: float,
        expiry_date: date,
        indicators: Dict,
        engine_signal: Dict,
        atm_strike: float,
        entry_premium_ce: float,
        entry_premium_pe: float,
        lots: int,
        lot_size: int,
        capital: float,
        risk_percent: float,
    ) -> Dict:
        """
        Ask GPT-4o to analyze the index and recommend a CE or PE trade.

        Returns a dict with:
          option_type      : "CE" | "PE" | "NONE"
          confidence_score : 0.0–1.0
          entry_premium    : float
          stop_loss_premium: float
          target_premium   : float
          ai_reasoning     : str
          lots_recommended : int
        """
        signal_str = engine_signal.get("signal", "NEUTRAL")
        signal_reasons = "\n".join(
            f"  {i+1}. {r}" for i, r in enumerate(engine_signal.get("reasons", []))
        )
        strength = engine_signal.get("strength", 0)
        bull_votes = engine_signal.get("bullish_votes", 0)
        bear_votes = engine_signal.get("bearish_votes", 0)
        expiry_warning = engine_signal.get("expiry_warning", False)

        ind = indicators
        expiry_warning_note = (
            "\n⚠️ EXPIRY DAY + after 1:30 PM: theta decay is very high — "
            "be extra conservative or avoid trade.\n"
            if expiry_warning else ""
        )

        prompt = f"""You are an expert options trader specializing in Nifty and BankNifty intraday options.

{self.OPTIONS_LESSONS}

## Market Context
- Index: {index}
- Current Price: ₹{current_price:.2f}
- ATM Strike: {atm_strike}
- Expiry Date: {expiry_date}
- Capital: ₹{capital:,.0f} | Risk: {risk_percent}%
- Lots requested: {lots} (lot size = {lot_size} units)

## Technical Indicators (5-min candles)
- RSI(14): {ind.get('rsi', 50):.1f}
- VWAP: ₹{ind.get('vwap', 0):.2f} → Price is {ind.get('price_vs_vwap', 'NEUTRAL')} VWAP
- MACD Histogram: {ind.get('macd_histogram', 0):.4f}
  - Bullish crossover: {ind.get('macd_bullish_crossover', False)}
  - Bearish crossover: {ind.get('macd_bearish_crossover', False)}
- Bollinger Band position: {ind.get('bb_position', 'MIDDLE')}
- EMA9: {ind.get('ema_9', 0):.2f} | EMA21: {ind.get('ema_21', 0):.2f}
- Stochastic K: {ind.get('stoch_k', 50):.1f} | D: {ind.get('stoch_d', 50):.1f}

## Engine Signal
- Direction: {signal_str}
- Strength: {strength}/5 (Bullish votes: {bull_votes}, Bearish votes: {bear_votes})
- Reasons:
{signal_reasons}
{expiry_warning_note}
## Live Option Premiums (ATM)
- {index} {atm_strike} CE premium: ₹{entry_premium_ce:.2f}
- {index} {atm_strike} PE premium: ₹{entry_premium_pe:.2f}

## Your Task
Based on the above data, decide whether to:
1. BUY CALL (CE) — if index is expected to go UP
2. BUY PUT (PE) — if index is expected to go DOWN
3. PASS — if signal is weak or conditions are unfavorable

For your chosen option (CE or PE), specify:
- Entry premium: exact premium to buy at
- Stop-loss premium: level to exit if trade goes wrong (25–30% below entry)
- Target premium: level to take profit (minimum 2× the risk)
- Lots to trade (can be less than {lots} if risk is too high)
- Confidence score: 0.0 (no confidence) to 1.0 (very high confidence)
- Reasoning: detailed explanation of your decision

Respond ONLY with valid JSON:
{{
  "option_type": "CE" | "PE" | "NONE",
  "entry_premium": <float>,
  "stop_loss_premium": <float>,
  "target_premium": <float>,
  "lots_recommended": <int>,
  "confidence_score": <float 0.0-1.0>,
  "ai_reasoning": "<detailed reasoning string>"
}}
"""

        logger.info(
            f"[OptionsLLMAgent] Calling GPT-4o for {index} options analysis "
            f"(signal={signal_str}, strength={strength}/5)"
        )

        try:
            response = await self.client.chat.completions.create(
                model="gpt-4o",
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "You are an expert options trader. Respond ONLY with valid JSON. "
                            "No markdown, no explanation outside JSON."
                        ),
                    },
                    {"role": "user", "content": prompt},
                ],
                response_format={"type": "json_object"},
                temperature=0.2,
                max_tokens=800,
            )

            raw = response.choices[0].message.content
            result = json.loads(raw)
            logger.info(
                f"[OptionsLLMAgent] GPT response: option_type={result.get('option_type')} "
                f"confidence={result.get('confidence_score')} "
                f"entry={result.get('entry_premium')} "
                f"sl={result.get('stop_loss_premium')} "
                f"target={result.get('target_premium')}"
            )
            return self._validate_response(result, entry_premium_ce, entry_premium_pe, lots)

        except Exception as e:
            logger.error(f"[OptionsLLMAgent] GPT call failed: {e}")
            # Fallback: use engine signal directly
            return self._fallback_response(
                engine_signal, entry_premium_ce, entry_premium_pe, lots
            )

    def _validate_response(
        self,
        result: Dict,
        premium_ce: float,
        premium_pe: float,
        max_lots: int,
    ) -> Dict:
        """Validate and auto-correct LLM response fields."""
        opt_type = result.get("option_type", "NONE").upper()
        if opt_type not in ("CE", "PE", "NONE"):
            opt_type = "NONE"

        if opt_type == "NONE":
            return result

        entry = float(result.get("entry_premium", premium_ce if opt_type == "CE" else premium_pe))
        sl = float(result.get("stop_loss_premium", entry * 0.70))
        target = float(result.get("target_premium", entry + (entry - sl) * 2))
        lots = int(result.get("lots_recommended", 1))
        confidence = float(result.get("confidence_score", 0.5))

        # Enforce: SL must be below entry for options BUY
        if sl >= entry:
            sl = round(entry * 0.72, 1)
            logger.warning(f"[OptionsLLMAgent] Auto-corrected SL to {sl} (was >= entry {entry})")

        # Enforce minimum 1:2 R:R
        rr = (target - entry) / (entry - sl) if entry > sl else 0
        if rr < 2.0:
            target = round(entry + (entry - sl) * 2.0, 1)
            logger.warning(f"[OptionsLLMAgent] Auto-corrected target to {target} (1:2 R:R)")

        # Clamp lots
        lots = max(1, min(lots, max_lots))
        confidence = max(0.0, min(1.0, confidence))

        result.update({
            "option_type": opt_type,
            "entry_premium": entry,
            "stop_loss_premium": sl,
            "target_premium": target,
            "lots_recommended": lots,
            "confidence_score": confidence,
        })
        return result

    def _fallback_response(
        self,
        engine_signal: Dict,
        premium_ce: float,
        premium_pe: float,
        max_lots: int,
    ) -> Dict:
        """Fallback when GPT fails — use engine signal with default levels."""
        sig = engine_signal.get("signal", "NEUTRAL")
        if sig == "BUY_CE":
            opt_type = "CE"
            entry = premium_ce
        elif sig == "BUY_PE":
            opt_type = "PE"
            entry = premium_pe
        else:
            return {
                "option_type": "NONE",
                "entry_premium": 0,
                "stop_loss_premium": 0,
                "target_premium": 0,
                "lots_recommended": 0,
                "confidence_score": 0.0,
                "ai_reasoning": "No clear signal from technical indicators.",
            }

        sl = round(entry * 0.72, 1)
        target = round(entry + (entry - sl) * 2, 1)
        return {
            "option_type": opt_type,
            "entry_premium": entry,
            "stop_loss_premium": sl,
            "target_premium": target,
            "lots_recommended": 1,
            "confidence_score": round(engine_signal.get("score", 50) / 100, 2),
            "ai_reasoning": (
                f"Fallback analysis (GPT unavailable). "
                f"Engine signal: {sig} with {engine_signal.get('strength', 0)}/5 votes. "
                + "; ".join(engine_signal.get("reasons", []))
            ),
        }


options_llm_agent = OptionsLLMAgent()
