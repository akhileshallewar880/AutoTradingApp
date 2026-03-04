# Improved Onboarding & Credential Management Flow

**Status**: Design Document
**Version**: 2.0 (Updated with credentials in onboarding)

---

## 🔄 Updated Flow: Onboarding → Login → App

### Phase 1: Onboarding (First App Launch)

```
┌─────────────────────────────────────────────────────────────────┐
│              SPLASH SCREEN → ONBOARDING CHECK                   │
│  Check: isOnboardingCompleted() from SharedPreferences          │
│  ├─ If FALSE: Show onboarding                                   │
│  └─ If TRUE: Go to Login Screen                                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              ONBOARDING SCREEN (4-Step PageView)                │
│                                                                 │
│  ✅ Step 1: Welcome to VanTrade                                │
│     • Features overview                                         │
│     • What the app does                                         │
│     • Why you should use it                                     │
│     [Next]                                                      │
│                                                                 │
│  ✅ Step 2: Why Zerodha?                                       │
│     • Direct broker integration                                 │
│     • Real-time trading                                         │
│     • Safe & secure                                             │
│     [Back] [Next]                                               │
│                                                                 │
│  ✅ Step 3: Get API Credentials ⭐ NEW STEP MODIFIED          │
│     • Step-by-step instructions                                │
│     • [Open Zerodha Console] button                             │
│     • Your API Key:    [________________]                       │
│     • Your API Secret: [________________]                       │
│     • [Copy from Zerodha] link                                  │
│     • Help: How to find these?                                  │
│     [Validate Credentials]                                      │
│     [Back] [Next] (only enabled if validated)                  │
│                                                                 │
│  ✅ Step 4: Ready to Start ⭐ NEW FINAL STEP                   │
│     • Summary of setup                                          │
│     • "Your credentials are saved securely"                     │
│     • "You're all set! Let's trade!"                            │
│     [Complete Setup]                                            │
│                                                                 │
│  onboarding_completed = true (SharedPreferences)                │
│  saved_api_key = "encrypted_key" (SharedPreferences)            │
│  saved_api_secret = "encrypted_secret" (SharedPreferences)      │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              LOGIN SCREEN                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Welcome back!                                            │  │
│  │ We found your saved Zerodha credentials ✓              │  │
│  │                                                          │  │
│  │ [Login with Zerodha]  ← Uses saved credentials         │  │
│  │ [Use Different Creds] ← Change credentials             │  │
│  │ [Demo Mode]           ← Test without Zerodha            │  │
│  │                                                          │  │
│  │ Note: Your API credentials are stored securely         │  │
│  │ and are never sent to our servers.                      │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
            When user clicks "Login with Zerodha":
                              ↓
         Zerodha OAuth → Get user info → HOME SCREEN
```

---

## 🔑 Credential Validation Flow (Step 3 of Onboarding)

