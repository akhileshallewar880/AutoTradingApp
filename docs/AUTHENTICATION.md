# Zerodha Kite Connect Authentication Guide

This guide explains how to authenticate and obtain an access token using the Kite Connect API.

## Authentication Flow

The Kite Connect authentication follows a 3-step OAuth-like flow:

### Step 1: Get Login URL
**Endpoint**: `GET /api/v1/auth/login`

This endpoint returns the Kite Connect login URL where users need to authenticate.

**Example Request**:
```bash
curl http://localhost:8000/api/v1/auth/login
```

**Example Response**:
```json
{
  "login_url": "https://kite.zerodha.com/connect/login?v=3&api_key=your_api_key",
  "message": "Redirect user to this URL to complete Zerodha login"
}
```

**Action**: Redirect the user to the `login_url` in their browser.

---

### Step 2: User Completes Login on Kite

After redirecting to the login URL:
1. User enters their Zerodha credentials
2. User authorizes your application
3. Zerodha redirects back to your configured `redirect_url` with a `request_token`

**Example Callback URL**:
```
https://your-app.com/callback?request_token=abc123xyz&status=success
```

Extract the `request_token` from the URL query parameters.

---

### Step 3: Exchange Request Token for Access Token
**Endpoint**: `POST /api/v1/auth/session`

Send the `request_token` to this endpoint to get the `access_token`.

**Example Request**:
```bash
curl -X POST http://localhost:8000/api/v1/auth/session \
  -H "Content-Type: application/json" \
  -d '{"request_token": "abc123xyz"}'
```

**Example Response**:
```json
{
  "access_token": "xyz789abc",
  "user_id": "XX0000",
  "user_name": "John Doe",
  "email": "john@example.com",
  "user_type": "individual",
  "broker": "ZERODHA",
  "exchanges": ["NSE", "NFO", "BSE"],
  "products": ["CNC", "NRML", "MIS"],
  "message": "Login successful. Use this access_token for all API requests"
}
```

**Important**: Store the `access_token` securely. Add it to your `.env` file:
```env
ZERODHA_ACCESS_TOKEN=xyz789abc
```

---

## Additional Endpoints

### Get User Profile
**Endpoint**: `GET /api/v1/auth/profile`

Fetch the logged-in user's profile details.

**Example Request**:
```bash
curl http://localhost:8000/api/v1/auth/profile
```

---

### Logout
**Endpoint**: `POST /api/v1/auth/logout`

Invalidate the current access token.

**Example Request**:
```bash
curl -X POST http://localhost:8000/api/v1/auth/logout
```

---

## Important Notes

1. **Redirect URL Configuration**: 
   - Configure your redirect URL in the [Kite Connect Developer Portal](https://developers.kite.trade/)
   - The redirect URL is where Zerodha will send the `request_token` after successful login

2. **Access Token Validity**:
   - Access tokens are valid until 6 AM the next day (IST)
   - You need to re-authenticate daily or handle token refresh in your app

3. **Security**:
   - Never expose your `api_secret` in client-side code
   - Store `access_token` securely
   - Use HTTPS in production

4. **Testing**:
   - You can test the flow using the Swagger UI at: `http://localhost:8000/docs`
   - Navigate to the "Authentication" section to try out the endpoints

---

## Complete Flow Example (Postman/cURL)

```bash
# Step 1: Get login URL
curl http://localhost:8000/api/v1/auth/login

# Step 2: Open the login_url in browser, login, and copy the request_token from callback URL

# Step 3: Exchange request_token for access_token
curl -X POST http://localhost:8000/api/v1/auth/session \
  -H "Content-Type: application/json" \
  -d '{"request_token": "YOUR_REQUEST_TOKEN_HERE"}'

# Step 4: Update your .env file with the access_token

# Step 5: Verify by fetching profile
curl http://localhost:8000/api/v1/auth/profile
```

---

## Troubleshooting

**Error: "Invalid or expired request_token"**
- Request tokens expire quickly (few minutes). Complete the flow immediately after getting the token.

**Error: "Failed to fetch profile"**
- Ensure you have set the `ZERODHA_ACCESS_TOKEN` in your `.env` file
- Check if the token is still valid (tokens expire at 6 AM IST)

**Error: "Checksum mismatch"**
- Verify your `ZERODHA_API_SECRET` is correct in the `.env` file
