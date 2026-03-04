from pydantic import BaseModel, Field

class LoginUrlResponse(BaseModel):
    login_url: str
    message: str = "Redirect user to this URL to complete Zerodha login"

class SessionRequest(BaseModel):
    request_token: str = Field(..., description="Request token received from Kite login callback")
    api_key: str = Field(..., description="User's Zerodha API key")
    api_secret: str = Field(..., description="User's Zerodha API secret")

class SessionResponse(BaseModel):
    access_token: str
    api_key: str = Field(..., description="User's Zerodha API key (needed for dashboard API calls)")
    user_id: str
    user_name: str
    email: str
    user_type: str
    broker: str
    exchanges: list
    products: list
    message: str = "Login successful. Use this access_token for all API requests"
