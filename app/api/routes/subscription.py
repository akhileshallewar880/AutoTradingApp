"""
Subscription & usage routes.

GET  /api/v1/subscription/status   — current plan, usage counts, limits
GET  /api/v1/subscription/plans    — all available plans
POST /api/v1/subscription/activate — record a completed payment + activate plan
"""

import uuid as _uuid
from datetime import datetime, timedelta

from fastapi import APIRouter, HTTPException, Query
from app.core.logging import logger
from app.models.subscription_models import UsageStatusResponse, CreateSubscriptionRequest

router = APIRouter()


@router.get("/status", response_model=UsageStatusResponse)
async def get_usage_status(vt_user_id: str = Query(..., description="VanTrade user UUID")):
    """Return current plan, monthly usage counts, and limits for a user."""
    from app.storage.database import db
    try:
        status = db.get_usage_status(vt_user_id)
        return UsageStatusResponse(**status)
    except Exception as e:
        logger.error(f"[Subscription] get_usage_status failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/plans")
async def list_plans():
    """Return all available subscription plans."""
    from app.storage.database import db
    try:
        status = db.get_usage_status("__probe__")
        return {"plans": status.get("all_plans", [])}
    except Exception as e:
        logger.error(f"[Subscription] list_plans failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/activate")
async def activate_subscription(body: CreateSubscriptionRequest):
    """
    Record a completed payment and activate a paid plan for the user.
    Called after successful payment verification on the client.

    In production: verify the payment_id with the payment provider (Razorpay / Stripe)
    before activating. This stub trusts the client — add server-side verification here.
    """
    from app.storage.database import db
    if not db._ready:
        raise HTTPException(status_code=503, detail="Database not available")

    from sqlalchemy import text
    import asyncio, uuid as _uuid

    plan_durations = {"pro": 30, "elite": 30}   # days
    duration_days = plan_durations.get(body.plan_id, 30)
    expires_at = datetime.utcnow() + timedelta(days=duration_days)

    def _sync():
        with db._engine.connect() as conn:
            # Cancel any existing active subscription for this user
            conn.execute(text("""
                UPDATE vantrade_subscriptions
                   SET status = 'cancelled', updated_at = GETUTCDATE()
                 WHERE vt_user_id = :uid AND status = 'active'
            """), {"uid": body.vt_user_id})

            conn.execute(text("""
                INSERT INTO vantrade_subscriptions
                  (subscription_id, vt_user_id, plan_id, status, expires_at,
                   payment_provider, payment_id, amount_paid, created_at, updated_at)
                VALUES
                  (:sid, :uid, :plan, 'active', :expires,
                   :provider, :pid, :amount, GETUTCDATE(), GETUTCDATE())
            """), {
                "sid":      str(_uuid.uuid4()),
                "uid":      body.vt_user_id,
                "plan":     body.plan_id,
                "expires":  expires_at.isoformat(),
                "provider": body.payment_provider,
                "pid":      body.payment_id,
                "amount":   body.amount_paid,
            })
            conn.commit()

    loop = asyncio.get_event_loop()
    try:
        await loop.run_in_executor(None, _sync)
    except Exception as e:
        logger.error(f"[Subscription] activate failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to activate subscription: {e}")

    logger.info(f"[Subscription] Activated plan={body.plan_id} for vt_user_id={body.vt_user_id}")
    return {
        "status": "activated",
        "plan_id": body.plan_id,
        "expires_at": expires_at.isoformat(),
    }
