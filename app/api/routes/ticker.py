"""
Ticker Routes — KiteTicker real-time price streaming via SSE

GET  /ticker/stream   — SSE stream of live ticks (WebSocket → SSE bridge)
GET  /ticker/snapshot — One-shot LTP snapshot (no WebSocket)
GET  /ticker/status   — Check if ticker is connected for a user
POST /ticker/stop     — Disconnect ticker for a user
"""

import json
import asyncio
from fastapi import APIRouter, Query, HTTPException
from fastapi.responses import StreamingResponse
from app.services.ticker_service import ticker_service, INDEX_TOKENS
from app.core.logging import logger
from typing import Optional, List

router = APIRouter()


# ── GET /ticker/stream ────────────────────────────────────────────────────────

@router.get("/stream")
async def stream_ticks(
    api_key: str = Query(..., description="User's Zerodha API key"),
    access_token: str = Query(..., description="User's Zerodha access token"),
    tokens: Optional[str] = Query(
        None,
        description=(
            "Comma-separated instrument tokens to subscribe. "
            "Defaults to NIFTY 50 (256265) + NIFTY BANK (260105)."
        ),
    ),
):
    """
    SSE (Server-Sent Events) stream of real-time Zerodha ticks.

    Connect with:
      EventSource('/api/v1/ticker/stream?api_key=...&access_token=...')

    Each event:
      data: {"instrument_token": 256265, "last_price": 22534.5, "change": 0.12, ...}

    Heartbeat every 30s if no ticks:
      data: {"heartbeat": true, "timestamp": "..."}
    """
    token_list: List[int] = list(INDEX_TOKENS.values())  # default
    if tokens:
        try:
            token_list = [int(t.strip()) for t in tokens.split(",") if t.strip()]
        except ValueError:
            raise HTTPException(status_code=400, detail="tokens must be integers")

    async def event_generator():
        try:
            async for tick in ticker_service.stream(api_key, access_token, token_list):
                yield f"data: {json.dumps(tick)}\n\n"
        except asyncio.CancelledError:
            logger.info(f"[TickerSSE] Client disconnected: {api_key[:8]}…")
        except Exception as e:
            logger.error(f"[TickerSSE] Stream error: {e}")
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",   # disable nginx buffering
            "Connection": "keep-alive",
        },
    )


# ── GET /ticker/snapshot ──────────────────────────────────────────────────────

@router.get("/snapshot")
async def get_price_snapshot(
    api_key: str = Query(...),
    access_token: str = Query(...),
    tokens: Optional[str] = Query(
        None,
        description="Comma-separated instrument tokens. Default: NIFTY+BankNifty."
    ),
):
    """
    One-shot LTP snapshot for given tokens.
    Much lighter than the stream endpoint — use for one-time price fetches.
    Returns: {token: {last_price, instrument_token}}
    """
    token_list: List[int] = list(INDEX_TOKENS.values())
    if tokens:
        try:
            token_list = [int(t.strip()) for t in tokens.split(",") if t.strip()]
        except ValueError:
            raise HTTPException(status_code=400, detail="tokens must be integers")

    try:
        loop = asyncio.get_event_loop()
        snapshot = await loop.run_in_executor(
            None,
            lambda: ticker_service.get_snapshot(api_key, access_token, token_list),
        )
        return {
            "snapshot": snapshot,
            "tokens": token_list,
            "index_map": {str(v): k for k, v in INDEX_TOKENS.items()},
        }
    except Exception as e:
        logger.error(f"[TickerSnapshot] {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Snapshot failed: {e}")


# ── GET /ticker/status ────────────────────────────────────────────────────────

@router.get("/status")
async def get_ticker_status(
    api_key: str = Query(...),
):
    """Check if a WebSocket ticker connection is active for this user."""
    return ticker_service.status(api_key)


# ── POST /ticker/stop ─────────────────────────────────────────────────────────

@router.post("/stop")
async def stop_ticker(
    api_key: str = Query(...),
):
    """Disconnect the WebSocket ticker for this user."""
    ticker_service.stop(api_key)
    return {"message": f"Ticker stopped for {api_key[:8]}…"}
