import 'dart:convert';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;

// ── Isolate entry point — required by flutter_foreground_task ────────────────
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MonitoringTaskHandler());
}

// ── Task handler — runs in background isolate ─────────────────────────────────
// Receives monitor URL via sendDataToTask, then polls every 15 s.
class MonitoringTaskHandler extends TaskHandler {
  String _monitorUrl = '';
  String _symbol = '';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Data is sent via sendDataToTask() right after startService() is called.
    // Nothing to read here — onReceiveData() sets up the URL.
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_monitorUrl.isEmpty) return;
    _poll();
  }

  Future<void> _poll() async {
    try {
      final resp = await http
          .get(Uri.parse(_monitorUrl))
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final status = (data['status'] as String?) ?? 'MONITORING';
        final premium = (data['current_premium'] as num?)?.toDouble();
        final pnl = (data['pnl'] as num?)?.toDouble();
        final hasAlert = data['has_human_alert'] == true;

        final premiumStr =
            premium != null ? '₹${premium.toStringAsFixed(2)}' : '--';
        final pnlStr = pnl != null
            ? '${pnl >= 0 ? '+' : ''}₹${pnl.toStringAsFixed(0)}'
            : '--';

        String title;
        String text;
        if (hasAlert) {
          title = '⚠️ ATTENTION: $_symbol';
          text = 'Immediate action required on your open position!';
        } else if (status == 'EXITED' || status == 'STOPPED') {
          title = 'VanTrade — $_symbol Closed';
          text = 'Position exited. Tap to view summary.';
        } else {
          title = 'VanTrade Monitoring: $_symbol';
          text = 'Premium: $premiumStr   P&L: $pnlStr';
        }

        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
        );

        // Forward full payload to the UI isolate
        FlutterForegroundTask.sendDataToMain(data);

        // Auto-stop when position is closed
        if (status == 'EXITED' ||
            status == 'STOPPED' ||
            status == 'HUMAN_NEEDED') {
          await FlutterForegroundTask.stopService();
        }
      }
    } catch (_) {
      // Swallow network errors — keep the service alive
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onReceiveData(Object data) {
    if (data is Map) {
      final cmd = data['cmd'] as String?;
      if (cmd == 'STOP') {
        FlutterForegroundTask.stopService();
        return;
      }
      // Initial config sent right after startService()
      _monitorUrl = (data['monitorUrl'] as String?) ?? _monitorUrl;
      _symbol = (data['symbol'] as String?) ?? _symbol;
    }
  }
}

// ── Static helpers — called from the Flutter UI ───────────────────────────────
class MonitoringForegroundService {
  MonitoringForegroundService._();

  /// Call once at app startup (before [startMonitoring]).
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'vantrade_monitor_channel',
        channelName: 'VanTrade Position Monitor',
        channelDescription:
            'Keeps options trade monitoring alive when the app is in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000), // every 15 s
        autoRunOnBoot: false,
        allowWifiLock: true,
      ),
    );
  }

  /// Start the foreground service for a given position.
  /// Returns true if the service started successfully.
  static Future<bool> startMonitoring({
    required String monitorUrl,
    required String symbol,
  }) async {
    // Request notification permission (Android 13+)
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // If already running (e.g. resume after screen-off), just update data
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask(
        {'monitorUrl': monitorUrl, 'symbol': symbol},
      );
      return true;
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'VanTrade Monitoring: $symbol',
      notificationText: 'AI is watching your position…',
      callback: startCallback,
    );

    if (result is ServiceRequestSuccess) {
      // Send config data to the task handler immediately after start
      FlutterForegroundTask.sendDataToTask(
        {'monitorUrl': monitorUrl, 'symbol': symbol},
      );
      return true;
    }
    return false;
  }

  /// Stop the foreground service.
  static Future<void> stopMonitoring() async {
    await FlutterForegroundTask.stopService();
  }

  /// Register a listener for data sent from the task isolate to the UI.
  static void addDataCallback(DataCallback callback) {
    FlutterForegroundTask.addTaskDataCallback(callback);
  }

  /// Remove a previously registered listener.
  static void removeDataCallback(DataCallback callback) {
    FlutterForegroundTask.removeTaskDataCallback(callback);
  }
}
