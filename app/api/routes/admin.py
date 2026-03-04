"""
Admin dashboard API routes.
Handles admin authentication, metrics retrieval, and real-time event streaming via SSE.
"""

from fastapi import APIRouter, Depends, Query, HTTPException, Response
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime, timedelta
from sqlmodel import Session, select, func
from decimal import Decimal
import json
import asyncio
from jose import JWTError, jwt

from app.core.config import get_settings
from app.core.database import get_session, engine
from app.core.logging import logger
from app.models.db_models import (
    AdminUser,
    User,
    Analysis,
    TokenUsage,
    Trade,
    AnalysisStatusEnum,
    TradeStatusEnum,
)

settings = get_settings()
router = APIRouter(prefix="/api/v1/admin", tags=["Admin"])


# ============================================================================
# MODELS
# ============================================================================

class AdminLoginRequest(BaseModel):
    username: str
    password: str


class AdminLoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int


class AdminSummary(BaseModel):
    total_users: int
    active_today: int
    total_tokens_30d: int
    total_tokens_all_time: int
    estimated_cost_30d: float
    estimated_cost_all_time: float
    users_in_profit: int
    total_profit: float
    total_loss: float
    trades_today: int
    win_rate: float
    timestamp: datetime


class UserMetric(BaseModel):
    user_id: int
    email: str
    full_name: str
    created_at: datetime
    analyses_count: int
    tokens_used: int
    estimated_cost: float


class TokenMetric(BaseModel):
    date: str
    total_tokens: int
    total_cost: float
    users_count: int


class AdminUserResponse(BaseModel):
    id: int
    email: str
    username: str
    is_active: bool
    created_at: datetime
    last_login: Optional[datetime] = None


# ============================================================================
# AUTHENTICATION
# ============================================================================

def verify_admin_token(token: str) -> dict:
    """Verify JWT admin token."""
    try:
        payload = jwt.decode(
            token,
            settings.ADMIN_JWT_SECRET,
            algorithms=[settings.ADMIN_JWT_ALGORITHM],
        )
        return payload
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")


def create_admin_token(username: str) -> str:
    """Create JWT token for admin."""
    expires = datetime.utcnow() + timedelta(minutes=settings.ADMIN_JWT_EXPIRATION_MINUTES)
    payload = {
        "sub": username,
        "type": "admin",
        "exp": expires,
    }
    token = jwt.encode(
        payload,
        settings.ADMIN_JWT_SECRET,
        algorithm=settings.ADMIN_JWT_ALGORITHM,
    )
    return token


