from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional
from app.agents.autonomous_agent import autonomous_agent_manager
from app.core.logging import logger

router = APIRouter()


class StartAgentRequest(BaseModel):
    api_key: str
    access_token: str
    user_id: str
    max_positions: int = 2
    risk_percent: float = 1.0
    scan_interval_minutes: int = 5
    max_trades_per_day: int = 6
    max_daily_loss_pct: float = 2.0
    capital_to_use: float = 0.0  # 0 = use full available balance


@router.post("/live-trading/start")
async def start_agent(req: StartAgentRequest):
    """
    Start the autonomous trading agent for a user.
    Agent will scan markets every N minutes, enter trades when signal strength ≥ 2,
    trail stop losses, and auto-squareoff MIS positions at 3:10 PM.
    """
    try:
        result = await autonomous_agent_manager.start_agent(
            user_id=req.user_id,
            api_key=req.api_key,
            access_token=req.access_token,
            max_positions=req.max_positions,
            risk_percent=req.risk_percent,
            scan_interval_minutes=req.scan_interval_minutes,
            max_trades_per_day=req.max_trades_per_day,
            max_daily_loss_pct=req.max_daily_loss_pct,
            capital_to_use=req.capital_to_use,
        )
        return result
    except Exception as e:
        logger.error(f"Failed to start agent for user {req.user_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/live-trading/stop")
async def stop_agent(user_id: str = Query(...)):
    """Stop the autonomous trading agent for a user. Does NOT close open positions."""
    try:
        result = await autonomous_agent_manager.stop_agent(user_id)
        return result
    except Exception as e:
        logger.error(f"Failed to stop agent for user {user_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/live-trading/status")
async def get_agent_status(user_id: str = Query(...)):
    """
    Get current agent status: running state, open positions, trade count,
    daily P&L, recent decision logs.
    """
    status = autonomous_agent_manager.get_agent_status(user_id)
    if status is None:
        return {
            "is_running": False,
            "status": "STOPPED",
            "started_at": None,
            "last_scan_at": None,
            "open_positions": [],
            "trade_count_today": 0,
            "daily_pnl": 0.0,
            "daily_loss_limit_hit": False,
            "settings": {},
            "recent_logs": [],
        }
    return status
