import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Central notification service for all in-app and background push notifications.
///
/// Three channels:
/// - [_orderChannel]   — Order execution updates (ORDER_PLACED, GTT_CREATED, FAILED, etc.)
/// - [_monitorChannel] — Live monitoring commentary events (DANGER, WARNING, INFO)
/// - [_analysisChannel]— Analysis lifecycle (complete, no trades found)
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  // Channel IDs
  static const _orderChannelId = 'vantrade_orders';
  static const _monitorChannelId = 'vantrade_monitor';
  static const _analysisChannelId = 'vantrade_analysis';

  // Auto-incrementing ID counters per channel
  int _orderId = 1000;
  int _monitorId = 2000;
  int _analysisId = 3000;

  Future<void> initialize() async {
    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

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

    // Request permission on Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
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
