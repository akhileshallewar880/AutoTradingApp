# Login Connection Troubleshooting

## Issue
Clicking "Login with Zerodha" button doesn't work. You see these warnings (which are harmless):
```
W/WindowOnBackDispatcher: OnBackInvokedCallback is not enabled
```

## Root Cause
The backend API is not accessible from your phone at `192.168.31.208:8000`

## Solutions

### 1. Check Backend is Running on All Network Interfaces

Your uvicorn server might be running on `127.0.0.1` (localhost only), which makes it inaccessible from your phone.

**Stop your current server (Ctrl+C) and restart with:**

```bash
cd /Users/akhileshallewar/project_dev/AutoTradingApp
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

The `--host 0.0.0.0` makes it accessible from your local network!

### 2. Verify Your Mac's IP Address

Make sure `192.168.31.208` is your Mac's current IP:

```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

Look for something like `inet 192.168.31.208`

### 3. Check Firewall

Your Mac's firewall might be blocking connections:

1. Open **System Settings** → **Network** → **Firewall**
2. Make sure Python or allow incoming connections for port 8000

### 4. Test Backend from Phone's Browser

Open your phone's browser and go to:
```
http://192.168.31.208:8000/docs
```

If you see the FastAPI documentation, backend is accessible!

### 5. Verify App Has New IP

Since you changed the IP in `api_config.dart`, you need to hot restart the app:

**In the Flutter terminal, press: `R` (capital R for hot restart)**

## Quick Test Commands

**From your Mac:**
```bash
# Test locally
curl http://192.168.31.208:8000/api/v1/auth/login

# Should return: {"login_url": "https://kite.zerodha.com/connect/login?..."}
```

## Expected Flow After Fix

1. Tap "Login with Zerodha" 
2. Loading spinner appears
3. WebView opens with Zerodha login page
4. (If you see a SnackBar error, check the error message)

---

**Most likely fix:** Restart uvicorn with `--host 0.0.0.0`
