# Multi-Login Setup Guide - VanTrade

## Overview

VanTrade now supports **multi-user login with user-provided Zerodha API credentials**. This allows each user to:

1. Use their own Zerodha API key and secret
2. Have complete control over their trading account
3. Ensure maximum security (no shared app-wide credentials)

---

## How It Works

### User Flow

```
User Opens App
    ↓
Sees Login Screen
    ↓
Clicks "Login with Zerodha"
    ↓
Zerodha OAuth Login
    ↓
Returns to app with session token
    ↓
Redirected to "API Settings" screen
    ↓
User pastes their Zerodha API Key & Secret
    ↓
App validates credentials with backend
    ↓
Credentials saved securely on device
    ↓
User can now trade with their own API key ✅
```

---

## For Users: How to Get API Credentials

### Step 1: Go to Zerodha Developer Console

1. Open https://kite.trade
2. Log in with your Zerodha username/password
3. Click **Developer Console** (top right corner)

### Step 2: Create or Select an App

**If creating new app:**
- Click **"Create New App"**
- **App Name**: "My VanTrade" (or any name)
- **Product Type**: Web (or appropriate type)
- **Redirect URL**: Leave as default or set to your app's domain
- Click **Create**

**If using existing app:**
- Select your app from the list
- Click on it to open settings

### Step 3: Copy Credentials

In the app settings, you'll see:
- **API Key** (e.g., `sk5hxzwm6j1qhrz1`)
- **API Secret** (e.g., `abc123def456ghi789...`)

⚠️ **KEEP THESE SECRET** - Never share with anyone!

### Step 4: Paste in VanTrade App

1. After Zerodha OAuth login, you'll see the "Configure API" screen
2. Paste your **API Key** in the first field
3. Paste your **API Secret** in the second field
4. Click **"Validate & Save Credentials"**
5. ✅ Done! You're ready to trade

---

## For Developers: Backend Implementation

### Endpoint: Validate Credentials

**Route:** `POST /api/validate-zerodha-credentials`

**Request:**
```json
{
  "api_key": "sk5hxzwm6j1qhrz1",
  "api_secret": "your_secret_here"
}
```

**Response (Valid):**
```json
{
  "valid": true,
  "message": "Credentials are valid and working!"
}
```

**Response (Invalid):**
```json
{
  "valid": false,
  "message": "Invalid API key. Please check and try again."
}
```

### How Validation Works

1. Backend receives user-provided API key and secret
2. Creates temporary KiteConnect instance
3. Makes read-only API call (fetch instruments)
4. If successful → credentials are valid
5. Returns success to frontend
6. Frontend saves credentials securely on device

### Security Considerations

- ✅ Credentials never stored on backend (only validated)
- ✅ Credentials encrypted in device storage (SharedPreferences)
- ✅ OAuth token handled separately from API credentials
- ✅ User maintains full control of their credentials
- ⚠️ Never log credentials to files
- ⚠️ Clear credentials on logout

---

## Files Modified/Created

### Frontend (Flutter)

**New Files:**
- `lib/screens/api_settings_screen.dart` - API credentials input screen
- `lib/screens/login_webview_screen.dart` - Updated to redirect to API settings

**Modified Files:**
- `lib/providers/auth_provider.dart` - Added credential management methods
- `lib/services/api_service.dart` - Added credential validation method
- `lib/main.dart` - Added API settings route

**Methods Added to AuthProvider:**
```dart
// Retrieve saved credentials from device storage
Future<Map<String, String>?> getSavedApiCredentials()

// Validate credentials with backend
Future<bool> validateApiCredentials(String apiKey, String apiSecret)

// Save credentials securely
Future<void> saveApiCredentials(String apiKey, String apiSecret)

// Clear credentials on logout
Future<void> clearApiCredentials()
```

### Backend (FastAPI)

**New Files:**
- `app/api/routes/credentials.py` - Credential validation endpoints

**Endpoints:**
```python
@router.post("/api/validate-zerodha-credentials")
async def validate_zerodha_credentials(request: CredentialsRequest)
```

**Modified Files:**
- `app/main.py` - Imported and registered credentials router

---

## Testing the Flow

### Test as User

1. **Build and run the app:**
   ```bash
   cd algotrading
   flutter run --release
   ```

2. **On login screen:**
   - Click "Login with Zerodha"
   - Log in with your Zerodha account
   - Get redirected to "Configure API" screen

3. **On API settings screen:**
   - Enter your API key (from Zerodha Developer Console)
   - Enter your API secret
   - Click "Validate & Save Credentials"
   - Should see ✅ success message

4. **Redirect to home screen:**
   - App is now ready to use
   - All future API calls will use your personal credentials

### Test with Demo Data (No API Needed)

- On login screen, click "Test with Dummy Data"
- Skip the API settings step
- Use demo data to explore features

---

## Troubleshooting

### ❌ Error: "Invalid API key"
- Check your API key spelling (case-sensitive)
- Verify you copied the entire key
- Ensure the API key is for the right Zerodha app

### ❌ Error: "Permission denied"
- The API key exists but doesn't have required permissions
- Go to Zerodha Developer Console
- Check that your app has "Quote" and "Order" permissions enabled
- Regenerate API key if needed

### ❌ Error: "Network error / Connection failed"
- Ensure backend server is running: `python app/main.py`
- Check that the API endpoint is accessible
- Verify backend URL in `lib/utils/api_config.dart`

### ❌ Credentials saved but app crashes on analysis
- Ensure backend is using the correct credentials to call Zerodha API
- Check backend logs for Zerodha API errors
- Verify that your Zerodha account has active subscriptions for quotes/orders

---

## Advanced: Using Credentials in API Calls

### On Frontend (Already Handled)
Credentials are retrieved and passed to backend automatically in requests.

### On Backend (When Implementing Features)

When you make Zerodha API calls in the backend, use the user's provided API key:

```python
from kiteconnect import KiteConnect

# User's API key from frontend
user_api_key = request.api_key  # from credentials endpoint

# Create session with user's key
kite = KiteConnect(api_key=user_api_key)

# Make API calls
quote = kite.quote(['NSE:SBIN'])
```

---

## Future Enhancements

- [ ] Store multiple API keys per user (switch between accounts)
- [ ] API key rotation/refresh mechanism
- [ ] Encrypted credential backup to cloud
- [ ] Rate limiting per API key
- [ ] Usage analytics per credential
- [ ] Support for sandbox/paper trading API keys

---

## Security Best Practices

1. **Always use HTTPS** in production
2. **Never log API credentials** to files or console
3. **Validate user input** before using with Zerodha API
4. **Rate limit** the validation endpoint (prevent brute force)
5. **Use environment variables** for app-level credentials (not user credentials)
6. **Rotate credentials** if compromised
7. **Audit logs** for credential usage

---

## Support

For issues with:
- **Zerodha API**: https://support.zerodha.com
- **VanTrade App**: Contact support@vantrade.app
- **Getting API Key**: https://kite.trade/docs/api/connect/v3/

---

**Last Updated:** March 4, 2026
**Version:** 1.0.0
