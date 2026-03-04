# Quick Start: Multi-Login Feature

## What Changed?

✅ **New Feature:** Each user now provides their own Zerodha API Key & Secret
✅ **Security:** Credentials stored locally on device, never on backend
✅ **Scalability:** No need to whitelist users in Zerodha Developer Console
✅ **Control:** Users have complete control over their API keys

---

## For End Users

### 1️⃣ Download and Open VanTrade App

### 2️⃣ Click "Login with Zerodha"
- You'll be redirected to Zerodha login page
- Enter your Zerodha username/password
- Authenticate with your 2FA (if enabled)

### 3️⃣ Get Your API Credentials
Go to https://kite.trade:
1. Click **Developer Console** (top right)
2. Select or create an app
3. Copy your **API Key** and **API Secret**

### 4️⃣ Enter Credentials in VanTrade
1. You'll see "Configure API" screen after login
2. Paste your **API Key** (first field)
3. Paste your **API Secret** (second field)
4. Click **"Validate & Save Credentials"**

### 5️⃣ Start Trading!
- ✅ Your credentials are validated
- ✅ Credentials saved securely on your device only
- ✅ Ready to use VanTrade for analysis and trading

---

## For Developers

### Setup

No additional backend setup needed! Just:

```bash
# 1. Ensure credentials.py is in app/api/routes/
# 2. Backend endpoint is automatically available at:
POST /api/validate-zerodha-credentials

# 3. Test it:
curl -X POST http://localhost:8000/api/validate-zerodha-credentials \
  -H "Content-Type: application/json" \
  -d '{"api_key": "your_key", "api_secret": "your_secret"}'
```

### Frontend Integration

All credential management is automatic in:
- `lib/providers/auth_provider.dart` — saves/loads/validates
- `lib/screens/api_settings_screen.dart` — user input screen

### Using User Credentials in Backend

When making API calls to Zerodha with user's credentials:

```python
from kiteconnect import KiteConnect

# Get user's API key from request (passed from frontend)
user_api_key = request.api_key

# Create KiteConnect with user's key
kite = KiteConnect(api_key=user_api_key)

# Make API calls as usual
quote = kite.quote(['NSE:SBIN'])
```

---

## Flow Diagram

```
┌─────────────────────────────────────────────────────────┐
│                     VanTrade App                        │
└─────────────────────────────────────────────────────────┘
                            │
                            ↓
                ┌─────────────────────────┐
                │  Login with Zerodha     │
                │  (OAuth)                │
                └─────────────────────────┘
                            │
                            ↓
                ┌─────────────────────────────────────┐
                │  Configure API Settings             │
                │  - Enter API Key                    │
                │  - Enter API Secret                 │
                └─────────────────────────────────────┘
                            │
                            ↓
        ┌───────────────────────────────────────────┐
        │     Backend Validation                    │
        │ POST /api/validate-zerodha-credentials   │
        │     ↓                                     │
        │  Test Zerodha API Call                  │
        │     ↓                                     │
        │  Return valid: true/false                │
        └───────────────────────────────────────────┘
                            │
                            ↓
        ┌───────────────────────────────────────────┐
        │  Save Credentials Securely on Device     │
        │  (SharedPreferences, encrypted)          │
        └───────────────────────────────────────────┘
                            │
                            ↓
        ┌───────────────────────────────────────────┐
        │  Home Screen - Ready to Trade             │
        │                                           │
        │  All Zerodha API calls now use user's    │
        │  personal API Key & Secret                │
        └───────────────────────────────────────────┘
```

---

## What This Enables

### Before (App-Wide Key)
```
Single API Key
    ↓
All Users → Same Zerodha API Key
    ↓
Limited to whitelisted users only
    ↓
Scaling issues: can't add users without manual work
```

### After (Multi-Login)
```
Each User Has Own Key
    ↓
User 1 → Their API Key ✅
User 2 → Their API Key ✅
User 3 → Their API Key ✅
    ↓
Any Zerodha user can signup
    ↓
Scales infinitely: no whitelist needed!
```

---

## Testing

### Test 1: Happy Path
1. Build app: `flutter run --release`
2. Click "Login with Zerodha"
3. Login with your Zerodha account
4. Enter valid API credentials
5. ✅ Should see success and redirect to home

### Test 2: Invalid Credentials
1. Follow steps 1-3 above
2. Enter fake/invalid API key
3. ❌ Should see error: "Invalid API key"
4. Go back and try again

### Test 3: Skip API Setup (Demo Mode)
1. From login screen, click "Test with Dummy Data"
2. ✅ Should skip API setup
3. Use app with demo data

---

## Deployment Checklist

Before deploying to Play Store:

```
Frontend:
[ ] api_settings_screen.dart created
[ ] auth_provider.dart updated with credential methods
[ ] api_service.dart updated with validation method
[ ] main.dart routes updated
[ ] login_webview_screen.dart redirects to /api-settings

Backend:
[ ] credentials.py endpoint working
[ ] main.py imports and registers credentials router
[ ] Backend running and accessible from mobile device
[ ] Test /api/validate-zerodha-credentials endpoint

Version:
[ ] pubspec.yaml version bumped (e.g., 1.0.0+2)
[ ] MULTI_LOGIN_SETUP.md in place
[ ] Privacy Policy updated (mention credential handling)

Testing:
[ ] Tested with real Zerodha account (demo/paper trading)
[ ] Tested error cases (invalid credentials)
[ ] Tested skip demo mode
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Validation failed" error | Ensure backend is running and endpoint accessible |
| "Invalid API key" | Check Zerodha Developer Console for correct key |
| "Permission denied" | Ensure API key has Quote + Order permissions in Zerodha |
| App crashes after saving | Check backend logs for Zerodha API errors |
| Credentials not saving | Ensure SharedPreferences package is configured |

---

## Next Steps

1. **Publish to Play Store** with this feature
2. **Monitor user feedback** on API setup flow
3. **Consider adding:**
   - Multiple API key support (switch between accounts)
   - Automatic credential refresh
   - Usage analytics per credential
   - Paper trading API key support

---

## Architecture Decision

### Why User-Provided Credentials?

✅ **Scalability** - Any Zerodha user can signup immediately
✅ **Security** - No shared credentials, each user isolated
✅ **Compliance** - User controls their own API access
✅ **Business** - No need to manually approve users
✅ **Trust** - Users know their credentials aren't on backend

### vs. Traditional SaaS Approach

| Aspect | Traditional | VanTrade (Multi-Login) |
|--------|-----------|----------------------|
| Credentials | App-wide shared key | Each user provides own |
| Onboarding | Manual whitelist | Automatic |
| Scaling | Limited by API quotas | Unlimited users |
| Security | Centralized risk | Decentralized, per-user |
| User Trust | Higher risk | Higher trust |

---

**Documentation Last Updated:** March 4, 2026
**Feature Version:** 1.0.0
