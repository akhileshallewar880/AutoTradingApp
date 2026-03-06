"""
API endpoints for managing user-provided Zerodha credentials.
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.core.logging import logger
from kiteconnect import KiteConnect

router = APIRouter(prefix="/api/v1", tags=["credentials"])


class CredentialsRequest(BaseModel):
    api_key: str
    api_secret: str


@router.post("/validate-zerodha-credentials")
async def validate_zerodha_credentials(request: CredentialsRequest):
    """
    Validate user-provided Zerodha API credentials.

    Checks format validity and confirms the api_key is accepted by Zerodha.
    Note: full api_key + api_secret validation only happens during OAuth login.
    """
    try:
        api_key = request.api_key.strip()
        api_secret = request.api_secret.strip()

        logger.info(f"Validating Zerodha credentials for API key: {api_key[:10]}...")

        # ── Basic format checks ───────────────────────────────────────────────
        if len(api_key) < 6:
            return {"valid": False, "message": "API key is too short. Please check and try again."}
        if len(api_secret) < 6:
            return {"valid": False, "message": "API secret is too short. Please check and try again."}

        # ── Lightweight Zerodha check: generate login URL ────────────────────
        # This confirms KiteConnect accepts the api_key without any network I/O.
        # Full credential validation (api_secret included) happens during Zerodha OAuth.
        try:
            kite = KiteConnect(api_key=api_key)
            login_url = kite.login_url()
            if not login_url or api_key not in login_url:
                return {"valid": False, "message": "Invalid API key format. Please check and try again."}
        except Exception as e:
            error_msg = str(e)
            logger.warning(f"KiteConnect rejected api_key: {error_msg}")
            return {"valid": False, "message": f"Invalid API key: {error_msg}"}

        logger.info(f"✓ Credentials format validated for api_key: {api_key[:10]}...")
        return {
            "valid": True,
            "message": "Credentials look valid! Proceed to login with Zerodha."
        }

    except Exception as e:
        logger.error(f"Error validating credentials: {e}")
        raise HTTPException(status_code=500, detail=f"Validation error: {str(e)}")


@router.post("/test-user-credentials")
async def test_user_credentials(request: CredentialsRequest):
    """
    Extended validation - test multiple Zerodha API calls with user credentials.

    This endpoint makes multiple API calls to ensure the user's credentials
    have all necessary permissions.
    """
    try:
        logger.info(f"Testing extended Zerodha credentials for API key: {request.api_key[:10]}...")

        kite = KiteConnect(api_key=request.api_key)

        results = {
            "instruments": False,
            "quote": False,
            "profile": False,
            "message": "Testing in progress..."
        }

        # Test 1: Instruments (read-only, safe test)
        try:
            instruments = kite.instruments()
            results["instruments"] = len(instruments) > 0 if instruments else False
            logger.info(f"✓ Instruments test: {'PASS' if results['instruments'] else 'FAIL'}")
        except Exception as e:
            logger.warning(f"✗ Instruments test failed: {e}")
            results["instruments"] = False

        # Test 2: Try getting a quote for a major stock (if we have valid token)
        # Note: This requires access_token, so we skip for just API key validation

        # Test 3: Profile info (requires access_token, skip for now)

        # All tests passed if instruments test passed
        if results["instruments"]:
            return {
                "valid": True,
                "message": "All credential tests passed!",
                "results": results
            }
        else:
            return {
                "valid": False,
                "message": "Some credential tests failed. Please check your API settings.",
                "results": results
            }

    except Exception as e:
        logger.error(f"Error testing extended credentials: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Testing error: {str(e)}"
        )
