"""
Database stub — no-op implementation for DB-free deployment.
All persistent data comes from Zerodha API directly.
"""
from app.core.logging import logger
from typing import List, Optional


class Database:
    """No-op database stub. App runs without any database."""

    async def save_analysis(self, analysis):
        pass

    async def get_analysis(self, analysis_id: str) -> Optional[dict]:
        return None

    async def update_analysis_status(self, analysis_id: str, status: str):
        pass

    async def save_execution_update(self, update):
        pass

    async def get_execution_updates(self, analysis_id: str) -> List:
        return []

    async def get_all_analyses(self, limit: int = 50) -> List[dict]:
        return []

    async def save_trade(self, trade):
        pass

    async def get_all_trades(self) -> List:
        return []

    async def get_monthly_trades(self, month: int, year: int) -> List:
        return []

    async def save_token_usage(self, *args, **kwargs):
        pass


db = Database()
