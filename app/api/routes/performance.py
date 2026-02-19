from fastapi import APIRouter
from app.models.response_models import MonthlyPerformanceResponse
from app.engines.performance_engine import performance_engine
from app.storage.database import db
from datetime import datetime

router = APIRouter()

@router.get("/monthly-performance", response_model=MonthlyPerformanceResponse)
async def get_monthly_performance():
    """
    Returns performance metrics for the current month.
    """
    now = datetime.now()
    trades = await db.get_monthly_trades(now.month, now.year)
    
    metrics = performance_engine.calculate_monthly_metrics(trades)
    
    return MonthlyPerformanceResponse(
        total_pnl=metrics['total_pnl'],
        win_rate=metrics['win_rate'],
        max_drawdown=metrics['max_drawdown'],
        total_trades=metrics['total_trades'],
        month=now.strftime("%B %Y")
    )
