import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Foreground task entry point (separate isolate)
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
void scannerStartCallback() {
  FlutterForegroundTask.setTaskHandler(ScannerTaskHandler());
}

// ─────────────────────────────────────────────────────────────────────────────
// Task handler — runs in the background isolate
// ─────────────────────────────────────────────────────────────────────────────

class ScannerTaskHandler extends TaskHandler {
  // Config from main isolate
  String _apiKey = '';
  String _accessToken = '';
  double _capital = 10000.0;
  double _riskPercent = 2.0;
  bool _stocksOn = false;
  bool _niftyOn = false;
  bool _bankniftyOn = false;

  // Internal tick counter: scan every 12 ticks × 15 s = 3 min
  int _tick = 0;
  static const int _scanEveryNTicks = 12;

  // Cooldown: don't re-alert same mode within 15 min (900 s)
  final Map<String, DateTime> _lastAlerted = {};

  late FlutterLocalNotificationsPlugin _notif;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _notif = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    await _notif.initialize(const InitializationSettings(android: androidInit));

    // Create the high-priority alarm channel in this isolate
    final androidPlugin = _notif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'vantrade_opportunity',
        'Trade Opportunities',
        description: 'Alarm when a trade opportunity is found by auto-scanner.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('opportunity_alarm'),
        enableVibration: true,
        showBadge: true,
      ),
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _tick++;
    if (_tick < _scanEveryNTicks) return;
    _tick = 0;

    if (!_isMarketOpen()) return;
    if (!_stocksOn && !_niftyOn && !_bankniftyOn) return;

    _runScans();
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
    // Config update
    _apiKey       = (data['apiKey']       as String?) ?? _apiKey;
    _accessToken  = (data['accessToken']  as String?) ?? _accessToken;
    _capital      = (data['capital']      as num?)?.toDouble() ?? _capital;
    _riskPercent  = (data['riskPercent']  as num?)?.toDouble() ?? _riskPercent;
    _stocksOn     = (data['stocks']       as bool?) ?? _stocksOn;
    _niftyOn      = (data['nifty']        as bool?) ?? _niftyOn;
    _bankniftyOn  = (data['banknifty']    as bool?) ?? _bankniftyOn;

    // Immediately scan when config arrives (first time)
    if (cmd == 'START' && _isMarketOpen()) _runScans();
  }

  // ── Market hours (IST = UTC+5:30) ──────────────────────────────────────────
  bool _isMarketOpen() {
    final ist = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    if (ist.weekday >= 6) return false; // Sat/Sun
    final mins = ist.hour * 60 + ist.minute;
    return mins >= 555 && mins <= 910; // 9:15 AM – 3:10 PM
  }

  // ── Run all enabled scans ──────────────────────────────────────────────────
  Future<void> _runScans() async {
    if (_stocksOn)     unawaited(_scanStocks());
    if (_niftyOn)      unawaited(_scanOptions('NIFTY'));
    if (_bankniftyOn)  unawaited(_scanOptions('BANKNIFTY'));
  }

  // ── Stocks scan ────────────────────────────────────────────────────────────
  Future<void> _scanStocks() async {
    if (_cooldownActive('STOCKS')) return;
    try {
      final uri = Uri.parse('https://api.vantrade.in/api/v1/analysis/generate');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'analysis_date': _todayStr(),
              'num_stocks': 3,
              'risk_percent': _riskPercent,
              'access_token': _accessToken,
              'api_key': _apiKey,
              'sectors': ['ALL'],
              'hold_duration_days': 0,
              'capital_to_use': _capital,
              'leverage': 1,
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final stocks = (data['stocks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final good = stocks.where((s) {
          final conf = (s['confidence_score'] as num?)?.toDouble() ?? 0;
          return conf >= 0.68;
        }).toList();

        if (good.isNotEmpty) {
          final symbols = good.map((s) => s['stock_symbol'] as String).join(', ');
          final action  = good.first['action'] as String? ?? 'TRADE';
          _setLastAlerted('STOCKS');
          await _fireAlarm(
            id: 700,
            title: '📈 Stock Opportunity — $action',
            body: '$symbols ${good.length > 1 ? "(+${good.length - 1} more)" : ""} • Tap to view analysis',
          );
          FlutterForegroundTask.sendDataToMain({
            'event': 'OPPORTUNITY',
            'mode': 'STOCKS',
            'symbols': symbols,
            'count': good.length,
          });
        }
      }
    } catch (_) {
      // Swallow — keep service alive
    }
  }

  // ── Options scan (NIFTY or BANKNIFTY) ─────────────────────────────────────
  Future<void> _scanOptions(String index) async {
    if (_cooldownActive(index)) return;
    try {
      // Step 1: get nearest expiry
      final expiriesUri = Uri.parse(
        'https://api.vantrade.in/api/v1/options/expiries'
        '?index=$index&api_key=${Uri.encodeComponent(_apiKey)}'
        '&access_token=${Uri.encodeComponent(_accessToken)}',
      );
      final exResp = await http.get(expiriesUri).timeout(const Duration(seconds: 20));
      if (exResp.statusCode != 200) return;
      final exData = jsonDecode(exResp.body) as Map<String, dynamic>;
      final expiries = (exData['expiries'] as List?)?.cast<String>() ?? [];
      if (expiries.isEmpty) return;
      final expiry = expiries.first;

      // Step 2: analyze
      final uri = Uri.parse('https://api.vantrade.in/api/v1/options/analyze');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'index': index,
              'expiry_date': expiry,
              'risk_percent': _riskPercent,
              'capital_to_use': _capital,
              'access_token': _accessToken,
              'api_key': _apiKey,
              'lots': 1,
              'leverage_multiplier': 1.0,
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final trade = data['trade'] as Map<String, dynamic>?;
        if (trade == null) return;

        final conf   = (trade['confidence_score'] as num?)?.toDouble() ?? 0;
        final signal = trade['signal'] as String? ?? '';
        if (conf < 0.68 || signal.isEmpty || signal == 'NEUTRAL') return;

        final optType    = trade['option_type'] as String? ?? '';
        final strike     = trade['strike_price'] as num?;
        final entryPrem  = (trade['entry_premium'] as num?)?.toDouble() ?? 0;
        final confPct    = (conf * 100).toStringAsFixed(0);

        _setLastAlerted(index);
        await _fireAlarm(
          id: index == 'NIFTY' ? 701 : 702,
          title: '🔔 $index $optType — ${signal.replaceAll('_', ' ')}',
          body: 'Strike $strike • Entry ₹${entryPrem.toStringAsFixed(1)} • '
                'Confidence $confPct% • Tap to open',
        );
        FlutterForegroundTask.sendDataToMain({
          'event': 'OPPORTUNITY',
          'mode': index,
          'signal': signal,
          'confidence': conf,
        });
      }
    } catch (_) {
      // Swallow — keep service alive
    }
  }

  // ── Alarm notification (wakes screen, plays alarm sound) ──────────────────
  Future<void> _fireAlarm({required int id, required String title, required String body}) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'vantrade_opportunity',
        'Trade Opportunities',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,     // wakes screen / shows over lock screen
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('opportunity_alarm'),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 400, 200, 400, 200, 800]),
        ticker: 'VanTrade — Trade Opportunity Found',
        styleInformation: BigTextStyleInformation(body),
        icon: '@mipmap/launcher_icon',
        channelShowBadge: true,
        ongoing: false,
        autoCancel: true,
      ),
    );
    await _notif.show(id, title, body, details);
  }

  // ── Cooldown helpers ───────────────────────────────────────────────────────
  bool _cooldownActive(String mode) {
    final last = _lastAlerted[mode];
    if (last == null) return false;
    return DateTime.now().difference(last).inMinutes < 15;
  }

  void _setLastAlerted(String mode) {
    _lastAlerted[mode] = DateTime.now();
  }

  String _todayStr() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AutoScannerService — Flutter-side state manager (ChangeNotifier)
