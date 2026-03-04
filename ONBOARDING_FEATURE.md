# Onboarding Feature Guide - VanTrade

## Overview

The **Onboarding Screen** appears when users launch the app for the first time. It educates them about:
- What VanTrade does
- Why they need a Zerodha account
- How to get their Zerodha API credentials
- Links to complete the setup process

---

## User Experience Flow

```
App Launch
    ↓
Splash Screen (2.5 seconds)
    ↓
Check: Is onboarding_completed flag set?
    ├─ NO (First time) → Show Onboarding Screen
    │       ↓
    │   Step 1: Welcome to VanTrade
    │       ↓
    │   Step 2: You Need Zerodha Account
    │       ↓
    │   Step 3: Get API Credentials (with link to kite.trade)
    │       ↓
    │   Step 4: Ready to Start
    │       ↓
    │   User clicks "Continue to Login"
    │       ↓
    │   Flag set: onboarding_completed = true
    │       ↓
    │   Go to Login Screen
    │
    └─ YES (Already seen) → Go to Login/Home as normal
```

---

## Onboarding Screen Details

### 4-Step Flow

#### **Step 1: Welcome to VanTrade**
- Title: "🚀 Welcome to VanTrade"
- Shows app features:
  - AI-powered stock recommendations
  - Real-time technical analysis
  - Automated trade execution via Zerodha
  - Portfolio tracking and GTT orders
  - Intraday and swing trading support

#### **Step 2: You Need a Zerodha Account**
- Title: "🔐 You Need a Zerodha Account"
- Explains why:
  - Analyze real market data
  - Execute your trades securely
  - Track your positions
  - Set automated orders (GTT)
- Notes that Zerodha is free to join

#### **Step 3: Get Your API Credentials**
- Title: "🔑 Get Your API Credentials"
- Step-by-step guide:
  1. Go to https://kite.trade
  2. Log in with Zerodha account
  3. Click "Developer Console" (top right)
  4. Create new app or select existing
  5. Copy API Key
  6. Copy API Secret
- Includes button: **"Open Zerodha Developer Console"** (with URL launcher)
- Warning: Keep credentials secret

#### **Step 4: Ready to Start**
- Title: "✅ Ready to Start"
- Summarizes next steps:
  1. Click "Continue" button
  2. Login with Zerodha account
  3. Paste API credentials
  4. Start analyzing and trading
- Reminder: Can skip if credentials not ready yet

### UI Features

✅ **Progress Bar** - Shows which step user is on (4 segments)
✅ **Page Navigation** - Swipe or use Next/Back buttons
✅ **Direct Links** - "Open Zerodha Developer Console" button opens kite.trade in browser
✅ **Skip Option** - "Skip Onboarding" link to go straight to login
✅ **Responsive Design** - Works on all device sizes

---

## Implementation Details

### Files Modified/Created

**Created:**
- `lib/screens/onboarding_screen.dart` - Complete onboarding UI and logic

**Modified:**
- `lib/main.dart` - Added `/onboarding` route
- `lib/screens/splash_screen.dart` - Added onboarding check
- `pubspec.yaml` - Added `url_launcher` dependency

### How It Works

#### 1. First App Launch
```
SplashScreen._checkSession():
  ├─ Wait 2.5 seconds (show splash animation)
  ├─ Check SharedPreferences for 'onboarding_completed' flag
  ├─ If NOT found → Navigate to /onboarding
  └─ If found → Continue to login/home as normal
```

#### 2. Onboarding Screen
```
OnboardingScreen:
  ├─ Display 4-step PageView with progress indicator
  ├─ User swipes/clicks through steps
  ├─ Step 3 has button to open kite.trade
  ├─ Final step has "Continue to Login" button
  └─ On completion:
      ├─ Set onboarding_completed = true in SharedPreferences
      └─ Navigate to /login
```

#### 3. Subsequent Launches
```
After first time:
  ├─ Splash screen checks SharedPreferences
  ├─ Sees onboarding_completed = true
  ├─ Skips onboarding entirely
  └─ Goes directly to login/home
```

### Code Structure

```dart
// OnboardingScreen (4 pages)
├─ Step 1: Welcome
├─ Step 2: Zerodha Account
├─ Step 3: Get API Credentials (with link)
└─ Step 4: Ready to Start

// Controls
├─ Progress indicator (4 bars)
├─ PageView (swipeable)
├─ Navigation buttons (Back/Next)
├─ Skip button
└─ Open Link button (Step 3 only)
```

---

## Configuration

### Dependencies Added