```
┌─────────────────────────────────────────────────────────────────┐
│         STEP 3: API CREDENTIAL INPUT & VALIDATION               │
│                                                                 │
│  User Interface:                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Get Your API Credentials                                 │  │
│  │                                                          │  │
│  │ 1. Open [Link: Zerodha Developer Console]              │  │
│  │    https://kite.trade/settings/api_console              │  │
│  │                                                          │  │
│  │ 2. Log in with your Zerodha credentials               │  │
│  │                                                          │  │
│  │ 3. Copy your API Key:                                  │  │
│  │    Paste here: [____________________]                  │  │
│  │    ℹ️ Looks like: "sk5hxzwm6j1qhrz1"                 │  │
│  │                                                          │  │
│  │ 4. Copy your API Secret:                               │  │
│  │    Paste here: [****________________]  🔒 (hidden)    │  │
│  │    ℹ️ Looks like: "ik0uni582wcn4zs..."               │  │
│  │                                                          │  │
│  │ ⓘ Never share these credentials with anyone!           │  │
│  │                                                          │  │
│  │ [Validate] [Skip for now]                              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Backend Validation:                                            │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ POST /api/validate-zerodha-credentials                  │  │
│  │                                                          │  │
│  │ Request: { api_key, api_secret }                        │  │
│  │                                                          │  │
│  │ 1. Instantiate KiteConnect(api_key, api_secret)        │  │
│  │ 2. Call kite.instruments() to test                      │  │
│  │ 3. If success: return {valid: true}                     │  │
│  │ 4. If fail: return {valid: false, error: "..."}        │  │
│  │                                                          │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Frontend Response Handling:                                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ ✅ VALID: Credentials Verified!                          │  │
│  │ • Save to SharedPreferences (encrypted)                  │  │
│  │ • Enable [Next] button                                   │  │
│  │ • Show green checkmark                                   │  │
│  │                                                          │  │
│  │ ❌ INVALID: Credentials Failed                           │  │
│  │ • Show error: "Invalid API Key or Secret"               │  │
│  │ • Show error: "Check Zerodha Developer Console"         │  │
│  │ • Disable [Next] button                                  │  │
│  │ • Allow retry                                            │  │
│  │                                                          │  │
│  │ ⏭️  SKIP FOR NOW:                                         │  │
│  │ • Save empty credentials                                 │  │
│  │ • Proceed to next step                                   │  │
│  │ • Will be asked to add credentials during login          │  │
│  │                                                          │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## ⚙️ NEW: Profile Settings Screen (Credential Management)

```
┌─────────────────────────────────────────────────────────────────┐
│              PROFILE/SETTINGS SCREEN (NEW)                      │
│                                                                 │
│  Accessed from: Home Screen → ☰ Menu → Settings/Profile        │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ 👤 Profile                                               │  │
│  ├──────────────────────────────────────────────────────────┤  │
│  │                                                          │  │
│  │ Account Information                                      │  │
│  │ ├─ Name: Akhilesh Allewar                              │  │
│  │ ├─ Email: akhilesh@example.com                          │  │
│  │ ├─ Zerodha ID: AB1234                                   │  │
│  │ └─ Member Since: March 4, 2026                          │  │
│  │                                                          │  │
│  ├──────────────────────────────────────────────────────────┤  │
│  │ API CREDENTIALS ⭐ NEW SECTION                          │  │
│  │                                                          │  │
│  │ Current Status: ✅ Valid & Active                       │  │
│  │                                                          │  │
│  │ API Key (masked): sk5hxzwm...qhrz1  ✓                  │  │
│  │ Last Verified: March 4, 2026 at 4:15 PM               │  │
│  │                                                          │  │
│  │ [Change API Credentials] button                         │  │
│  │                                                          │  │
│  │ When clicked:                                            │  │
│  │ • Opens modal to enter new credentials                  │  │
│  │ • Validates new credentials                             │  │
│  │ • Replaces old credentials                              │  │
│  │ • Confirms with success message                         │  │
│  │                                                          │  │
│  ├──────────────────────────────────────────────────────────┤  │
│  │ PRIVACY & SECURITY                                       │  │
│  │                                                          │  │
│  │ 🔒 Credentials are encrypted locally                    │  │
│  │    and never stored on our servers                      │  │
│  │                                                          │  │
│  │ [View Privacy Policy]                                   │  │
│  │ [View Terms of Service]                                 │  │
│  │                                                          │  │
│  ├──────────────────────────────────────────────────────────┤  │
│  │ ACTIONS                                                  │  │
│  │                                                          │  │
│  │ [Export Trade History]                                  │  │
│  │ [Download Performance Report]                           │  │
│  │ [Logout]                                                │  │
│  │ [Delete Account] (caution)                              │  │
│  │                                                          │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Change Credentials Modal (From Settings)

