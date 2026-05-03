import hashlib
from datetime import datetime, timedelta
from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import RedirectResponse
from app.models.auth_models import (
    LoginUrlResponse, SessionRequest, SessionResponse,
    PhoneVerifyRequest, PhoneAuthResponse,
)
from app.services.zerodha_service import zerodha_service
from app.core.logging import logger
from app.core.config import get_settings

# ── Firebase Admin SDK — lazy import, safe if not installed ──────────────────
try:
    import firebase_admin
    from firebase_admin import auth as _fb_auth
    _FIREBASE_AVAILABLE = True
except ImportError:
    firebase_admin = None  # type: ignore
    _fb_auth = None        # type: ignore
    _FIREBASE_AVAILABLE = False

_firebase_app = None


def _get_firebase_app():
    """Lazy-initialise Firebase Admin once. Returns None if not configured."""
    global _firebase_app
    if not _FIREBASE_AVAILABLE:
        return None
    if _firebase_app is not None:
        return _firebase_app
    settings = get_settings()
    if not settings.FIREBASE_PROJECT_ID:
        return None
    try:
        try:
            _firebase_app = firebase_admin.get_app()
        except ValueError:
            _firebase_app = firebase_admin.initialize_app(
                options={"projectId": settings.FIREBASE_PROJECT_ID}
            )
        return _firebase_app
    except Exception as exc:
        logger.warning(f"[Firebase] init failed: {exc}")
        return None


def _create_vt_jwt(vt_user_id: str, phone_number: str) -> str:
    from jose import jwt as jose_jwt
    settings = get_settings()
    payload = {
        "sub": vt_user_id,
        "phone": phone_number,
        "type": "vt_phone",
        "exp": datetime.utcnow() + timedelta(hours=settings.VT_JWT_EXPIRY_HOURS),
    }
    return jose_jwt.encode(payload, settings.VT_JWT_SECRET, algorithm="HS256")


router = APIRouter()

@router.get("/login", response_model=LoginUrlResponse)
async def get_login_url(api_key: str = Query(...)):
    """
    Step 1: Get Kite Connect login URL.
    Accepts user's API key to generate login URL with their registered Kite Connect app.
    Redirect the user to this URL to complete the Zerodha login.
    After successful login, Zerodha will redirect to your configured redirect_url with a request_token.
    """
    try:
        login_url = zerodha_service.get_login_url_with_api_key(api_key)
        return LoginUrlResponse(login_url=login_url)
    except Exception as e:
        logger.error(f"Failed to generate login URL: {e}")
        raise HTTPException(status_code=500, detail="Failed to generate Zerodha login URL")

@router.post("/session", response_model=SessionResponse)
async def create_session(session_request: SessionRequest):
    """
    Step 2: Exchange request_token for access_token.
    After user completes login on Kite, you'll receive a request_token in the callback URL.
    POST that request_token (along with api_key and api_secret) here to get the access_token and user details.

    The access_token should be stored securely and used for all subsequent API calls.
    """
    try:
        session_data = await zerodha_service.generate_session_with_credentials(
            session_request.request_token,
            session_request.api_key,
            session_request.api_secret
        )

        # Derive a stable user_id from the api_key (no DB needed)
        user_id = hashlib.sha256(session_request.api_key.encode()).hexdigest()[:16]

        return SessionResponse(
            access_token=session_data["access_token"],
            api_key=session_request.api_key,
            user_id=user_id,
            user_name=session_data["user_name"],
            email=session_data["email"],
            user_type=session_data["user_type"],
            broker=session_data["broker"],
            exchanges=session_data["exchanges"],
            products=session_data["products"]
        )
    except Exception as e:
        logger.error(f"Session creation failed: {e}")
        raise HTTPException(
            status_code=400,
            detail=f"Failed to create session. Invalid or expired request_token. Error: {str(e)}"
        )

@router.get("/profile")
async def get_user_profile():
    """
    Get the logged-in user's profile.
    Requires valid access_token to be set in ZerodhaService.
    """
    try:
        profile = await zerodha_service.get_profile()
        return {"status": "success", "data": profile}
    except Exception as e:
        logger.error(f"Failed to fetch profile: {e}")
        raise HTTPException(
            status_code=401,
            detail="Failed to fetch profile. Please login first or check if access_token is valid."
        )

