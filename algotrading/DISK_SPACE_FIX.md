# 🚨 CRITICAL: Disk Space Issue

## Problem
Your Mac's disk is **FULL**. The Flutter build is failing with:
```
Failed to create parent directory... no space left on device
```

## Check Disk Space
```bash
df -h /
```

## Quick Fixes (Run these commands)

### 1. Clear Gradle Cache (Recommended - Safe)
```bash
rm -rf ~/.gradle/caches
rm -rf ~/.gradle/wrapper
```

### 2. Clear Flutter Build Cache
```bash
cd algotrading
flutter clean
rm -rf build/
rm -rf ~/.pub-cache/_temp
```

### 3. Clear Dart/Flutter Cache
```bash
rm -rf ~/.pub-cache/hosted
flutter pub cache repair
```

### 4. Clear Android Build Cache
```bash
cd algotrading/android
./gradlew clean
rm -rf .gradle
```

### 5. Check Large Files (Find what's taking space)
```bash
# Find large files in home directory
du -sh ~/* | sort -rh | head -10

# Find large files in project
du -sh ~/project_dev/* | sort -rh | head -10
```

### 6. Other Common Large Directories to Clean
```bash
# Clear system logs
sudo rm -rf /var/log/*

# Clear user cache
rm -rf ~/Library/Caches/*

# Clear Xcode derived data (if you use Xcode)
rm -rf ~/Library/Developer/Xcode/DerivedData/*

# Clear old Flutter SDK caches
rm -rf ~/flutter/bin/cache/artifacts
```

## After Cleaning

Once you've freed up space:

```bash
cd algotrading
flutter clean
flutter pub get
flutter run
```

## Permanent Solution

1. **Delete old/unused Flutter projects**
2. **Clear Downloads folder**
3. **Empty Trash**
4. **Remove old Docker images/containers** (if you use Docker)
5. **Use Disk Utility to check storage**

## Minimum Space Needed

For Flutter development, you need:
- **At least 10-15 GB free** for builds
- Gradle caches can grow to 2-5 GB
- Flutter SDK needs ~2 GB

---

**Try the Gradle cache cleanup first, it's the safest and will likely free several GB!**
