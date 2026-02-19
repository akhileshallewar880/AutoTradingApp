from fastapi import APIRouter, BackgroundTasks, HTTPException
from app.models.request_models import AgentRunRequest
from app.models.response_models import AgentRunResponse
from app.agents.trading_agent import trading_agent
from app.core.logging import logger

router = APIRouter()

@router.post("/run-agent", response_model=AgentRunResponse)
async def run_trading_agent(request: AgentRunRequest, background_tasks: BackgroundTasks):
    """
    Triggers the autonomous trading agent.
    For this POC, we run it await-style to return the specific trades found in the response.
    In a real event-driven system, this might just acknowledge and run in background.
    """
    logger.info(f"Received Agent Run Request: {request}")
    try:
        # Running synchronously (awaited) to return the result immediately for the user demo
        response = await trading_agent.run(request)
        return response
    except Exception as e:
        logger.error(f"Agent run failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))
