from fastapi import APIRouter, HTTPException
from app.models.auth_models import LoginUrlResponse, SessionRequest, SessionResponse
from app.services.zerodha_service import zerodha_service
from app.core.logging import logger

router = APIRouter()

@router.get("/login", response_model=LoginUrlResponse)
async def get_login_url():
    """
    Step 1: Get Kite Connect login URL.
    Redirect the user to this URL to complete the Zerodha login.
    After successful login, Zerodha will redirect to your configured redirect_url with a request_token.
    """
    try:
        login_url = zerodha_service.get_login_url()
        return LoginUrlResponse(login_url=login_url)
    except Exception as e:
        logger.error(f"Failed to generate login URL: {e}")
        raise HTTPException(status_code=500, detail="Failed to generate login URL")

@router.post("/session", response_model=SessionResponse)
async def create_session(session_request: SessionRequest):
    """
    Step 2: Exchange request_token for access_token.
    After user completes login on Kite, you'll receive a request_token in the callback URL.
    POST that request_token here to get the access_token and user details.
    
    The access_token should be stored securely and used for all subsequent API calls.
    """
    try:
        session_data = await zerodha_service.generate_session(session_request.request_token)
        
        return SessionResponse(
            access_token=session_data["access_token"],
            user_id=session_data["user_id"],
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
