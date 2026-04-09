import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Checks and requests the three permissions required for the trade alarm to
/// wake the device screen when the app is backgrounded or the phone is locked.
///
/// 1. POST_NOTIFICATIONS   — show notifications at all (Android 13+)
/// 2. SCHEDULE_EXACT_ALARM — fire at the exact scheduled time (Android 12+)
/// 3. USE_FULL_SCREEN_INTENT — wake screen / show over lock screen (Android 14+)
class AlarmPermissionService {
  AlarmPermissionService._();
  static final AlarmPermissionService instance = AlarmPermissionService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  // ── Status checks ──────────────────────────────────────────────────────────

  /// Returns true when the device can show notifications at all.
  Future<bool> hasNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    final granted = await _android?.areNotificationsEnabled();
    return granted ?? true;
  }

  /// Returns true when the app can schedule exact alarms.
  /// Always true on Android < 12.
  Future<bool> hasExactAlarmPermission() async {
    if (!Platform.isAndroid) return true;
    final granted = await _android?.canScheduleExactNotifications();
    return granted ?? true;
  }

  static const _kFsiConfirmedKey = 'alarm_fsi_confirmed';

  /// Whether the user has manually confirmed full-screen intent was enabled.
  Future<bool> hasConfirmedFullScreenIntent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kFsiConfirmedKey) ?? false;
  }

  /// Call this when the user taps "Done" on the full-screen intent step.
  Future<void> markFullScreenIntentConfirmed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFsiConfirmedKey, true);
  }

  Future<AlarmPermissionStatus> checkAll() async {
    return AlarmPermissionStatus(
      notifications:   await hasNotificationPermission(),
      exactAlarm:      await hasExactAlarmPermission(),
      fullScreenIntent: await hasConfirmedFullScreenIntent(),
    );
  }

  // ── Permission requests ────────────────────────────────────────────────────

  /// Requests POST_NOTIFICATIONS permission via the OS dialog.
  Future<void> requestNotificationPermission() async {
    if (!Platform.isAndroid) return;
    await _android?.requestNotificationsPermission();
  }

  /// Opens the system settings page where the user grants "Alarms & reminders".
  /// On Android < 12 this is a no-op (permission not needed).
  Future<void> openExactAlarmSettings(String packageName) async {
    if (!Platform.isAndroid) return;
    try {
      final intent = AndroidIntent(
        action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
        data: 'package:$packageName',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    } catch (_) {
      // Fallback: open app details settings
      await _openAppDetails(packageName);
    }
  }

  /// Opens the system settings page for "Allow full-screen notifications".
  /// On Android < 14 this is a no-op (permission not needed).
  Future<void> openFullScreenIntentSettings(String packageName) async {
    if (!Platform.isAndroid) return;
    try {
      final intent = AndroidIntent(
        action: 'android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENT',
        data: 'package:$packageName',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    } catch (_) {
      // Fallback: open notification settings for the app
      await _openNotificationSettings(packageName);
    }
  }

  Future<void> _openNotificationSettings(String packageName) async {
    try {
      final intent = AndroidIntent(
        action: 'android.settings.APP_NOTIFICATION_SETTINGS',
        arguments: <String, dynamic>{
          'android.provider.extra.APP_PACKAGE': packageName,
        },
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    } catch (_) {
      await _openAppDetails(packageName);
    }
  }

  Future<void> _openAppDetails(String packageName) async {
    final intent = AndroidIntent(
      action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
      data: 'package:$packageName',
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    await intent.launch();
  }
}

class AlarmPermissionStatus {
  final bool notifications;
  final bool exactAlarm;
  /// Full-screen intent has no runtime check API — always false until the user
  /// confirms manually so the setup screen always shows step 3.
  final bool fullScreenIntent;

  const AlarmPermissionStatus({
    required this.notifications,
    required this.exactAlarm,
    this.fullScreenIntent = false,
  });

  bool get allGranted => notifications && exactAlarm && fullScreenIntent;
}
