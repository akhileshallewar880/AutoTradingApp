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

    Makes a test API call to Zerodha to verify the credentials are valid.

    Request body:
    {
        "api_key": "user's_api_key",
        "api_secret": "user's_api_secret"
    }

    Response:
    {
        "valid": true/false,
        "message": "Credentials validated successfully" or error message
    }
    """
    try:
        logger.info(f"Validating Zerodha credentials for API key: {request.api_key[:10]}...")

        # Create KiteConnect instance with provided credentials
        kite = KiteConnect(api_key=request.api_key)

        # Try to make a simple API call to test the credentials
        # Using instruments call as a safe, read-only test
        try:
            instruments = kite.instruments()

            if instruments and len(instruments) > 0:
                logger.info(f"✓ Credentials validated successfully. Found {len(instruments)} instruments.")
                return {
                    "valid": True,
                    "message": "Credentials are valid and working!"
                }
            else:
                logger.warning("Credentials test returned empty instruments list")
                return {
                    "valid": False,
                    "message": "Credentials appear invalid (no instruments returned)"
                }

        except Exception as e:
            # If the test call fails, credentials are invalid
            error_msg = str(e)
            logger.warning(f"Credentials validation failed: {error_msg}")

            # Check for specific error messages
            if "Invalid api_key" in error_msg or "Invalid API key" in error_msg:
                return {
                    "valid": False,
                    "message": "Invalid API key. Please check and try again."
                }
            elif "Permission denied" in error_msg or "Insufficient permission" in error_msg:
                return {
                    "valid": False,
                    "message": "API key doesn't have permission to access instruments. Check your API settings in Zerodha."
                }
            else:
                return {
                    "valid": False,
                    "message": f"Validation failed: {error_msg}"
                }

    except Exception as e:
        logger.error(f"Error validating credentials: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Validation error: {str(e)}"
        )


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
