from typing import List, Optional
from app.models.trade_models import Trade
from app.models.analysis_models import AnalysisResponse, ExecutionUpdate, ExecutionStatus
from app.core.logging import logger
import json
import os
import asyncio
from datetime import datetime

class Database:
    def __init__(self, db_path: str = "data/trades.json", analysis_path: str = "data/analyses.json"):
        self.db_path = db_path
        self.analysis_path = analysis_path

        # Ensure data directory exists
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        os.makedirs(os.path.dirname(self.analysis_path), exist_ok=True)

        self._trades: List[Trade] = []
        self._analyses: dict = {}  # analysis_id -> AnalysisResponse
        self._execution_updates: dict = {}  # analysis_id -> List[ExecutionUpdate]

        logger.info(
            f"⚠️  Using JSON fallback storage (not production-ready). "
            f"Trades: {db_path}, Analyses: {analysis_path}"
        )
        logger.info(
            f"⚠️  For persistent storage, configure Azure SQL in .env and update app/storage/database.py"
        )
        self._load()

    def _load(self):
        # Load trades
        if os.path.exists(self.db_path):
            try:
                with open(self.db_path, "r") as f:
                    data = json.load(f)
                    self._trades = [Trade(**t) for t in data]
                    logger.info(f"✅ Loaded {len(self._trades)} trades from {self.db_path}")
            except Exception as e:
                logger.error(f"Failed to load trades from {self.db_path}: {e}")
        else:
            logger.info(f"No existing trades file at {self.db_path} (will create on first save)")

        # Load analyses
        if os.path.exists(self.analysis_path):
            try:
                with open(self.analysis_path, "r") as f:
                    data = json.load(f)
                    self._analyses = data.get("analyses", {})
                    self._execution_updates = data.get("execution_updates", {})
                    logger.info(
                        f"✅ Loaded {len(self._analyses)} analyses and "
                        f"{sum(len(v) for v in self._execution_updates.values())} execution updates "
                        f"from {self.analysis_path}"
                    )
            except Exception as e:
                logger.error(f"Failed to load analyses from {self.analysis_path}: {e}")
        else:
            logger.info(f"No existing analyses file at {self.analysis_path} (will create on first save)")

    async def _save(self):
        try:
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, self._write_to_file)
        except Exception as e:
            logger.error(
                f"❌ Database save failed - data may be lost! "
                f"This is using fallback JSON storage. "
                f"Please configure Azure SQL for persistent storage. "
                f"Error: {e}",
                exc_info=True
            )
            # Re-raise to alert the caller
            raise

    def _write_to_file(self):
        try:
            # Ensure directory exists
            os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
            os.makedirs(os.path.dirname(self.analysis_path), exist_ok=True)

            # Save trades
            with open(self.db_path, "w") as f:
                json.dump([t.model_dump(mode='json') for t in self._trades], f, indent=4)
            logger.debug(f"Trades saved to {self.db_path} ({len(self._trades)} records)")

            # Save analyses
            with open(self.analysis_path, "w") as f:
                json.dump({
                    "analyses": self._analyses,
                    "execution_updates": self._execution_updates
                }, f, indent=4, default=str)
            logger.debug(
                f"Analyses saved to {self.analysis_path} "
                f"({len(self._analyses)} analyses, "
                f"{sum(len(v) for v in self._execution_updates.values())} updates)"
            )
        except Exception as e:
            logger.error(f"Failed to write to database files: {e}", exc_info=True)
            raise

    async def save_trade(self, trade: Trade):
        self._trades.append(trade)
        logger.debug(f"Trade added to memory: {trade.id}")
        await self._save()
        logger.info(f"✅ Trade persisted: {trade.id} (total: {len(self._trades)})")

    async def get_all_trades(self) -> List[Trade]:
        return self._trades

    async def get_monthly_trades(self, month: int, year: int) -> List[Trade]:
        return [
            t for t in self._trades 
            if t.entry_time.month == month and t.entry_time.year == year
        ]
    
    async def save_analysis(self, analysis: AnalysisResponse):
        """Save analysis to database."""
        self._analyses[analysis.analysis_id] = analysis.model_dump(mode='json')
        logger.debug(
            f"Analysis added to memory: {analysis.analysis_id} "
            f"with {len(analysis.stocks)} stocks"
        )
        await self._save()
        logger.info(f"✅ Analysis persisted: {analysis.analysis_id} (total: {len(self._analyses)})")
    
    async def get_analysis(self, analysis_id: str) -> Optional[dict]:
        """Retrieve analysis by ID."""
        return self._analyses.get(analysis_id)
    
    async def update_analysis_status(self, analysis_id: str, status: str):
        """Update analysis status."""
        if analysis_id in self._analyses:
            self._analyses[analysis_id]["status"] = status
            await self._save()
    
    async def save_execution_update(self, update: ExecutionUpdate):
        """Save execution update."""
        if update.analysis_id not in self._execution_updates:
            self._execution_updates[update.analysis_id] = []

        self._execution_updates[update.analysis_id].append(update.model_dump(mode='json'))
        logger.debug(
            f"Execution update added to memory for {update.analysis_id}: "
            f"{update.stock_symbol} - {update.update_type}"
        )
        await self._save()
        total_updates = sum(len(v) for v in self._execution_updates.values())
        logger.info(
            f"✅ Execution update persisted for {update.analysis_id} "
            f"(total: {total_updates} updates)"
        )
    
    async def get_execution_updates(self, analysis_id: str) -> List[ExecutionUpdate]:
        """Get all execution updates for an analysis."""
        updates_data = self._execution_updates.get(analysis_id, [])
        return [ExecutionUpdate(**u) for u in updates_data]
    
    async def get_all_analyses(self, limit: int = 50) -> List[dict]:
        """Get recent analyses."""
        analyses_list = list(self._analyses.values())
        # Sort by created_at descending
        analyses_list.sort(key=lambda x: x.get("created_at", ""), reverse=True)
        return analyses_list[:limit]

db = Database()

