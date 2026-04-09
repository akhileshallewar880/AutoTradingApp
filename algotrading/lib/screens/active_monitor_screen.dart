import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/active_trade_store.dart';
import '../services/monitoring_foreground_service.dart';
import '../services/notification_service.dart';
import '../utils/api_config.dart';

/// Standalone screen shown when the user reopens the app with an active trade.
/// Only needs [analysisId] to poll GET /options/{id}/monitor.
/// Does not require the full OptionsAnalysis object.
class ActiveMonitorScreen extends StatefulWidget {
  final ActiveTrade trade;

  const ActiveMonitorScreen({super.key, required this.trade});

  @override
  State<ActiveMonitorScreen> createState() => _ActiveMonitorScreenState();
}

class _ActiveMonitorScreenState extends State<ActiveMonitorScreen> {
  Map<String, dynamic>? _state;
  List<Map<String, dynamic>> _events = [];
  bool _hasAlert = false;
  bool _monitoring = true;

  // Notification tracking
  int _notifiedEventCount = 0;
  bool _closedNotified = false;

  final _audio = AudioPlayer();
  final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
  final _purple = const Color(0xFF7C3AED);

  @override
  void initState() {
    super.initState();
    MonitoringForegroundService.addDataCallback(_onForegroundData);
    _poll();
  }

  @override
  void dispose() {
    MonitoringForegroundService.removeDataCallback(_onForegroundData);
    _audio.dispose();
    super.dispose();
  }

  void _onForegroundData(Object data) {
    if (!mounted || data is! Map) return;
    _applyState(Map<String, dynamic>.from(data));
  }

