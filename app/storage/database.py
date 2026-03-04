"""
Database persistence layer using SQLModel and Azure SQL.
Replaces the JSON fallback storage with proper relational database.
"""

from typing import List, Optional
from sqlmodel import Session, select
from app.models.trade_models import Trade
from app.models.analysis_models import AnalysisResponse, ExecutionUpdate, ExecutionStatus
from app.models.db_models import (
    Analysis,
    StockRecommendation,
    ExecutionUpdate as DBExecutionUpdate,
    Order,
    GttOrder,
    Trade as DBTrade,
    TokenUsage,
    AnalysisStatusEnum,
)
from app.core.database import engine
from app.core.logging import logger
from datetime import datetime
import json


class Database:
    """
    SQLModel-based database layer using Azure SQL.
    All data is persisted to relational database tables.
    """

    def __init__(self):
        """Initialize database connection."""
        logger.info("✅ Using Azure SQL database for persistent storage")
        logger.info("Creating database tables if they don't exist...")
        try:
            # Create tables if they don't exist
            from app.models.db_models import SQLModel
            SQLModel.metadata.create_all(engine)
            logger.info("✅ Database tables verified/created successfully")
        except Exception as e:
            logger.error(f"Failed to create database tables: {e}", exc_info=True)
            raise

    async def save_analysis(self, analysis: AnalysisResponse):
        """Save analysis to database."""
        try:
            with Session(engine) as session:
                # Calculate portfolio metrics
                total_investment = sum(
                    s.entry_price * s.quantity for s in analysis.stocks
                )
                max_profit = sum(
                    (s.target_price - s.entry_price) * s.quantity
                    for s in analysis.stocks if s.action == "BUY"
                )
                max_loss = sum(
                    abs(s.stop_loss - s.entry_price) * s.quantity
                    for s in analysis.stocks
                )

                # Create analysis record
                # Note: analysis_id is auto-generated, user_id from request
                db_analysis = Analysis(
                    # analysis_id will be auto-generated (don't set it)
                    user_id=analysis.request.user_id,  # From AnalysisRequest
                    status=AnalysisStatusEnum.COMPLETED,
                    hold_duration_days=getattr(analysis, 'holdDurationDays', 0),
                    total_investment=total_investment,
                    max_profit=max_profit,
                    max_loss=max_loss,
                    created_at=datetime.utcnow(),
                    completed_at=datetime.utcnow(),
                )

                session.add(db_analysis)
                session.flush()  # Flush to get the auto-generated analysis_id

                # Create stock recommendation records
                for idx, stock in enumerate(analysis.stocks):
                    recommendation = StockRecommendation(
                        analysis_id=db_analysis.analysis_id,  # Use the generated ID
                        stock_symbol=stock.stock_symbol,
                        action=stock.action,
                        entry_price=stock.entry_price,
                        stop_loss=stock.stop_loss,
                        target_price=stock.target_price,
                        confidence_score=stock.confidence_score,
                        rationale=stock.ai_reasoning,
                        created_at=datetime.utcnow(),
                    )
                    session.add(recommendation)

                session.commit()
                logger.info(
                    f"✅ Analysis persisted to SQL (ID: {db_analysis.analysis_id}) "
                    f"with {len(analysis.stocks)} stocks"
                )
        except Exception as e:
            logger.error(f"Failed to save analysis: {e}", exc_info=True)
            raise

    async def get_analysis(self, analysis_id: str) -> Optional[dict]:
        """Retrieve analysis by ID from database."""
        try:
            with Session(engine) as session:
                statement = select(Analysis).where(
                    Analysis.analysis_id == analysis_id
                )
                analysis = session.exec(statement).first()

                if analysis:
                    logger.info(f"✅ Retrieved analysis from SQL: {analysis_id}")
                    return analysis.result_json
                else:
                    logger.warning(f"Analysis not found: {analysis_id}")
                    return None
        except Exception as e:
            logger.error(f"Failed to retrieve analysis: {e}", exc_info=True)
            raise

    async def update_analysis_status(self, analysis_id: str, status: str):
        """Update analysis status in database."""
        try:
            with Session(engine) as session:
                statement = select(Analysis).where(
                    Analysis.analysis_id == analysis_id
                )
                analysis = session.exec(statement).first()

                if analysis:
                    analysis.status = status
                    analysis.updated_at = datetime.utcnow()
                    session.add(analysis)
                    session.commit()
                    logger.info(f"✅ Updated analysis status: {analysis_id} -> {status}")
        except Exception as e:
            logger.error(f"Failed to update analysis status: {e}", exc_info=True)
            raise

    async def save_execution_update(self, update: ExecutionUpdate):
        """Save execution update to database."""
        try:
            with Session(engine) as session:
                db_update = DBExecutionUpdate(
                    analysis_id=update.analysis_id,
                    stock_symbol=update.stock_symbol,
                    update_type=update.updateType,
                    message=update.message,
                    order_id=getattr(update, 'order_id', None),
                    status=getattr(update, 'status', 'PENDING'),
                    timestamp=update.timestamp,
                    created_at=datetime.utcnow(),
                )

                session.add(db_update)
                session.commit()
                logger.info(
                    f"✅ Execution update persisted to SQL: "
                    f"{update.analysis_id} - {update.stock_symbol}"
                )
        except Exception as e:
            logger.error(f"Failed to save execution update: {e}", exc_info=True)
            raise

    async def get_execution_updates(
        self, analysis_id: str
    ) -> List[ExecutionUpdate]:
        """Get all execution updates for an analysis from database."""
        try:
            with Session(engine) as session:
                statement = select(DBExecutionUpdate).where(
                    DBExecutionUpdate.analysis_id == analysis_id
                ).order_by(DBExecutionUpdate.timestamp)

                updates = session.exec(statement).all()

                result = [
                    ExecutionUpdate(
                        analysis_id=u.analysis_id,
                        stock_symbol=u.stock_symbol,
                        updateType=u.update_type,
                        message=u.message,
                        timestamp=u.timestamp,
                    )
                    for u in updates
                ]

                logger.info(
                    f"✅ Retrieved {len(result)} execution updates from SQL "
                    f"for analysis: {analysis_id}"
                )
                return result
        except Exception as e:
            logger.error(f"Failed to retrieve execution updates: {e}", exc_info=True)
            raise

    async def get_all_analyses(self, limit: int = 50) -> List[dict]:
        """Get recent analyses from database."""
        try:
            with Session(engine) as session:
                statement = (
                    select(Analysis)
                    .order_by(Analysis.created_at.desc())
                    .limit(limit)
                )
                analyses = session.exec(statement).all()

                result = [analysis.result_json for analysis in analyses]

                logger.info(f"✅ Retrieved {len(result)} analyses from SQL")
                return result
        except Exception as e:
            logger.error(f"Failed to retrieve analyses: {e}", exc_info=True)
            raise

    async def save_trade(self, trade: Trade):
        """Save completed trade to database."""
        try:
            with Session(engine) as session:
                db_trade = DBTrade(
                    trade_id=trade.id,
                    symbol=trade.symbol,
                    action=trade.action,
                    entry_price=trade.entry_price,
                    exit_price=trade.exit_price,
                    quantity=trade.quantity,
                    pnl=trade.pnl,
                    pnl_percent=trade.pnl_percent,
                    entry_time=trade.entry_time,
                    exit_time=trade.exit_time,
                    status="CLOSED",
                    created_at=datetime.utcnow(),
                )

                session.add(db_trade)
                session.commit()
                logger.info(f"✅ Trade persisted to SQL: {trade.id}")
        except Exception as e:
            logger.error(f"Failed to save trade: {e}", exc_info=True)
            raise

    async def get_all_trades(self) -> List[Trade]:
        """Get all trades from database."""
        try:
            with Session(engine) as session:
                statement = select(DBTrade).order_by(DBTrade.entry_time.desc())
                trades = session.exec(statement).all()

                result = [
                    Trade(
                        id=t.trade_id,
                        symbol=t.symbol,
                        action=t.action,
                        entry_price=float(t.entry_price),
                        exit_price=float(t.exit_price) if t.exit_price else 0,
                        quantity=t.quantity,
                        pnl=float(t.pnl) if t.pnl else 0,
                        pnl_percent=float(t.pnl_percent) if t.pnl_percent else 0,
                        entry_time=t.entry_time,
                        exit_time=t.exit_time,
                    )
                    for t in trades
                ]

                logger.info(f"✅ Retrieved {len(result)} trades from SQL")
                return result
        except Exception as e:
            logger.error(f"Failed to retrieve trades: {e}", exc_info=True)
            raise

    async def get_monthly_trades(self, month: int, year: int) -> List[Trade]:
        """Get trades for a specific month from database."""
        try:
            with Session(engine) as session:
                statement = (
                    select(DBTrade)
                    .where(
                        (DBTrade.entry_time >= datetime(year, month, 1))
                        & (
                            DBTrade.entry_time
                            < (
                                datetime(year, month + 1, 1)
                                if month < 12
                                else datetime(year + 1, 1, 1)
                            )
                        )
                    )
                    .order_by(DBTrade.entry_time.desc())
                )
                trades = session.exec(statement).all()

                result = [
                    Trade(
                        id=t.trade_id,
                        symbol=t.symbol,
                        action=t.action,
                        entry_price=float(t.entry_price),
                        exit_price=float(t.exit_price) if t.exit_price else 0,
                        quantity=t.quantity,
                        pnl=float(t.pnl) if t.pnl else 0,
                        pnl_percent=float(t.pnl_percent) if t.pnl_percent else 0,
                        entry_time=t.entry_time,
                        exit_time=t.exit_time,
                    )
                    for t in trades
                ]

                logger.info(
                    f"✅ Retrieved {len(result)} trades for {month}/{year} from SQL"
                )
                return result
        except Exception as e:
            logger.error(f"Failed to retrieve monthly trades: {e}", exc_info=True)
            raise

    async def save_token_usage(
        self,
        user_id: Optional[int],
        analysis_id: Optional[str],
        model: str,
        prompt_tokens: int,
        completion_tokens: int,
        total_tokens: int,
        estimated_cost_usd: float,
    ):
        """Save OpenAI token usage to database."""
        try:
            from decimal import Decimal
            with Session(engine) as session:
                token_usage = TokenUsage(
                    user_id=user_id,
                    analysis_id=analysis_id,
                    model=model,
                    prompt_tokens=prompt_tokens,
                    completion_tokens=completion_tokens,
                    total_tokens=total_tokens,
                    estimated_cost_usd=Decimal(str(estimated_cost_usd)),
                    created_at=datetime.utcnow(),
                )
                session.add(token_usage)
                session.commit()
                logger.info(
                    f"✅ Token usage saved: {total_tokens} tokens "
                    f"(user_id={user_id}, analysis_id={analysis_id})"
                )
        except Exception as e:
            logger.error(f"Failed to save token usage: {e}", exc_info=True)


# Initialize database singleton
db = Database()
