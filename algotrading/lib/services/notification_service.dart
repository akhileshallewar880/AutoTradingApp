import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:flutter_timezone/flutter_timezone.dart';

// Opportunity alarm notification IDs (one per mode)
const _kAlarmIds = {799, 800, 801, 802};

/// Foreground tap handler — called when user taps a notification while app is open.
void _onNotificationTap(NotificationResponse response) {
  if (_kAlarmIds.contains(response.id)) {
    NotificationService.onAlarmTap?.call();
  }
}

/// Background / terminated tap handler — must be a top-level @pragma function.
@pragma('vm:entry-point')
void _onBgNotificationTap(NotificationResponse response) {
  if (_kAlarmIds.contains(response.id)) {
    NotificationService.onAlarmTap?.call();
  }
}

/// Central notification service for all in-app and background push notifications.
///
/// Four channels:
/// - [_orderChannel]      — Order execution updates (ORDER_PLACED, GTT_CREATED, FAILED, etc.)
/// - [_monitorChannel]    — Live monitoring commentary events (DANGER, WARNING, INFO)
/// - [_analysisChannel]   — Analysis lifecycle (complete, no trades found)
/// - [_opportunityChannel]— Auto-scanner alarm (fullScreenIntent, wakes screen + alarm sound)
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  /// Set this in main() to handle opportunity-alarm notification taps.
  static Future<void> Function()? onAlarmTap;

  final _plugin = FlutterLocalNotificationsPlugin();

  // Channel IDs
  static const _orderChannelId       = 'vantrade_orders';
  static const _monitorChannelId     = 'vantrade_monitor';
  static const _analysisChannelId    = 'vantrade_analysis';
  static const _opportunityChannelId = 'vantrade_opportunity';
  static const _reminderChannelId    = 'vantrade_login_reminder';

  // Auto-incrementing ID counters per channel
  int _orderId    = 1000;
  int _monitorId  = 2000;
  int _analysisId = 3000;

  /// Must be called once (e.g. in main()) before scheduling reminders.
  static Future<void> initializeTimezone() async {
    tz_data.initializeTimeZones();
    final tzInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
  }

  Future<void> initialize() async {
    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: _onBgNotificationTap,
    );

    // If the app was launched by tapping an alarm notification (cold start),
    // getNotificationAppLaunchDetails fires here — treat it the same as a tap.
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails != null &&
        launchDetails.didNotificationLaunchApp &&
        launchDetails.notificationResponse != null &&
        _kAlarmIds.contains(launchDetails.notificationResponse!.id)) {
      onAlarmTap?.call();
    }

    // Create Android notification channels
    await _createChannel(
      id: _orderChannelId,
      name: 'Order Execution',
      description: 'Notifies when trades are placed, GTT orders created, or execution fails.',
      importance: Importance.high,
      playSound: true,
    );
    await _createChannel(
      id: _monitorChannelId,
      name: 'Live Monitor Commentary',
      description: 'Live commentary and alerts from AI position monitoring.',
      importance: Importance.high,
      playSound: true,
    );
    await _createChannel(
      id: _analysisChannelId,
      name: 'Analysis Updates',
      description: 'Analysis completion and results notifications.',
      importance: Importance.defaultImportance,
      playSound: false,
    );

    await _createChannel(
      id: _reminderChannelId,
      name: 'Login Reminder',
      description: 'Daily weekday reminder to log in to VanTrade before market open.',
      importance: Importance.high,
      playSound: true,
    );

    // Reuse one plugin reference for all remaining Android-specific setup
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    // Opportunity alarm channel — max importance, custom sound, wakes screen.
    // audioAttributesUsage.alarm makes sound play through the ALARM audio
    // stream, bypassing silent/vibrate/DND modes just like a real alarm app.
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _opportunityChannelId,
        'Trade Opportunities',
        description:
            'Alarm notification when auto-scanner finds a trade opportunity. '
            'Wakes screen even when phone is locked.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('opportunity_alarm'),
        enableVibration: true,
        showBadge: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );

    // POST_NOTIFICATIONS permission (Android 13+)
    await android?.requestNotificationsPermission();

    // USE_FULL_SCREEN_INTENT permission (Android 14+, API 34+).
    // Without this the alarm notification fires but does NOT wake the screen
    // when it is locked/off — it sits silently in the notification shade.
    await android?.requestFullScreenIntentPermission();
  }

  /// Returns true if the app has the USE_FULL_SCREEN_INTENT permission granted.
  /// Always returns true on Android < 14 (permission not required there).
  Future<bool> hasFullScreenIntentPermission() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    return await androidPlugin?.canScheduleExactNotifications() ?? true;
  }

  Future<void> _createChannel({
    required String id,
    required String name,
    required String description,
    required Importance importance,
    required bool playSound,
  }) async {
    final channel = AndroidNotificationChannel(
      id,
      name,
      description: description,
      importance: importance,
      playSound: playSound,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  // ── Order execution notifications ─────────────────────────────────────────

  /// Fire a notification for an order execution event.
  ///
  /// [updateType] maps to icon/color in the notification body.
  Future<void> showOrderUpdate({
    required String stockSymbol,
    required String message,
    required String updateType,
  }) async {
    final icon = _orderIcon(updateType);
    await _show(
      id: _orderId++,
      title: '$icon $stockSymbol',
      body: message,
      channelId: _orderChannelId,
      importance: Importance.high,
      priority: Priority.high,
    );
  }

  /// Fire a summary notification when execution completes.
  Future<void> showExecutionComplete({
    required int completedCount,
    required int failedCount,
  }) async {
    final isSuccess = failedCount == 0;
    final title = isSuccess ? '✅ Orders Placed!' : '⚠️ Execution Finished';
    final body = isSuccess
        ? '$completedCount trade${completedCount == 1 ? '' : 's'} successfully placed.'
        : '$completedCount placed, $failedCount failed. Check the app for details.';
    await _show(
      id: _orderId++,
      title: title,
      body: body,
      channelId: _orderChannelId,
      importance: Importance.high,
      priority: Priority.high,
    );
  }

  // ── Live monitoring commentary notifications ───────────────────────────────

  /// Fire a notification for a live monitoring commentary event.
  ///
  /// [alertLevel] is one of: 'DANGER', 'WARNING', 'INFO'
  Future<void> showMonitorEvent({
    required String symbol,
    required String message,
    required String alertLevel,
    String? eventType,
  }) async {
    final icon = _monitorIcon(alertLevel);
    final title = '$icon VanTrade — $symbol';
    final body = eventType != null && eventType.isNotEmpty
        ? '[$eventType] $message'
        : message;
    await _show(
      id: _monitorId++,
      title: title,
      body: body,
      channelId: _monitorChannelId,
      importance:
          alertLevel == 'DANGER' ? Importance.max : Importance.high,
      priority: alertLevel == 'DANGER' ? Priority.max : Priority.high,
    );
  }

  /// Fire a notification when a monitored position is exited/closed.
  Future<void> showPositionClosed({
    required String symbol,
    required String status,
    double? pnl,
  }) async {
    final pnlStr =
        pnl != null ? ' | P&L: ${pnl >= 0 ? '+' : ''}₹${pnl.toStringAsFixed(0)}' : '';
    final title = status == 'HUMAN_NEEDED'
        ? '🚨 Action Required — $symbol'
        : '🏁 Position Closed — $symbol';
    final body = status == 'HUMAN_NEEDED'
        ? 'AI monitoring stopped. Manual exit required.$pnlStr'
        : 'Your $symbol position has been exited.$pnlStr';
    await _show(
      id: _monitorId++,
      title: title,
      body: body,
      channelId: _monitorChannelId,
      importance: Importance.max,
      priority: Priority.max,
    );
  }

  // ── Analysis notifications ─────────────────────────────────────────────────

  Future<void> showAnalysisComplete({
    required int stockCount,
    required String holdLabel,
  }) async {
    await _show(
      id: _analysisId++,
      title: '🔍 Analysis Complete',
      body: stockCount > 0
          ? 'Found $stockCount trade${stockCount == 1 ? '' : 's'} for $holdLabel. Tap to review.'
          : 'No suitable trades found for $holdLabel today.',
      channelId: _analysisChannelId,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
  }

  // ── Opportunity alarm (auto-scanner) ──────────────────────────────────────

  /// Fire a full-screen alarm notification when the auto-scanner finds a trade.
  ///
  /// Uses [fullScreenIntent] to wake the screen even when the device is locked.
  /// Sound: opportunity_alarm.mp3 (res/raw). Vibration pattern: alarm-like pulse.
  Future<void> showOpportunityAlarm({
    required String mode,     // 'STOCKS', 'NIFTY', 'BANKNIFTY'
    required String title,
    required String body,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _opportunityChannelId,
        'Trade Opportunities',
        importance: Importance.max,
        priority: Priority.max,
        // CATEGORY_ALARM lets fullScreenIntent bypass the USE_FULL_SCREEN_INTENT
        // runtime permission introduced in Android 14 (API 34).  Without this,
        // the notification fires but the screen never wakes on a locked phone.
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('opportunity_alarm'),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 400, 200, 400, 200, 800]),
        ticker: 'VanTrade — Trade Opportunity',
        styleInformation: BigTextStyleInformation(body),
        icon: '@mipmap/launcher_icon',
        channelShowBadge: true,
        autoCancel: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
    // Fixed ID per mode so repeated alerts replace the previous one
    final id = mode == 'NIFTY' ? 801 : mode == 'BANKNIFTY' ? 802 : 800;
    await _plugin.show(id, title, body, details);
  }

  // ── Test alarm (development / market-closed testing) ─────────────────────

  /// Cancels a previously scheduled test alarm (ID 799).
  Future<void> cancelTestAlarm() => _plugin.cancel(799);

  /// Schedules a full-screen alarm notification [delaySeconds] from now.
  /// The notification tap calls [onAlarmTap], which reads pending_opportunity
  /// from SharedPreferences and shows OpportunityAlarmScreen.
  Future<void> scheduleTestAlarm({int delaySeconds = 120}) async {
    // Cancel any previous test alarm
    await _plugin.cancel(799);

    final fireAt = tz.TZDateTime.now(tz.local)
        .add(Duration(seconds: delaySeconds));

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _opportunityChannelId,
        'Trade Opportunities',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('opportunity_alarm'),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 400, 200, 400, 200, 800]),
        ticker: 'VanTrade — Test Trade Opportunity',
        styleInformation: const BigTextStyleInformation(
            'NIFTY CE 24000 • Entry ₹120 • SL ₹78 • Target ₹204 — Tap to execute'),
        icon: '@mipmap/launcher_icon',
        channelShowBadge: true,
        autoCancel: true,
      ),
    );

    final canExact = await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.canScheduleExactNotifications() ??
        false;

    await _plugin.zonedSchedule(
      799, // fixed test alarm ID — also in _kAlarmIds
      '📈 TEST — Stock Opportunity Found',
      'RELIANCE BUY ₹2845 • INFY BUY ₹1620 • Tap to review & execute',
      fireAt,
      details,
      androidScheduleMode: canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  // ── Weekday login reminder (Mon–Fri 09:00) ────────────────────────────────

  /// Schedules 5 weekly recurring notifications — one per weekday — at 09:00.
  /// Safe to call multiple times; cancels previous reminders first.
  Future<void> scheduleWeekdayLoginReminders() async {
    // Cancel any previously scheduled reminders (IDs 900–904)
    for (int i = 900; i <= 904; i++) {
      await _plugin.cancel(i);
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _reminderChannelId,
        'Login Reminder',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/launcher_icon',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    // Monday=1 … Friday=5
    final weekdays = [
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    ];

    for (int i = 0; i < 5; i++) {
      // Use exact alarms if permitted (Android 13+ requires user to grant in
      // Settings > Special app access > Alarms & reminders), else inexact.
      final canExact = await _plugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.canScheduleExactNotifications() ??
          false;
      await _plugin.zonedSchedule(
        900 + i,
        '📈 Market opens soon!',
        'Log in to VanTrade and check today\'s trade opportunities.',
        _nextOccurrenceOf(weekdays[i], hour: 9),
        details,
        androidScheduleMode: canExact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexact,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  /// Returns the next [tz.TZDateTime] that falls on [weekday] at [hour]:00.
  tz.TZDateTime _nextOccurrenceOf(int weekday, {required int hour}) {
    final now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime candidate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);

    // Advance day-by-day until we land on the right weekday in the future
    while (candidate.weekday != weekday || !candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  // ── Internal helper ────────────────────────────────────────────────────────

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required Importance importance,
    required Priority priority,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelId,
        importance: importance,
        priority: priority,
        icon: '@mipmap/launcher_icon',
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    await _plugin.show(id, title, body, details);
  }

  String _orderIcon(String updateType) {
    switch (updateType) {
      case 'ORDER_PLACED':
        return '✅';
      case 'GTT_CREATED':
      case 'GTT_PLACED':
        return '🔔';
      case 'ERROR':
      case 'FAILED':
      case 'GTT_FAILED':
        return '❌';
      case 'SQUAREDOFF':
        return '🔄';
      case 'SQUAREOFF_FAILED':
        return '⚠️';
      case 'MARKET_CLOSED':
        return '🕐';
      default:
        return '📋';
    }
  }

  String _monitorIcon(String alertLevel) {
    switch (alertLevel) {
      case 'DANGER':
        return '🚨';
      case 'WARNING':
        return '⚠️';
      default:
        return '📊';
    }
  }
}
