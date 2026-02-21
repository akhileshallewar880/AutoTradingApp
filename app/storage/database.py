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
        self._load()

    def _load(self):
        # Load trades
        if os.path.exists(self.db_path):
            try:
                with open(self.db_path, "r") as f:
                    data = json.load(f)
                    self._trades = [Trade(**t) for t in data]
            except Exception as e:
                logger.error(f"Failed to load trades DB: {e}")
        
        # Load analyses
        if os.path.exists(self.analysis_path):
            try:
                with open(self.analysis_path, "r") as f:
                    data = json.load(f)
                    self._analyses = data.get("analyses", {})
                    self._execution_updates = data.get("execution_updates", {})
            except Exception as e:
                logger.error(f"Failed to load analysis DB: {e}")

    async def _save(self):
        try:
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, self._write_to_file)
        except Exception as e:
            logger.error(f"Failed to save DB, Please Check the Db Connection String !!: {e}")

    def _write_to_file(self):
        # Save trades
        with open(self.db_path, "w") as f:
            json.dump([t.model_dump(mode='json') for t in self._trades], f, indent=4)
        
        # Save analyses
        with open(self.analysis_path, "w") as f:
            json.dump({
                "analyses": self._analyses,
                "execution_updates": self._execution_updates
            }, f, indent=4, default=str)

    async def save_trade(self, trade: Trade):
        self._trades.append(trade)
        await self._save()
        logger.info(f"Trade saved: {trade.id}")

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
        await self._save()
        logger.info(f"Analysis saved: {analysis.analysis_id}")
    
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
        await self._save()
        logger.info(f"Execution update saved for {update.analysis_id}")
    
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

