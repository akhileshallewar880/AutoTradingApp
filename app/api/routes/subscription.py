"""
Subscription & usage routes.

GET  /api/v1/subscription/status   — current plan, usage counts, limits
GET  /api/v1/subscription/plans    — all available plans
POST /api/v1/subscription/activate — record a completed payment + activate plan
"""

import uuid as _uuid
from datetime import datetime, timedelta

from fastapi import APIRouter, HTTPException, Query, Header
from app.core.logging import logger
from app.core.config import get_settings
from app.models.subscription_models import UsageStatusResponse, CreateSubscriptionRequest

router = APIRouter()

# Promo provider name used during the beta 100%-off period
_PROMO_PROVIDER = "promo"

# Plans available for promo activation (maps plan → expected monthly price)
_PLAN_PRICES = {"pro": 99.0, "elite": 499.0}


def _verify_vt_user(authorization: str, expected_vt_user_id: str) -> str:
    """
    Decode the VT JWT from the Authorization header and verify the sub claim
    matches the requested vt_user_id. Returns the verified vt_user_id.
    Raises HTTPException 401/403 on failure.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")
    token = authorization.split(" ", 1)[1].strip()
    try:
        from jose import jwt as _jose_jwt, JWTError
        settings = get_settings()
        payload = _jose_jwt.decode(
            token, settings.VT_JWT_SECRET,
            algorithms=["HS256"],
            options={"verify_exp": True},
        )
        uid = payload.get("sub", "")
        if not uid:
            raise HTTPException(status_code=401, detail="Invalid token: missing sub claim")
        if uid != expected_vt_user_id:
            raise HTTPException(status_code=403, detail="Token does not match requested user")
        return uid
    except JWTError as e:
        raise HTTPException(status_code=401, detail=f"Invalid or expired token: {e}")


@router.get("/status", response_model=UsageStatusResponse)
async def get_usage_status(
    vt_user_id: str = Query(..., description="VanTrade user UUID"),
    authorization: str = Header(..., description="Bearer <vt_access_token>"),
):
    """Return current plan, monthly usage counts, and limits for a user."""
    _verify_vt_user(authorization, vt_user_id)
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
async def activate_subscription(
    body: CreateSubscriptionRequest,
    authorization: str = Header(..., description="Bearer <vt_access_token>"),
):
    """
    Activate a plan for the user after payment (or promo during beta).

    Security:
    - vt_user_id ownership is verified via the Bearer token.
    - Payment provider 'promo' is allowed during beta (amount_paid must be 0).
    - All other providers require server-side payment verification (add Razorpay
      verify_payment call here before going live with paid billing).
    """
    # ── 1. Verify the caller owns this vt_user_id ────────────────────────────
    _verify_vt_user(authorization, body.vt_user_id)

    # ── 2. Validate plan ─────────────────────────────────────────────────────
    if body.plan_id not in _PLAN_PRICES and body.plan_id != "free":
        raise HTTPException(status_code=400, detail=f"Unknown plan: {body.plan_id}")

    # ── 3. Payment verification ──────────────────────────────────────────────
    if body.payment_provider == _PROMO_PROVIDER:
        # Beta 100%-off promo: amount_paid must be exactly 0
        if (body.amount_paid or 0) != 0:
            raise HTTPException(
                status_code=400,
                detail="Promo activation requires amount_paid = 0",
            )
        logger.info(
            f"[Subscription] Promo activation: plan={body.plan_id} "
            f"payment_id={body.payment_id} vt_user_id={body.vt_user_id[:8]}..."
        )
    else:
        # Production path — add Razorpay / Stripe server-side verification here.
        # Example for Razorpay:
        #   import razorpay
        #   client = razorpay.Client(auth=(RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET))
        #   payment = client.payment.fetch(body.payment_id)
        #   assert payment["status"] == "captured"
        #   assert payment["amount"] >= expected_amount_in_paise
        raise HTTPException(
            status_code=501,
            detail="Paid billing is not yet enabled. Use the promo code during beta.",
        )

    from app.storage.database import db
    if not db._ready:
        raise HTTPException(status_code=503, detail="Database not available")

    from sqlalchemy import text
    import asyncio, uuid as _uuid

    plan_durations = {"pro": 30, "elite": 30}
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