```
┌─────────────────────────────────────────────────────────────────┐
│          CHANGE API CREDENTIALS MODAL                           │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Update Your API Credentials                              │  │
│  │                                                          │  │
│  │ Need new credentials? Get them here:                     │  │
│  │ [Open Zerodha Console]                                   │  │
│  │                                                          │  │
│  │ New API Key:                                             │  │
│  │ [____________________]                                  │  │
│  │                                                          │  │
│  │ New API Secret:                                          │  │
│  │ [****____________________]  🔒                          │  │
│  │                                                          │  │
│  │ Current Password (for verification):                     │  │
│  │ [****____________________]                              │  │
│  │                                                          │  │
│  │ ⓘ You'll need to re-enter your password for security   │  │
│  │                                                          │  │
│  │ [Update] [Cancel]                                        │  │
│  │                                                          │  │
│  │ On Success:                                              │  │
│  │ ✅ "Credentials updated successfully!"                 │  │
│  │ (Automatically logs user out and redirects to login)    │  │
│  │                                                          │  │
│  │ On Failure:                                              │  │
│  │ ❌ "Invalid credentials. Please try again."            │  │
│  │                                                          │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📱 Updated Login Screen (After Onboarding)

```
┌─────────────────────────────────────────────────────────────────┐
│              LOGIN SCREEN (SCENARIO A: Has Credentials)         │
│                                                                 │
│  ✅ Credentials Found in Local Storage                         │
│                                                                 │
│  "Your Zerodha credentials are ready!"                          │
│                                                                 │
│  API Key (masked): sk5hxzwm...qhrz1  ✓                         │
│                                                                 │
│  [Login with Zerodha] ← Auto-uses saved credentials            │
│  [Use Different Creds] ← Change credentials                    │
│  [Demo Mode] ← Test without Zerodha                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              LOGIN SCREEN (SCENARIO B: No Credentials)          │
│                                                                 │
│  ❌ No Credentials Found                                       │
│                                                                 │
│  "We couldn't find your saved credentials"                      │
│                                                                 │
│  You can either:                                                │
│  [Add Credentials Now] → Opens credential input modal          │
│  [Demo Mode] → Test without Zerodha                            │
│                                                                 │
│  [Onboarding again?] → Restart onboarding flow                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Complete Updated Flow Diagram

```
┌──────────────┐
│ App Launch   │
└──────────────┘
       ↓
┌────────────────────────────┐
│ Check onboarding_completed  │
└────────────────────────────┘
       ↓
   YES or NO?
   /        \
  NO        YES
  ↓         ↓
┌─────────────────────────┐  ┌──────────────┐
│ ONBOARDING FLOW         │  │ LOGIN SCREEN │
│ (4 Steps)               │  └──────────────┘
│ ✅ Step 1: Welcome      │         ↓
│ ✅ Step 2: Why Zerodha  │  (Check if credentials exist)
│ ✅ Step 3: API Creds    │         ↓
│    - Input API Key      │    YES / NO
│    - Input API Secret   │    /      \
│    - Validate           │   YES    NO
│    - Save encrypted     │   ↓      ↓
│ ✅ Step 4: Ready        │  ┌─────────────────────────┐
│    - Confirm setup      │  │ Add Credentials Modal   │
│    - Mark complete      │  │ • Enter API Key         │
│                         │  │ • Enter API Secret      │
└─────────────────────────┘  │ • Validate              │
       ↓                      │ • Save                  │
   ✓ Complete                 └─────────────────────────┘
       ↓                              ↓
   onboarding = true          Credentials saved
       ↓                              ↓
       └──────────────┬───────────────┘
                      ↓
           Click "Login with Zerodha"
                      ↓
              Zerodha OAuth
                      ↓
              Get user info
                      ↓
           ✓ Login successful
                      ↓
           🏠 HOME SCREEN
```

---

## 💾 SharedPreferences Keys