  void _applyState(Map<String, dynamic> data) {
    final hasAlert = data['has_human_alert'] == true;
    final events = (data['events'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    setState(() {
      _state = data;
      _events = events;
    });
    if (hasAlert && !_hasAlert) {
      setState(() => _hasAlert = true);
      _playAlert();
      _showAlertBanner();
    }
    final status = data['status'] as String? ?? 'MONITORING';

    // Fire push notifications for each new monitor event
    _notifyNewEvents(events, status, data);

    if (status == 'EXITED' || status == 'STOPPED' || status == 'HUMAN_NEEDED') {
      setState(() => _monitoring = false);
      _clearAndStop();
    }
  }

  void _notifyNewEvents(
    List<Map<String, dynamic>> events,
    String status,
    Map<String, dynamic> data,
  ) {
    // Notify for every new event since last check
    if (events.length > _notifiedEventCount) {
      final newEvents = events.sublist(_notifiedEventCount);
      for (final e in newEvents) {
        final level = e['alert_level'] as String? ?? 'INFO';
        final type = e['event_type'] as String? ?? '';
        final msg = e['message'] as String? ?? '';
        if (msg.isNotEmpty) {
          NotificationService.instance.showMonitorEvent(
            symbol: widget.trade.symbol,
            message: msg,
            alertLevel: level,
            eventType: type,
          );
        }
      }
      _notifiedEventCount = events.length;
    }

    // Fire a single position-closed notification
    if (!_closedNotified &&
        (status == 'EXITED' ||
            status == 'STOPPED' ||
            status == 'HUMAN_NEEDED')) {
      _closedNotified = true;
      final pnl = (data['pnl'] as num?)?.toDouble();
      NotificationService.instance.showPositionClosed(
        symbol: widget.trade.symbol,
        status: status,
        pnl: pnl,
      );
    }
  }

  // Main HTTP poll loop — polls immediately on open, then every 15 s
  Future<void> _poll() async {
    while (mounted && _monitoring) {
      try {
        final resp = await http
            .get(Uri.parse(ApiConfig.optionsMonitorUrl(widget.trade.analysisId)))
            .timeout(const Duration(seconds: 10));
        if (!mounted) return;
        if (resp.statusCode == 200) {
          _applyState(jsonDecode(resp.body) as Map<String, dynamic>);
        } else if (resp.statusCode == 404) {
          setState(() => _monitoring = false);
          await _clearAndStop();
          return;
        }
      } catch (_) {}
      // Wait before next poll (skipped on first pass above)
      await Future.delayed(const Duration(seconds: 15));
    }
  }

  Future<void> _clearAndStop() async {
    await ActiveTradeStore.clear();
    await MonitoringForegroundService.stopMonitoring();
  }

  Future<void> _stopMonitoring() async {
    try {
      await http
          .post(Uri.parse(
              ApiConfig.optionsMonitorStopUrl(widget.trade.analysisId)))
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
    setState(() => _monitoring = false);
    await _clearAndStop();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _playAlert() async {
    try { await _audio.play(AssetSource('sounds/alert.mp3')); } catch (_) {}
  }

  void _showAlertBanner() {
    if (!mounted) return;
    final msg = _events.lastWhere(
      (e) => e['alert_level'] == 'DANGER',
      orElse: () => {'message': 'Immediate action required!'},
    )['message'] as String;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        backgroundColor: Colors.red[900],
        leading: const Icon(Icons.warning_rounded, color: Colors.white, size: 28),
        content: Text(msg,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('DISMISS',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final isCE = widget.trade.optionType == 'CE';
    final status = s?['status'] as String? ?? 'MONITORING';

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.trade.symbol} Monitor'),
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        actions: [
          if (_monitoring)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  const _PulsingDot(),
                  const SizedBox(width: 6),
                  Text('LIVE',
                      style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Position summary card ────────────────────────────────────
            _buildSummaryCard(isCE),
            const SizedBox(height: 16),
            // ── Live monitoring card ─────────────────────────────────────
            _buildMonitorCard(s, status),
            const SizedBox(height: 16),
            // ── Event log ───────────────────────────────────────────────
            if (_events.isNotEmpty) _buildEventLog(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(bool isCE) {
    final color = isCE ? Colors.green[700]! : Colors.red[700]!;
    final bg = isCE ? Colors.green[50]! : Colors.red[50]!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(isCE ? Icons.trending_up : Icons.trending_down,
              color: color, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isCE ? 'BUY CALL (CE)' : 'BUY PUT (PE)',
                    style: TextStyle(
                        color: color,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                Text(widget.trade.symbol,
                    style:
                        TextStyle(color: Colors.grey[700], fontSize: 13)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Entry', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
              Text(_currency.format(widget.trade.entryFillPrice),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMonitorCard(Map<String, dynamic>? s, String status) {
    final pnl = (s?['pnl'] as num?)?.toDouble();
    final pnlPct = (s?['pnl_pct'] as num?)?.toDouble();
    final premium = (s?['current_premium'] as num?)?.toDouble();
    final sl = (s?['sl_trigger'] as num?)?.toDouble() ?? widget.trade.slTrigger;
    final target = (s?['target_price'] as num?)?.toDouble() ?? widget.trade.targetPrice;
    final peak = (s?['peak_premium'] as num?)?.toDouble();
    final pollCount = s?['poll_count'] as int? ?? 0;
    final isAlert = _hasAlert;
    final pnlColor =
        (pnl ?? 0) >= 0 ? Colors.green[700]! : Colors.red[700]!;

    final isDone =
        status == 'EXITED' || status == 'STOPPED' || status == 'HUMAN_NEEDED';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Live P&L banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isAlert
                ? Colors.red[900]
                : (isDone ? Colors.grey[800] : Colors.grey[900]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    if (isAlert)
                      const Icon(Icons.warning_rounded,
                          color: Colors.white, size: 18)
                    else if (isDone)
                      Icon(Icons.check_circle_outline,
                          color: Colors.grey[300], size: 18)
                    else
                      const _PulsingDot(),
                    const SizedBox(width: 8),
                    Text(
                      isAlert
                          ? 'ATTENTION REQUIRED'
                          : (isDone
                              ? 'Position Closed'
                              : 'AI Monitoring Active'),
                      style: TextStyle(
                        color: isAlert
                            ? Colors.red[200]
                            : Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                  Text('Poll #$pollCount',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat('Premium',
                      premium != null
                          ? '₹${premium.toStringAsFixed(2)}'
                          : '--',
                      Colors.white),
                  _stat('P&L',
                      pnl != null
                          ? '₹${pnl.toStringAsFixed(0)}'
                          : '--',
                      pnlColor),
                  _stat('%',
                      pnlPct != null
                          ? '${pnlPct >= 0 ? '+' : ''}${pnlPct.toStringAsFixed(1)}%'
                          : '--',
                      pnlColor),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat('SL', '₹${sl.toStringAsFixed(2)}',
                      Colors.red[300]!),
                  _stat('Target', '₹${target.toStringAsFixed(2)}',
                      Colors.green[300]!),
                  _stat(
                    'Peak',
                    peak != null
                        ? '₹${peak.toStringAsFixed(2)}'
                        : '--',
                    Colors.amber[300]!,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Stop button
        OutlinedButton.icon(
          onPressed: isDone ? null : _stopMonitoring,
          icon: Icon(
            isDone
                ? Icons.check_circle_outline
                : Icons.stop_circle_outlined,
            size: 16,
          ),
          label: Text(
            isDone
                ? 'Position Closed'
                : 'Stop Monitoring (Manual Exit)',
            style: const TextStyle(fontSize: 13),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red[700],
            side: BorderSide(color: Colors.red[300]!),
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Widget _buildEventLog() {
    final recent = _events.reversed.take(8).toList();
    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.timeline, color: _purple, size: 18),
              const SizedBox(width: 8),
              const Text('Monitor Log',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),
            ...recent.map((e) {
              final level = e['alert_level'] as String? ?? 'INFO';
              final type = e['event_type'] as String? ?? '';
              final msg = e['message'] as String? ?? '';
              final ts = e['timestamp'] as String? ?? '';
              final timeStr =
                  ts.length >= 19 ? ts.substring(11, 19) : ts;

              Color dot;
              switch (level) {
                case 'DANGER':
                  dot = Colors.red[700]!;
                  break;
                case 'WARNING':
                  dot = Colors.orange[700]!;
                  break;
                default:
                  dot = Colors.green[600]!;
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 4, right: 8),
                      decoration: BoxDecoration(
                          color: dot, shape: BoxShape.circle),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '[$type] $msg',
                            style: TextStyle(
                              fontSize: 12,
                              color: level == 'DANGER'
                                  ? Colors.red[700]
                                  : Colors.grey[800],
                              fontWeight: level == 'DANGER'
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          Text(timeStr,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[500])),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color valueColor) {
    return Column(children: [
      Text(label,
          style: const TextStyle(color: Colors.white54, fontSize: 11)),
      const SizedBox(height: 4),
      Text(value,
          style: TextStyle(
              color: valueColor,
              fontSize: 15,
              fontWeight: FontWeight.bold)),
    ]);
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
            color: Colors.greenAccent, shape: BoxShape.circle),
      ),
    );
  }
}
