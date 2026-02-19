# AI Trading App - Quick Start Guide

## 🚀 Running the App

### 1. Start Backend API
```bash
cd /Users/akhileshallewar/project_dev/AutoTradingApp
source venv/bin/activate  # if using virtual environment
uvicorn app.main:app --reload
```

Backend will run on `http://localhost:8000`

### 2. Run Flutter App
```bash
cd /Users/akhileshallewar/project_dev/AutoTradingApp/algotrading
flutter run
```

**Available devices:**
- Android Device: 23090RA98I
- macOS (desktop)
- Chrome (web)

## 📱 Using the App

### First Time Login
1. Tap "Login with Zerodha"
2. Enter Zerodha credentials in WebView
3. Complete 2FA
4. Auto-redirects to Home screen

### Generate Analysis
1. Go to Home → "Generate AI Analysis"
2. Select date (past year)
3. Choose stocks count (5-20)
4. Set risk % (0.5-5%)
5. Tap "Generate AI Analysis"

### Review & Execute
1. Review AI recommendations
2. Check P&L projections for each stock
3. Tap "Confirm & Execute"
4. Watch real-time execution progress

### View History
1. Go to Home → "View History"
2. See all past analyses
3. Pull to refresh

## 🔧 Troubleshooting

### "Cannot connect to backend"
- Check backend is running: `curl http://localhost:8000`
- For Android emulator: Use `10.0.2.2` instead of `localhost`
- Edit `lib/utils/api_config.dart` if needed

### "Login failed"
- Ensure Zerodha API credentials in `.env`
- Check internet connection
- Try clearing app data and login again

### Build fails
- Check disk space: `df -h /`
- Clean project: `flutter clean && flutter pub get`
- Clear Gradle cache if needed

## 📝 Important Files

- **Backend Config**: `/Users/akhileshallewar/project_dev/AutoTradingApp/.env`
- **API URL Config**: `algotrading/lib/utils/api_config.dart`
- **Full Walkthrough**: See artifacts folder

## ✅ Everything Ready!

All code is in place. Just run the commands above and you're good to go! 🎉