@router.get("/callback")
async def zerodha_callback(request: Request):
    """
    Redirect URL registered in Kite Connect developer portal.
    Forwards all query params (request_token, action, status) to the Angular frontend.
    Flutter WebView intercepts before reaching here; browsers are redirected to the web app.
    """
    settings = get_settings()
    query_string = str(request.url.query)
    redirect_url = f"{settings.FRONTEND_URL}/login?{query_string}"
    return RedirectResponse(url=redirect_url, status_code=302)

@router.get("/validate-token")
async def validate_token(
    api_key: str = Query(..., description="User's Zerodha API key"),
    access_token: str = Query(..., description="Zerodha access token to validate"),
):
    """
    Lightweight endpoint to check if a Zerodha access token is still valid.
    Returns 200 if valid, 401 if expired or invalid.
    Used by the Flutter app on startup to avoid sending users to /home with a dead session.
    """
    try:
        from kiteconnect import KiteConnect
        import asyncio
        kite = KiteConnect(api_key=api_key)
        kite.set_access_token(access_token)
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, kite.profile)
        return {"valid": True}
    except Exception as e:
        logger.warning(f"Token validation failed: {e}")
        raise HTTPException(
            status_code=401,
            detail="Session expired. Please login to Zerodha again."
        )


@router.post("/logout")
async def logout():
    """
    Logout and invalidate the current access_token.
    """
    try:
        await zerodha_service.invalidate_session()
        return {"status": "success", "message": "Logged out successfully"}
    except Exception as e:
        logger.error(f"Logout failed: {e}")
        raise HTTPException(status_code=500, detail=f"Logout failed: {str(e)}")


@router.post("/phone/verify", response_model=PhoneAuthResponse)
async def verify_phone_token(body: PhoneVerifyRequest):
    """
    Exchange a Firebase ID token (issued after OTP success on client) for a VanTrade JWT.
    Creates or retrieves the user record in vantrade_users.

    Flow:
      1. Client completes Firebase phone OTP → receives Firebase ID token
      2. POST that token here
      3. We verify it with Firebase Admin, upsert user in DB, return VT JWT
    """
    app = _get_firebase_app()
    if app is None:
        raise HTTPException(
            status_code=503,
            detail="Phone authentication is not configured on this server. "
                   "Set FIREBASE_PROJECT_ID in your environment.",
        )

    try:
        decoded = _fb_auth.verify_id_token(
            body.firebase_id_token, app=app, check_revoked=True
        )
    except firebase_admin.auth.RevokedIdTokenError:
        raise HTTPException(status_code=401, detail="Firebase token has been revoked")
    except firebase_admin.auth.UserDisabledError:
        raise HTTPException(status_code=403, detail="Firebase account is disabled")
    except Exception as exc:
        logger.warning(f"[Firebase] token verify failed: {exc}")
        raise HTTPException(status_code=401, detail="Invalid or expired Firebase ID token")

    firebase_uid: str = decoded.get("uid", "")
    phone_number: str = decoded.get("phone_number", "")
    if not firebase_uid or not phone_number:
        raise HTTPException(
            status_code=422,
            detail="Firebase token is missing uid or phone_number claim",
        )

    from app.storage.database import db

    try:
        result = await db.upsert_user_by_firebase_uid(
            firebase_uid=firebase_uid,
            phone_number=phone_number,
            phone_verified_at=datetime.utcnow().isoformat(),
        )
    except Exception as exc:
        logger.error(f"[PhoneAuth] DB upsert failed: {exc}", exc_info=True)
        raise HTTPException(status_code=500, detail="Failed to save user record")

    vt_token = _create_vt_jwt(result["vt_user_id"], phone_number)
    logger.info(
        f"[PhoneAuth] {'New' if result['is_new_user'] else 'Returning'} user: "
        f"phone={phone_number}, vt_user_id={result['vt_user_id']}"
    )
    return PhoneAuthResponse(
        vt_access_token=vt_token,
        vt_user_id=result["vt_user_id"],
        phone_number=phone_number,
        is_new_user=result["is_new_user"],
    )