// ─────────────────────────────────────────────────────────────────────────────

class AutoScannerService extends ChangeNotifier {
  AutoScannerService._();
  static final AutoScannerService instance = AutoScannerService._();

  static const int _serviceId = 512;

  bool stocksEnabled    = false;
  bool niftyEnabled     = false;
  bool bankniftyEnabled = false;
  DateTime? lastOpportunityTime;
  String lastOpportunityMode = '';

  bool get anyEnabled => stocksEnabled || niftyEnabled || bankniftyEnabled;

  // ── Persistence ─────────────────────────────────────────────────────────────
  Future<void> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    stocksEnabled    = prefs.getBool('scanner_stocks')    ?? false;
    niftyEnabled     = prefs.getBool('scanner_nifty')     ?? false;
    bankniftyEnabled = prefs.getBool('scanner_banknifty') ?? false;
    notifyListeners();
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('scanner_stocks',    stocksEnabled);
    await prefs.setBool('scanner_nifty',     niftyEnabled);
    await prefs.setBool('scanner_banknifty', bankniftyEnabled);
  }

  // ── Toggle methods ───────────────────────────────────────────────────────────
  Future<void> toggleStocks(bool on, {required ScanCreds creds}) async {
    stocksEnabled = on;
    await _saveState();
    await _syncService(creds);
    notifyListeners();
  }

  Future<void> toggleNifty(bool on, {required ScanCreds creds}) async {
    niftyEnabled = on;
    await _saveState();
    await _syncService(creds);
    notifyListeners();
  }

  Future<void> toggleBanknifty(bool on, {required ScanCreds creds}) async {
    bankniftyEnabled = on;
    await _saveState();
    await _syncService(creds);
    notifyListeners();
  }

  Future<void> turnAllOff() async {
    stocksEnabled    = false;
    niftyEnabled     = false;
    bankniftyEnabled = false;
    await _saveState();
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask({'cmd': 'STOP'});
    }
    notifyListeners();
  }

  // ── Foreground service sync ──────────────────────────────────────────────────
  Future<void> _syncService(ScanCreds creds) async {
    if (!anyEnabled) {
      // All modes off → stop service
      if (await FlutterForegroundTask.isRunningService) {
        FlutterForegroundTask.sendDataToTask({'cmd': 'STOP'});
      }
      return;
    }

    final config = {
      'cmd': 'START',
      'stocks':      stocksEnabled,
      'nifty':       niftyEnabled,
      'banknifty':   bankniftyEnabled,
      'apiKey':      creds.apiKey,
      'accessToken': creds.accessToken,
      'capital':     creds.capital,
      'riskPercent': creds.riskPercent,
    };

    if (await FlutterForegroundTask.isRunningService) {
      // Already running — just update config
      FlutterForegroundTask.sendDataToTask(config);
      return;
    }

    // Request notification permission (Android 13+)
    final perm = await FlutterForegroundTask.checkNotificationPermission();
    if (perm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      notificationTitle: 'VanTrade Auto-Scanner',
      notificationText: _buildStatusText(),
      callback: scannerStartCallback,
    );

    if (result is ServiceRequestSuccess) {
      FlutterForegroundTask.sendDataToTask(config);
    }
  }

  String _buildStatusText() {
    final modes = [
      if (stocksEnabled)    'Stocks',
      if (niftyEnabled)     'NIFTY',
      if (bankniftyEnabled) 'BANKNIFTY',
    ];
    return 'Scanning ${modes.join(", ")} every 3 min…';
  }

  // ── Called by home screen to handle opportunity events from task ─────────────
  void onOpportunityReceived(String mode) {
    lastOpportunityTime = DateTime.now();
    lastOpportunityMode = mode;
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Credentials holder passed to toggle methods
// ─────────────────────────────────────────────────────────────────────────────

class ScanCreds {
  final String apiKey;
  final String accessToken;
  final double capital;
  final double riskPercent;
  const ScanCreds({
    required this.apiKey,
    required this.accessToken,
    required this.capital,
    required this.riskPercent,
  });
}
