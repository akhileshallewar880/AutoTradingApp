import 'dart:typed_data';
import 'dart:ui' show Color;
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

  // ── Brand color palette ────────────────────────────────────────────────────
  static const _colorGreen  = Color(0xFF00D26A);
  static const _colorRed    = Color(0xFFE53935);
  static const _colorPurple = Color(0xFF9B59B6);
  static const _colorOrange = Color(0xFFFF9800);
  static const _colorBlue   = Color(0xFF2196F3);
  static const _colorTeal   = Color(0xFF00BCD4);

  static const _largeIcon =
      DrawableResourceAndroidBitmap('launcher_icon');

  // ── Initialise ─────────────────────────────────────────────────────────────

  /// Must be called once (e.g. in main()) before scheduling reminders.
  static Future<void> initializeTimezone() async {
    tz_data.initializeTimeZones();
    final tzInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
  }

  Future<void> initialize() async {
    const androidInit =
        AndroidInitializationSettings('@mipmap/launcher_icon');
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
      description:
          'Notifies when trades are placed, GTT orders created, or execution fails.',
      importance: Importance.high,
      playSound: true,
    );
    await _createChannel(
      id: _monitorChannelId,
      name: 'Live Monitor Commentary',
      description:
          'Live commentary and alerts from AI position monitoring.',
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
      description:
          'Daily weekday reminder to log in to VanTrade before market open.',
      importance: Importance.high,
      playSound: true,
    );

    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

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

    await android?.requestNotificationsPermission();
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

  /// Fire a rich notification for an order execution event.
  ///
  /// [updateType] drives the emoji prefix, accent color, and vibration.
  Future<void> showOrderUpdate({
    required String stockSymbol,
    required String message,
    required String updateType,
  }) async {
    final icon   = _orderIcon(updateType);
    final color  = _orderColor(updateType);
    final isErr  = updateType == 'FAILED' ||
        updateType == 'GTT_FAILED' ||
        updateType == 'ERROR';
    await _show(
      id: _orderId++,
      title: '$icon $stockSymbol',
      body: message,
      channelId: _orderChannelId,
      importance: isErr ? Importance.max : Importance.high,
      priority: isErr ? Priority.max : Priority.high,
      color: color,
      vibrate: isErr,
    );
  }

  /// Fire a summary notification when execution completes.
  Future<void> showExecutionComplete({
    required int completedCount,
    required int failedCount,
  }) async {
    final isSuccess = failedCount == 0;
    final title =
        isSuccess ? '✅ Orders Placed!' : '⚠️ Execution Finished';
    final body = isSuccess
        ? '$completedCount trade${completedCount == 1 ? '' : 's'} '
            'successfully placed.'
        : '$completedCount placed, $failedCount failed. '
            'Check the app for details.';
    await _show(
      id: _orderId++,
      title: title,
      body: body,
      channelId: _orderChannelId,
      importance: Importance.high,
      priority: Priority.high,
      color: isSuccess ? _colorGreen : _colorOrange,
      vibrate: !isSuccess,
    );
  }

  // ── Live monitoring commentary notifications ───────────────────────────────

  Future<void> showMonitorEvent({
    required String symbol,
    required String message,
    required String alertLevel,
    String? eventType,
  }) async {
    final icon  = _monitorIcon(alertLevel);
    final color = alertLevel == 'DANGER'
        ? _colorRed
        : alertLevel == 'WARNING'
            ? _colorOrange
            : _colorBlue;
    final title = '$icon VanTrade — $symbol';
    final body  = eventType != null && eventType.isNotEmpty
        ? '[$eventType] $message'
        : message;
    await _show(
      id: _monitorId++,
      title: title,
      body: body,
      channelId: _monitorChannelId,
      importance: alertLevel == 'DANGER' ? Importance.max : Importance.high,
      priority: alertLevel == 'DANGER' ? Priority.max : Priority.high,
      color: color,
      vibrate: alertLevel == 'DANGER',
    );
  }

  Future<void> showPositionClosed({
    required String symbol,
    required String status,
    double? pnl,
  }) async {
    final pnlStr = pnl != null
        ? ' | P&L: ${pnl >= 0 ? '+' : ''}₹${pnl.toStringAsFixed(0)}'
        : '';
    final isHuman = status == 'HUMAN_NEEDED';
    final color = isHuman
        ? _colorRed
        : (pnl != null && pnl >= 0)
            ? _colorGreen
            : _colorRed;
    await _show(
      id: _monitorId++,
      title: isHuman
          ? '🚨 Action Required — $symbol'
          : '🏁 Position Closed — $symbol',
      body: isHuman
          ? 'AI monitoring stopped. Manual exit required.$pnlStr'
          : 'Your $symbol position has been exited.$pnlStr',
      channelId: _monitorChannelId,
      importance: Importance.max,
      priority: Priority.max,
      color: color,
      vibrate: true,
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
          ? 'Found $stockCount trade${stockCount == 1 ? '' : 's'} for '
              '$holdLabel. Tap to review.'
          : 'No suitable trades found for $holdLabel today.',
      channelId: _analysisChannelId,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      color: stockCount > 0 ? _colorGreen : _colorBlue,
    );
  }

  // ── Opportunity alarm (auto-scanner) ──────────────────────────────────────

  Future<void> showOpportunityAlarm({
    required String mode,
    required String title,
    required String body,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _opportunityChannelId,
        'Trade Opportunities',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        color: _colorGreen,
        icon: '@drawable/ic_notification',
        largeIcon: _largeIcon,
        subText: 'VanTrade',
        channelShowBadge: true,
        playSound: true,
        sound:
            const RawResourceAndroidNotificationSound('opportunity_alarm'),
        enableVibration: true,
        vibrationPattern:
            Int64List.fromList([0, 400, 200, 400, 200, 800]),
        ticker: 'VanTrade — Trade Opportunity',
        styleInformation: BigTextStyleInformation(body),
        autoCancel: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
    final id =
        mode == 'NIFTY' ? 801 : mode == 'BANKNIFTY' ? 802 : 800;
    await _plugin.show(id, title, body, details);
  }

  // ── Test alarm ────────────────────────────────────────────────────────────

  Future<void> cancelTestAlarm() => _plugin.cancel(799);

  Future<void> scheduleTestAlarm({int delaySeconds = 120}) async {
    await _plugin.cancel(799);

    final fireAt =
        tz.TZDateTime.now(tz.local).add(Duration(seconds: delaySeconds));

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _opportunityChannelId,
        'Trade Opportunities',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        color: _colorGreen,
        icon: '@drawable/ic_notification',
        largeIcon: _largeIcon,
        subText: 'VanTrade',
        channelShowBadge: true,
        playSound: true,
        sound:
            const RawResourceAndroidNotificationSound('opportunity_alarm'),
        enableVibration: true,
        vibrationPattern:
            Int64List.fromList([0, 400, 200, 400, 200, 800]),
        ticker: 'VanTrade — Test Trade Opportunity',
        styleInformation: const BigTextStyleInformation(
            'NIFTY CE 24000 • Entry ₹120 • SL ₹78 • Target ₹204 — '
            'Tap to execute'),
        autoCancel: true,
      ),
    );

    final canExact = await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.canScheduleExactNotifications() ??
        false;

    await _plugin.zonedSchedule(
      799,
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

  Future<void> scheduleWeekdayLoginReminders() async {
    for (int i = 900; i <= 904; i++) {
      await _plugin.cancel(i);
    }

    final weekdays = [
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    ];

    for (int i = 0; i < 5; i++) {
      final canExact = await _plugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.canScheduleExactNotifications() ??
          false;

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _reminderChannelId,
          'Login Reminder',
          importance: Importance.high,
          priority: Priority.high,
          color: _colorGreen,
          icon: '@drawable/ic_notification',
          largeIcon: _largeIcon,
          subText: 'VanTrade',
          channelShowBadge: true,
          styleInformation: const BigTextStyleInformation(
              'Log in to VanTrade and check today\'s trade opportunities.'),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

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

  tz.TZDateTime _nextOccurrenceOf(int weekday, {required int hour}) {
    final now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime candidate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
    while (candidate.weekday != weekday || !candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required Importance importance,
    required Priority priority,
    Color color = _colorGreen,
    bool vibrate = false,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        _channelDisplayName(channelId),
        importance: importance,
        priority: priority,
        color: _colorGreen,
        icon: '@drawable/ic_notification',
        largeIcon: _largeIcon,
        subText: 'VanTrade',
        channelShowBadge: true,
        ticker: body,
        enableVibration: vibrate,
        vibrationPattern: vibrate
            ? Int64List.fromList([0, 200, 100, 300])
            : null,
        styleInformation: BigTextStyleInformation(body),
        autoCancel: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: 'vantrade',
      ),
    );
    await _plugin.show(id, title, body, details);
  }

  String _channelDisplayName(String channelId) {
    switch (channelId) {
      case _orderChannelId:
        return 'Order Execution';
      case _monitorChannelId:
        return 'Live Monitor';
      case _analysisChannelId:
        return 'Analysis Updates';
      case _opportunityChannelId:
        return 'Trade Opportunities';
      case _reminderChannelId:
        return 'Login Reminder';
      default:
        return 'VanTrade';
    }
  }

  Color _orderColor(String updateType) {
    switch (updateType) {
      case 'ORDER_PLACED':
        return _colorGreen;
      case 'GTT_CREATED':
      case 'GTT_PLACED':
        return _colorPurple;
      case 'FAILED':
      case 'GTT_FAILED':
      case 'ERROR':
        return _colorRed;
      case 'SQUAREDOFF':
        return _colorTeal;
      case 'ORDER_PENDING':
        return _colorOrange;
      case 'SQUAREOFF_FAILED':
      case 'HOLD_ENDED':
        return _colorOrange;
      case 'MARKET_CLOSED':
        return _colorBlue;
      default:
        return _colorBlue;
    }
  }

  String _orderIcon(String updateType) {
    switch (updateType) {
      case 'ORDER_PLACED':
        return '✅';
      case 'GTT_CREATED':
      case 'GTT_PLACED':
        return '🛡️';
      case 'FAILED':
      case 'GTT_FAILED':
      case 'ERROR':
        return '❌';
      case 'SQUAREDOFF':
        return '🔄';
      case 'SQUAREOFF_FAILED':
        return '⚠️';
      case 'MARKET_CLOSED':
        return '🕐';
      case 'ORDER_PENDING':
        return '🕐';
      case 'HOLD_ENDED':
        return '⏰';
      default:
        return '📊';
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