@router.post("/auth/login", response_model=AdminLoginResponse)
async def admin_login(request: AdminLoginRequest, session: Session = Depends(get_session)):
    """Authenticate admin user and return JWT token."""
    try:
        # Find admin user by username
        statement = select(AdminUser).where(AdminUser.username == request.username)
        admin_user = session.exec(statement).first()

        if not admin_user:
            raise HTTPException(status_code=401, detail="Invalid credentials")

        # Verify password using bcrypt (matches seed_admin.py hashing method)
        import bcrypt
        try:
            if not bcrypt.checkpw(
                request.password.encode('utf-8'),
                admin_user.password_hash.encode('utf-8')
            ):
                raise HTTPException(status_code=401, detail="Invalid credentials")
        except ValueError:
            # Invalid hash format
            raise HTTPException(status_code=401, detail="Invalid credentials")

        if not admin_user.is_active:
            raise HTTPException(status_code=403, detail="Admin user is inactive")

        # Update last_login
        admin_user.last_login = datetime.utcnow()
        session.add(admin_user)
        session.commit()

        # Create token
        token = create_admin_token(admin_user.username)

        logger.info(f"Admin login successful: {admin_user.username}")

        return AdminLoginResponse(
            access_token=token,
            expires_in=settings.ADMIN_JWT_EXPIRATION_MINUTES * 60,
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Login error: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal server error")


# ============================================================================
# METRICS ENDPOINTS
# ============================================================================

@router.get("/metrics/summary", response_model=AdminSummary)
async def get_metrics_summary(
    token: str = Query(...),
    session: Session = Depends(get_session),
):
    """Get admin dashboard summary metrics."""
    try:
        verify_admin_token(token)

        today = datetime.utcnow().date()
        thirty_days_ago = datetime.utcnow() - timedelta(days=30)

        # Total users
        total_users_stmt = select(func.count(User.user_id))
        total_users = session.exec(total_users_stmt).first() or 0

        # Active users today (users who have sessions or analyses created today)
        active_today_stmt = select(func.count(func.distinct(User.user_id))).where(
            Analysis.created_at >= datetime(today.year, today.month, today.day)
        )
        active_today = session.exec(active_today_stmt).first() or 0

        # Token usage last 30 days
        tokens_30d_stmt = select(func.sum(TokenUsage.total_tokens)).where(
            TokenUsage.created_at >= thirty_days_ago
        )
        tokens_30d = session.exec(tokens_30d_stmt).first() or 0

        # Token usage all time
        tokens_all_stmt = select(func.sum(TokenUsage.total_tokens))
        tokens_all = session.exec(tokens_all_stmt).first() or 0

        # Estimated costs
        cost_30d_stmt = select(func.sum(TokenUsage.estimated_cost_usd)).where(
            TokenUsage.created_at >= thirty_days_ago
        )
        cost_30d = float(session.exec(cost_30d_stmt).first() or 0)

        cost_all_stmt = select(func.sum(TokenUsage.estimated_cost_usd))
        cost_all = float(session.exec(cost_all_stmt).first() or 0)

        # Profit/Loss metrics
        profitable_trades_stmt = select(func.count(Trade.trade_id)).where(
            Trade.pnl > 0
        )
        users_in_profit = session.exec(profitable_trades_stmt).first() or 0

        total_profit_stmt = select(func.sum(Trade.pnl)).where(Trade.pnl > 0)
        total_profit = float(session.exec(total_profit_stmt).first() or 0)

        total_loss_stmt = select(func.sum(Trade.pnl)).where(Trade.pnl < 0)
        total_loss = float(session.exec(total_loss_stmt).first() or 0)

        # Trades today
        trades_today_stmt = select(func.count(Trade.trade_id)).where(
            Trade.entry_at >= datetime(today.year, today.month, today.day)
        )
        trades_today = session.exec(trades_today_stmt).first() or 0

        # Win rate
        total_closed_stmt = select(func.count(Trade.trade_id)).where(
            Trade.trade_status == TradeStatusEnum.CLOSED
        )
        total_closed = session.exec(total_closed_stmt).first() or 1

        win_rate_stmt = select(func.count(Trade.trade_id)).where(
            (Trade.trade_status == TradeStatusEnum.CLOSED) & (Trade.pnl > 0)
        )
        wins = session.exec(win_rate_stmt).first() or 0
        win_rate = (wins / total_closed * 100) if total_closed > 0 else 0

        return AdminSummary(
            total_users=total_users,
            active_today=active_today,
            total_tokens_30d=tokens_30d,
            total_tokens_all_time=tokens_all,
            estimated_cost_30d=cost_30d,
            estimated_cost_all_time=cost_all,
            users_in_profit=users_in_profit,
            total_profit=total_profit,
            total_loss=abs(total_loss),
            trades_today=trades_today,
            win_rate=win_rate,
            timestamp=datetime.utcnow(),
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get metrics summary: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Failed to fetch metrics")


@router.get("/metrics/users", response_model=List[UserMetric])
async def get_user_metrics(
    token: str = Query(...),
    limit: int = Query(50),
    session: Session = Depends(get_session),
):
    """Get per-user metrics."""
    try:
        verify_admin_token(token)

        # Get users with their stats
        users_stmt = select(User).order_by(User.created_at.desc()).limit(limit)
        users = session.exec(users_stmt).all()

        result = []
        for user in users:
            # Count analyses
            analyses_stmt = select(func.count(Analysis.analysis_id)).where(
                Analysis.user_id == user.user_id
            )
            analyses_count = session.exec(analyses_stmt).first() or 0

            # Count tokens
            tokens_stmt = select(func.sum(TokenUsage.total_tokens)).where(
                TokenUsage.user_id == user.user_id
            )
            tokens_used = session.exec(tokens_stmt).first() or 0

            # Calculate cost
            cost_stmt = select(func.sum(TokenUsage.estimated_cost_usd)).where(
                TokenUsage.user_id == user.user_id
            )
            estimated_cost = float(session.exec(cost_stmt).first() or 0)

            result.append(
                UserMetric(
                    user_id=user.user_id,
                    email=user.email,
                    full_name=user.full_name,
                    created_at=user.created_at,
                    analyses_count=analyses_count,
                    tokens_used=tokens_used,
                    estimated_cost=estimated_cost,
                )
            )

        return result

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get user metrics: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Failed to fetch user metrics")


@router.get("/metrics/tokens", response_model=List[TokenMetric])
async def get_token_metrics(
    token: str = Query(...),
    days: int = Query(30),
    session: Session = Depends(get_session),
):
    """Get daily token usage metrics for last N days."""
    try:
        verify_admin_token(token)

        result = []
        for i in range(days):
            date = (datetime.utcnow() - timedelta(days=i)).date()
            date_start = datetime(date.year, date.month, date.day)
            date_end = date_start + timedelta(days=1)

            # Sum tokens for the day
            tokens_stmt = select(func.sum(TokenUsage.total_tokens)).where(
                (TokenUsage.created_at >= date_start)
                & (TokenUsage.created_at < date_end)
            )
            total_tokens = session.exec(tokens_stmt).first() or 0

            # Sum cost
            cost_stmt = select(func.sum(TokenUsage.estimated_cost_usd)).where(
                (TokenUsage.created_at >= date_start)
                & (TokenUsage.created_at < date_end)
            )
            total_cost = float(session.exec(cost_stmt).first() or 0)

            # Count unique users
            users_stmt = select(func.count(func.distinct(TokenUsage.user_id))).where(
                (TokenUsage.created_at >= date_start)
                & (TokenUsage.created_at < date_end)
            )
            users_count = session.exec(users_stmt).first() or 0

            result.append(
                TokenMetric(
                    date=str(date),
                    total_tokens=total_tokens,
                    total_cost=total_cost,
                    users_count=users_count,
                )
            )

        return result

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get token metrics: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Failed to fetch token metrics")


# ============================================================================
# SERVER-SENT EVENTS (SSE) - LIVE UPDATES
# ============================================================================

@router.get("/events")
async def admin_events(token: str = Query(...)):
    """SSE endpoint for live metric updates."""
    try:
        verify_admin_token(token)

        async def event_generator():
            while True:
                try:
                    with Session(engine) as session:
                        # Get current metrics
                        today = datetime.utcnow().date()
                        thirty_days_ago = datetime.utcnow() - timedelta(days=30)

                        # Total users
                        total_users = session.exec(
                            select(func.count(User.user_id))
                        ).first() or 0

                        # Active today
                        active_today = session.exec(
                            select(func.count(func.distinct(User.user_id))).where(
                                Analysis.created_at >= datetime(today.year, today.month, today.day)
                            )
                        ).first() or 0

                        # Tokens 30 days
                        tokens_30d = session.exec(
                            select(func.sum(TokenUsage.total_tokens)).where(
                                TokenUsage.created_at >= thirty_days_ago
                            )
                        ).first() or 0

                        # Cost 30 days
                        cost_30d = float(
                            session.exec(
                                select(func.sum(TokenUsage.estimated_cost_usd)).where(
                                    TokenUsage.created_at >= thirty_days_ago
                                )
                            ).first() or 0
                        )

                        # Trades today
                        trades_today = session.exec(
                            select(func.count(Trade.trade_id)).where(
                                Trade.entry_at >= datetime(today.year, today.month, today.day)
                            )
                        ).first() or 0

                        # Profit/loss
                        total_profit = float(
                            session.exec(
                                select(func.sum(Trade.pnl)).where(Trade.pnl > 0)
                            ).first() or 0
                        )
                        total_loss = float(
                            session.exec(
                                select(func.sum(Trade.pnl)).where(Trade.pnl < 0)
                            ).first() or 0
                        )

                        data = {
                            "timestamp": datetime.utcnow().isoformat(),
                            "totalUsers": total_users,
                            "activeToday": active_today,
                            "tokens30d": tokens_30d,
                            "cost30d": cost_30d,
                            "tradesToday": trades_today,
                            "totalProfit": total_profit,
                            "totalLoss": abs(total_loss),
                        }

                        yield f"data: {json.dumps(data)}\n\n"

                except Exception as e:
                    logger.error(f"SSE error: {e}")
                    yield f"data: {json.dumps({'error': str(e)})}\n\n"

                # Wait 5 seconds before next update
                await asyncio.sleep(5)

        return StreamingResponse(
            event_generator(),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "X-Accel-Buffering": "no",
                "Connection": "keep-alive",
            },
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to start SSE: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Failed to start live updates")
