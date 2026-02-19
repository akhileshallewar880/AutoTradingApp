from pydantic import BaseModel, Field

class LoginUrlResponse(BaseModel):
    login_url: str
    message: str = "Redirect user to this URL to complete Zerodha login"

class SessionRequest(BaseModel):
    request_token: str = Field(..., description="Request token received from Kite login callback")

class SessionResponse(BaseModel):
    access_token: str
    user_id: str
    user_name: str
    email: str
    user_type: str
    broker: str
    exchanges: list
    products: list
    message: str = "Login successful. Use this access_token for all API requests"