| Key | Value | Encrypted | Notes |
|-----|-------|-----------|-------|
| `onboarding_completed` | true/false | ❌ No | Boolean flag |
| `zerodha_api_key` | "sk5hxzwm..." | ✅ Yes | Fernet encrypted |
| `zerodha_api_secret` | "ik0uni582..." | ✅ Yes | Fernet encrypted |
| `zerodha_user_id` | "AB1234" | ❌ No | From OAuth |
| `user_email` | "user@email.com" | ❌ No | From OAuth |
| `session_token` | "jwt_token..." | ✅ Yes | For API auth |
| `last_login` | "2026-03-04T16:15:00Z" | ❌ No | Timestamp |

---

## 🔐 Security Considerations

### Encryption
```python
# In Flutter/Dart (using fernet_encrypt package)
from cryptography.fernet import Fernet

# Generate key (user's device-specific key)
encryption_key = Fernet.generate_key()

# Encrypt credentials
cipher = Fernet(encryption_key)
encrypted_api_key = cipher.encrypt(api_key.encode())
encrypted_api_secret = cipher.encrypt(api_secret.encode())

# Save to SharedPreferences (encrypted value)
preferences.setString('zerodha_api_key', encrypted_api_key)
preferences.setString('zerodha_api_secret', encrypted_api_secret)
```

### Local Storage Only
- ✅ Credentials stored ONLY on user's device
- ✅ NEVER sent to VanTrade backend
- ✅ NEVER sent to any cloud service
- ✅ Encrypted at rest with Fernet

### When Credentials Are Used
```
1. User clicks "Login with Zerodha"
   ↓
2. App decrypts credentials from SharedPreferences
   ↓
3. App calls Zerodha OAuth with credentials
   ↓
4. Zerodha returns OAuth token
   ↓
5. App stores OAuth token (not raw credentials)
   ↓
6. Subsequent API calls use OAuth token
```

---

## 📋 Implementation Checklist

```
Frontend Changes:
[ ] Update onboarding_screen.dart
    [ ] Step 3: Add API credential input fields
    [ ] Add validation button
    [ ] Add help links to Zerodha console
    [ ] Save encrypted credentials to SharedPreferences

[ ] Create profile_settings_screen.dart
    [ ] Show current API Key (masked)
    [ ] Show last verified date
    [ ] Add "Change Credentials" button
    [ ] Change credentials modal
    [ ] Logout button
    [ ] Delete account option

[ ] Update login_screen.dart
    [ ] Check if credentials exist in SharedPreferences
    [ ] Show different UI based on credential status
    [ ] Add "Add Credentials Now" button if missing

[ ] Update routing in main.dart
    [ ] Route to /profile-settings
    [ ] Route to /change-credentials modal

[ ] Update auth_provider.dart
    [ ] Add saveApiCredentials() method
    [ ] Add getApiCredentials() method
    [ ] Add deleteApiCredentials() method
    [ ] Add validateApiCredentials() method
    [ ] Add updateApiCredentials() method

Backend Changes:
[ ] Update credentials.py
    [ ] POST /api/validate-zerodha-credentials (already exists)
    [ ] No changes needed for local encryption

Database Changes:
[ ] No changes (credentials not stored on backend)
```

---

## ✨ User Benefits

| Before | After |
|--------|-------|
| ❌ Login → API Settings (extra step) | ✅ Onboarding → Login (one flow) |
| ❌ Easy to forget credentials | ✅ Credentials saved from day 1 |
| ❌ No way to change credentials | ✅ Profile Settings to update |
| ❌ Credentials exposed in separate screen | ✅ Credentials secured during onboarding |
| ❌ Could lose credentials on logout | ✅ Credentials persist locally |

---

## 🎯 Summary

This improved flow:
1. ✅ **Simplifies user setup** - Everything in onboarding
2. ✅ **Reduces friction** - No extra screens after login
3. ✅ **Improves security** - Credentials encrypted locally, never sent to backend
4. ✅ **Adds flexibility** - Users can change credentials anytime in settings
5. ✅ **Better UX** - Clear error messages and validation feedback
6. ✅ **Professional** - Looks polished with credential management

