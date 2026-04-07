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
5. Minimum Risk:Reward = 1:1.5 for any options trade
6. STOP LOSS on premium = 30–40% of entry premium
   - entry ₹50  → SL ₹30–35  (loss of ₹15–20)
   - entry ₹100 → SL ₹60–70  (loss of ₹30–40)
   - entry ₹150 → SL ₹90–105 (loss of ₹45–60)
   Tighter SL = smaller lots needed, better capital efficiency
7. TARGET on premium = entry + 1.5× to 2× (entry - SL)
   - entry ₹100, SL ₹65 → risk=₹35 → target ₹152–₹170
   - entry ₹150, SL ₹100 → risk=₹50 → target ₹225 MAX (do not exceed 50% gain)
   - NEVER set target more than 50% above entry — it is unreachable intraday
   - For weak signals (strength ≤ 3/5): cap target at 30% above entry
8. Time filter: Never recommend buying options after 2:00 PM IST
9. Expiry-day caution: On expiry day, avoid buying options after 1:30 PM (theta decay)
10. Prefer strong signal (3+/5 indicator votes) — weak signals = gambling, not trading
11. REALITY CHECK — typical intraday NIFTY/BANKNIFTY option moves:
    - Small move (30–50 pts index): premium changes 10–25%
    - Medium move (50–100 pts index): premium changes 25–50%
    - Large move (100+ pts index): premium changes 50–100%
    Calibrate your target to the signal strength. Do NOT expect 100% premium gain on a weak signal.
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
        max_risk_rupees: float = 0.0,
        max_sl_distance_per_unit: float = 999.0,
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
        candle_count = ind.get("candle_count", 0)
        data_quality = ind.get("data_quality", "NORMAL")
        data_quality_note = (
            f"\n⚠️ LOW DATA QUALITY: Only {candle_count} candles available "
            f"(need 35 for reliable MACD). MACD signal may be noisy — "
            "reduce confidence score by 0.1–0.2 and prefer VWAP/RSI/EMA signals over MACD.\n"
            if data_quality == "LOW" else ""
        )
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
- Capital: ₹{capital:,.0f} | Risk per trade: {risk_percent}% = ₹{max_risk_rupees:,.0f} MAX LOSS
- Lots requested: {lots} (lot size = {lot_size} units)
- ⚠️ HARD CONSTRAINT: Max SL distance = ₹{max_sl_distance_per_unit:.2f} per unit
  → (entry_premium - stop_loss_premium) MUST be ≤ ₹{max_sl_distance_per_unit:.2f}
  → Total max loss = (entry - SL) × {lot_size} × {lots} ≤ ₹{max_risk_rupees:,.0f}
  → If you cannot place a meaningful SL within this budget, reduce lots_recommended or return NONE.

## Technical Indicators (5-min candles, {candle_count} candles){data_quality_note}
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
- Confidence score: calibrated as follows — be honest, do NOT default to 0.8:
    0.9–1.0 : 4–5 votes aligned, strong crossover, clear trend
    0.7–0.89 : 3 votes, decent signal, moderate conviction
    0.5–0.69 : 2 votes or mixed signals, marginal trade
    < 0.5   : weak signal, consider returning NONE instead
- Suggested hold minutes: how many minutes to hold before exiting if neither SL nor target is hit (15–90 min for intraday; shorter near end of day or on weak signals)
- Hold reasoning: one sentence explaining why that hold duration (e.g. "momentum trade, exit by 11 AM before lunch drift")
- Reasoning: detailed explanation of your decision

Respond ONLY with valid JSON:
{{
  "option_type": "CE" | "PE" | "NONE",
  "entry_premium": <float>,
  "stop_loss_premium": <float>,
  "target_premium": <float>,
  "lots_recommended": <int>,
  "confidence_score": <float 0.0-1.0>,
  "suggested_hold_minutes": <int>,
  "hold_reasoning": "<one sentence>",
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
            err_type = type(e).__name__
            err_msg = str(e)[:200]
            logger.error(f"[OptionsLLMAgent] GPT call failed ({err_type}): {e}")
            return self._fallback_response(
                engine_signal, entry_premium_ce, entry_premium_pe, lots,
                error_info=f"{err_type}: {err_msg}",
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
        sl = float(result.get("stop_loss_premium", entry * 0.65))
        target = float(result.get("target_premium", entry + (entry - sl) * 1.5))
        lots = int(result.get("lots_recommended", 1))
        confidence = float(result.get("confidence_score", 0.5))

        # Enforce: SL must be below entry for options BUY
        if sl >= entry:
            sl = round(entry * 0.65, 1)
            logger.warning(f"[OptionsLLMAgent] Auto-corrected SL to {sl} (was >= entry {entry})")

        risk = entry - sl

        # Enforce minimum 1:1.5 R:R
        rr = (target - entry) / risk if risk > 0 else 0
        if rr < 1.5:
            target = round(entry + risk * 1.5, 1)
            logger.warning(f"[OptionsLLMAgent] Auto-corrected target to {target} (1:1.5 R:R)")

        # Cap target at 50% above entry — anything higher is unrealistic intraday
        max_target = round(entry * 1.50, 1)
        if target > max_target:
            target = max_target
            logger.warning(f"[OptionsLLMAgent] Capped target to {target} (50% above entry {entry})")

        # Clamp lots
        lots = max(1, min(lots, max_lots))
        confidence = max(0.0, min(1.0, confidence))

        hold_minutes = int(result.get("suggested_hold_minutes", 30))
        hold_minutes = max(10, min(hold_minutes, 90))  # clamp 10–90 min

        result.update({
            "option_type": opt_type,
            "entry_premium": entry,
            "stop_loss_premium": sl,
            "target_premium": target,
            "lots_recommended": lots,
            "confidence_score": confidence,
            "suggested_hold_minutes": hold_minutes,
            "hold_reasoning": result.get("hold_reasoning", ""),
        })
        return result

    def _fallback_response(
        self,
        engine_signal: Dict,
        premium_ce: float,
        premium_pe: float,
        max_lots: int,
        error_info: str = "",
    ) -> Dict:
        """Fallback when GPT fails — use engine signal with default levels."""
        sig = engine_signal.get("signal", "NEUTRAL")
        error_suffix = f" [AI error: {error_info}]" if error_info else ""

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
                "ai_reasoning": f"No clear signal from technical indicators.{error_suffix}",
            }

        sl = round(entry * 0.65, 1)   # 35% SL — realistic intraday options stop
        target = round(entry + (entry - sl) * 1.5, 1)  # 1:1.5 R:R, capped at 50%
        target = min(target, round(entry * 1.50, 1))
        return {
            "option_type": opt_type,
            "entry_premium": entry,
            "stop_loss_premium": sl,
            "target_premium": target,
            "lots_recommended": 1,
            "confidence_score": round(engine_signal.get("score", 50) / 100, 2),
            "suggested_hold_minutes": 30,
            "hold_reasoning": "Default hold — exit within 30 minutes if target/SL not hit.",
            "ai_reasoning": (
                f"Fallback analysis (AI call failed{error_suffix}). "
                f"Engine signal: {sig} with {engine_signal.get('strength', 0)}/5 votes. "
                + "; ".join(engine_signal.get("reasons", []))
            ),
        }


options_llm_agent = OptionsLLMAgent()