```yaml
# pubspec.yaml
dependencies:
  url_launcher: ^6.1.11
```

Install:
```bash
flutter pub get
```

### SharedPreferences Usage

```dart
// Mark onboarding as complete
final prefs = await SharedPreferences.getInstance();
await prefs.setBool('onboarding_completed', true);

// Check if onboarding needed
final completed = prefs.getBool('onboarding_completed') ?? false;

// To reset onboarding (for testing)
await prefs.remove('onboarding_completed');
```

---

## Testing

### Test 1: First Launch (with onboarding)
```
1. Uninstall app completely
2. Install fresh
3. Run app
4. Should see splash screen (2.5 sec)
5. Then see onboarding screen (Step 1)
6. Can swipe/click through all 4 steps
7. Click "Continue to Login" on Step 4
8. See login screen
```

### Test 2: Subsequent Launches (skip onboarding)
```
1. Close app (don't uninstall)
2. Re-open app
3. Should see splash screen (2.5 sec)
4. Should go directly to login screen (no onboarding)
```

### Test 3: Skip Onboarding
```
1. Start fresh app
2. See onboarding Step 1
3. Click "Skip Onboarding" button
4. Should go directly to login
5. Flag set to true in SharedPreferences
6. Next launch should skip onboarding
```

### Test 4: Open Zerodha Link
```
1. See onboarding Step 3
2. Click "Open Zerodha Developer Console"
3. Should open https://kite.trade in browser
4. Can copy API credentials
5. Return to app
```

### Test 5: Swipe Navigation
```
1. On onboarding Step 1
2. Swipe right → should go to Step 2
3. Swipe left → should go back to Step 1
4. Can also use Next/Back buttons
```

---

## Resetting Onboarding (For Testing)

If you want to see onboarding again after first launch:

```dart
// In debug mode, run this code somewhere
final prefs = await SharedPreferences.getInstance();
await prefs.remove('onboarding_completed');
// Restart app - should show onboarding again
```

Or add a debug button in settings:

```dart
ElevatedButton(
  onPressed: () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('onboarding_completed');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Onboarding reset. Restart app.')),
    );
  },
  child: const Text('Reset Onboarding'),
)
```

---

## Customization Options

### Change Step Content
Edit the `steps` list in `onboarding_screen.dart`:

```dart
final List<OnboardingStep> steps = [
  OnboardingStep(
    title: 'Your Custom Title',
    description: 'Your custom description',
    content: 'Your content here',
    icon: Icons.your_icon,
  ),
  // ...
];
```

### Change Colors
Modify the theme:

```dart
// In onboarding_screen.dart
Colors.green[700]  // Primary color
Colors.green[50]   // Background color
Colors.grey[600]   // Text color
```

### Change Animations
Modify PageView transition:

```dart
PageView(
  // Change to BouncingScrollPhysics for different feel
  physics: const BouncingScrollPhysics(),
  // ...
);
```

---

## Analytics Integration (Optional)

Track onboarding completion:

```dart
// In onboarding_screen.dart, when user completes
Future<void> _markOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('onboarding_completed', true);

  // Optional: Track analytics
  // analytics.logEvent(name: 'onboarding_completed');
}
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Onboarding shows every time | SharedPreferences not saving properly. Check file permissions. |
| Link to Zerodha doesn't work | Ensure `url_launcher` is installed (`flutter pub get`). Check AndroidManifest.xml has INTERNET permission. |
| Onboarding doesn't appear on first launch | Check `splash_screen.dart` is checking SharedPreferences correctly. |
| Pages not swiping | Check `PageView` is not inside a `SingleChildScrollView` (conflicts with swipe). |

---

## Future Enhancements

- [ ] Add video tutorials in onboarding
- [ ] Allow users to skip individual steps
- [ ] Add swipe indicators ("Swipe →")
- [ ] Track user journey (which steps completed)
- [ ] A/B test different onboarding flows
- [ ] Add FAQ section in onboarding
- [ ] Support multiple languages
- [ ] Add animations between steps

---

## Deployment Notes

### Before Publishing to Play Store

✅ Test onboarding on multiple devices
✅ Verify Zerodha link opens correctly
✅ Ensure no crashes on back button during onboarding
✅ Test on low-end devices (slow internet)
✅ Verify all text is readable and well-formatted
✅ Test with accessibility tools (text size, screen readers)

### Play Store Listing

In the app description, mention:
> "First-time setup wizard guides you through getting Zerodha API credentials."

---

**Last Updated:** March 4, 2026
**Feature Status:** ✅ Complete & Ready for Production
