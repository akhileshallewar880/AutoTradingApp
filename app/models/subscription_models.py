from typing import Optional, List
from pydantic import BaseModel


class PlanModel(BaseModel):
    plan_id: str
    name: str
    price_monthly: float
    analyses_per_month: Optional[int]   # None = unlimited
    executions_per_month: Optional[int]
    features: Optional[str]             # JSON array string


class UsageModel(BaseModel):
    period: str
    analyses_count: int
    executions_count: int
    last_analysis_at: Optional[str]
    last_execution_at: Optional[str]


class UsageStatusResponse(BaseModel):
    plan: dict
    subscription: dict
    usage: UsageModel
    limits: dict
    analyses_remaining: Optional[int]   # None = unlimited
    executions_remaining: Optional[int]
    is_over_analysis_limit: bool
    is_over_execution_limit: bool
    all_plans: List[dict]


class CreateSubscriptionRequest(BaseModel):
    vt_user_id: str
    plan_id: str
    payment_provider: Optional[str] = None
    payment_id: Optional[str] = None
    amount_paid: Optional[float] = None
