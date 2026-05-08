from pydantic import BaseModel, Field
from typing import Optional

class LoginUrlResponse(BaseModel):
    login_url: str
    message: str = "Redirect user to this URL to complete Zerodha login"

class SessionRequest(BaseModel):
    request_token: str = Field(..., description="Request token received from Kite login callback")
    api_key: str = Field(..., description="User's Zerodha API key")
    api_secret: str = Field(..., description="User's Zerodha API secret")
    vt_user_id: Optional[str] = Field(None, description="VanTrade user UUID from phone auth — used to bind Zerodha account to one app user")

class SessionResponse(BaseModel):
    access_token: str
    api_key: str = Field(..., description="User's Zerodha API key (needed for dashboard API calls)")
    user_id: str
    zerodha_user_id: str = Field("", description="Zerodha client code (e.g. AB1234) — canonical account identifier")
    user_name: str
    email: str
    user_type: str
    broker: str
    exchanges: list
    products: list
    message: str = "Login successful. Use this access_token for all API requests"


class PhoneVerifyRequest(BaseModel):
    firebase_id_token: str = Field(
        ..., description="Firebase ID token obtained after OTP verification on client"
    )


class PhoneAuthResponse(BaseModel):
    vt_access_token: str
    vt_user_id: str
    phone_number: str
    is_new_user: bool
    message: str = "Phone verification successful"
