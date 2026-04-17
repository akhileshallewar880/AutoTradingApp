import 'dart:convert';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;

// ── Isolate entry point — required by flutter_foreground_task ────────────────
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MonitoringTaskHandler());
}

// ── Task handler — runs in background isolate ─────────────────────────────────
//
// Supports two modes sent via sendDataToTask:
//   { 'mode': 'SESSION', 'statusUrl': '...', 'sessionId': '...' }
//     → polls /options/session/{id}/status every 30 s
//     → keeps notification alive with phase / scan count
//     → forwards status payload to UI isolate on every tick
//
//   { 'mode': 'MONITOR', 'monitorUrl': '...', 'symbol': '...' }
//     → existing behaviour: polls /options/{id}/monitor every 15 s
//     → stops service when position is EXITED / STOPPED
//
class MonitoringTaskHandler extends TaskHandler {
  String _mode = '';

  // SESSION fields
  String _statusUrl = '';
  String _sessionId = '';
  String _sessionIndex = '';

  // MONITOR fields
  String _monitorUrl = '';
  String _symbol = '';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_mode == 'SESSION') {
      _pollSession();
    } else if (_mode == 'MONITOR') {
      _pollMonitor();
    }
  }

  // ── SESSION polling ────────────────────────────────────────────────────────

  Future<void> _pollSession() async {
    if (_statusUrl.isEmpty) return;
    try {
      final resp = await http
          .get(Uri.parse(_statusUrl))
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final phase       = (data['phase']        as String?) ?? 'SCANNING';
        final running     = (data['running']       as bool?)   ?? true;
        final scanCount   = (data['scan_count']    as int?)    ?? 0;
        final tradesCount = (data['trades_today']  as int?)    ?? 0;
        final sessionPnl  = (data['session_pnl']   as num?)?.toDouble() ?? 0.0;

        String title;
        String text;

        if (!running || phase == 'STOPPED') {
          title = 'VanTrade — Session Stopped';
          text  = 'Scans: $scanCount  |  Trades: $tradesCount  |  P&L: ₹${sessionPnl.toStringAsFixed(0)}';
        } else if (phase == 'MONITORING') {
          final activeTrade = data['active_trade'] as Map<String, dynamic>?;
          final premium = (activeTrade?['current_premium'] as num?)?.toDouble();
          final premStr = premium != null ? '₹${premium.toStringAsFixed(2)}' : '--';
          title = 'VanTrade — Trade Active ($_sessionIndex)';
          text  = 'Monitoring open position  |  Premium: $premStr';
        } else if (phase == 'EXECUTING') {
          title = 'VanTrade — Placing Order ($_sessionIndex)';
          text  = 'Signal found — executing trade…';
        } else {
          // SCANNING
          title = 'VanTrade — Scanning ($_sessionIndex)';
          text  = 'Scan #$scanCount  |  Trades today: $tradesCount'
                  '${sessionPnl != 0 ? "  |  P&L: ₹${sessionPnl.toStringAsFixed(0)}" : ""}';
        }

        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText:  text,
        );

        // Forward to UI so the session screen can update while foregrounded
        FlutterForegroundTask.sendDataToMain({'mode': 'SESSION', ...data});

        // Auto-stop the foreground service (not the backend!) if session ended
        if (!running || phase == 'STOPPED' || phase == 'ERROR') {
          await FlutterForegroundTask.stopService();
        }
      }
    } catch (_) {
      // Swallow — keep service alive through transient network errors
    }
  }

  // ── MONITOR polling ────────────────────────────────────────────────────────

  Future<void> _pollMonitor() async {
    if (_monitorUrl.isEmpty) return;
    try {
      final resp = await http
          .get(Uri.parse(_monitorUrl))
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data    = jsonDecode(resp.body) as Map<String, dynamic>;
        final status  = (data['status']          as String?) ?? 'MONITORING';
        final premium = (data['current_premium'] as num?)?.toDouble();
        final pnl     = (data['pnl']             as num?)?.toDouble();
        final hasAlert = data['has_human_alert'] == true;

        final premiumStr = premium != null ? '₹${premium.toStringAsFixed(2)}' : '--';
        final pnlStr     = pnl != null
            ? '${pnl >= 0 ? '+' : ''}₹${pnl.toStringAsFixed(0)}'
            : '--';

        String title;
        String text;
        if (hasAlert) {
          title = '⚠️ ATTENTION: $_symbol';
          text  = 'Immediate action required on your open position!';
        } else if (status == 'EXITED' || status == 'STOPPED') {
          title = 'VanTrade — $_symbol Closed';
          text  = 'Position exited. Tap to view summary.';
        } else {
          title = 'VanTrade Monitoring: $_symbol';
          text  = 'Premium: $premiumStr   P&L: $pnlStr';
        }

        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText:  text,
        );

        FlutterForegroundTask.sendDataToMain({'mode': 'MONITOR', ...data});

        if (status == 'EXITED' || status == 'STOPPED' || status == 'HUMAN_NEEDED') {
          await FlutterForegroundTask.stopService();
        }
      }
    } catch (_) {}
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    final cmd = data['cmd'] as String?;
    if (cmd == 'STOP') {
      FlutterForegroundTask.stopService();
      return;
    }

    final mode = data['mode'] as String?;
    if (mode == 'SESSION') {
      _mode        = 'SESSION';
      _statusUrl   = (data['statusUrl']    as String?) ?? _statusUrl;
      _sessionId   = (data['sessionId']   as String?) ?? _sessionId;
      _sessionIndex = (data['index']      as String?) ?? _sessionIndex;
    } else if (mode == 'MONITOR') {
      _mode       = 'MONITOR';
      _monitorUrl = (data['monitorUrl'] as String?) ?? _monitorUrl;
      _symbol     = (data['symbol']     as String?) ?? _symbol;
    }
  }
}

// ── Static helpers — called from the Flutter UI ───────────────────────────────
class MonitoringForegroundService {
  MonitoringForegroundService._();

  /// Call once at app startup (before any start call).
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'vantrade_monitor_channel',
        channelName: 'VanTrade Position Monitor',
        channelDescription:
            'Keeps trading session and position monitoring alive in background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // SESSION uses 30 s; MONITOR uses 15 s.
        // We initialise with 30 s (session mode default).
        // The handler fires on every repeat and internally decides what to poll.
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: false,
        allowWifiLock: true,
      ),
    );
  }

  // ── SESSION mode ────────────────────────────────────────────────────────────

  /// Start/update the foreground service in SESSION mode.
  static Future<bool> startSession({
    required String sessionId,
    required String statusUrl,
    required String index,
  }) async {
    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    final payload = {
      'mode':      'SESSION',
      'statusUrl': statusUrl,
      'sessionId': sessionId,
      'index':     index,
    };

    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask(payload);
      return true;
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 257,
      notificationTitle: 'VanTrade — Scanning ($index)',
      notificationText:  'AI is scanning the market in the background…',
      callback: startCallback,
    );

    if (result is ServiceRequestSuccess) {
      FlutterForegroundTask.sendDataToTask(payload);
      return true;
    }
    return false;
  }

  // ── MONITOR mode ────────────────────────────────────────────────────────────

  /// Start/update the foreground service in MONITOR mode.
  static Future<bool> startMonitoring({
    required String monitorUrl,
    required String symbol,
  }) async {
    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    final payload = {'mode': 'MONITOR', 'monitorUrl': monitorUrl, 'symbol': symbol};

    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask(payload);
      return true;
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'VanTrade Monitoring: $symbol',
      notificationText:  'AI is watching your position…',
      callback: startCallback,
    );

    if (result is ServiceRequestSuccess) {
      FlutterForegroundTask.sendDataToTask(payload);
      return true;
    }
    return false;
  }

  // ── Shared ──────────────────────────────────────────────────────────────────

  static Future<void> stopMonitoring() async {
    await FlutterForegroundTask.stopService();
  }

  static void addDataCallback(DataCallback callback) {
    FlutterForegroundTask.addTaskDataCallback(callback);
  }

  static void removeDataCallback(DataCallback callback) {
    FlutterForegroundTask.removeTaskDataCallback(callback);
  }
}
