import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../utils/api_config.dart';
import '../services/active_trade_store.dart';
import '../services/active_session_store.dart';
import '../services/monitoring_foreground_service.dart';

class OptionsSessionScreen extends StatefulWidget {
  final String sessionId;
  final String index;
  final String expiryDate;
  final double capital;
  final int lots;
  final String apiKey;
  final String accessToken;

  const OptionsSessionScreen({
    super.key,
    required this.sessionId,
    required this.index,
    required this.expiryDate,
    required this.capital,
    required this.lots,
    required this.apiKey,
    required this.accessToken,
  });

  @override
  State<OptionsSessionScreen> createState() => _OptionsSessionScreenState();
}

class _OptionsSessionScreenState extends State<OptionsSessionScreen> {
  // ── Event feed ───────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _events = [];
  final _scrollController = ScrollController();

  // ── Session state ────────────────────────────────────────────────────────
  String _phase = 'SCANNING';
  bool _running = true;
  int _scanCount = 0;
  int _tradesCount = 0;
  double _sessionPnl = 0.0;
  String _lastSignal = '';
  String _lastRegime = '';

  // ── Active trade ─────────────────────────────────────────────────────────
  Map<String, dynamic>? _activeTrade;

  // ── SSE connection ────────────────────────────────────────────────────────
  http.Client? _sseClient;
  StreamSubscription? _sseSub;
  bool _sseConnected = false;
  bool _stopping = false;

  final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
  final _purple = const Color(0xFF7C3AED);
  final _indigo = const Color(0xFF4F46E5);

  @override
  void initState() {
    super.initState();
    MonitoringForegroundService.addDataCallback(_onForegroundData);
    _connectSse();
    _pollStatus();
    _persistAndStartForeground();
  }

  /// Persist session credentials so the foreground service can keep polling
  /// even when the app is closed, and start the background service.
  Future<void> _persistAndStartForeground() async {
    await ActiveSessionStore.save(
      sessionId:   widget.sessionId,
      index:       widget.index,
      expiryDate:  widget.expiryDate,
      capital:     widget.capital,
      lots:        widget.lots,
      apiKey:      widget.apiKey,
      accessToken: widget.accessToken,
    );
    await MonitoringForegroundService.startSession(
      sessionId: widget.sessionId,
      statusUrl: ApiConfig.optionsSessionStatusUrl(widget.sessionId),
      index:     widget.index,
    );
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    _sseClient?.close();
    _scrollController.dispose();
    MonitoringForegroundService.removeDataCallback(_onForegroundData);
    super.dispose();
  }

  // ── SSE connection ────────────────────────────────────────────────────────

  void _connectSse() {
    _sseClient = http.Client();
    final uri = Uri.parse(ApiConfig.optionsSessionStreamUrl(widget.sessionId));

    final request = http.Request('GET', uri);
    final future = _sseClient!.send(request);

    future.then((response) {
      if (!mounted) return;
      setState(() => _sseConnected = true);

      _sseSub = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (!line.startsWith('data:')) return;
          final raw = line.substring(5).trim();
          if (raw.isEmpty || raw == '{"type":"PING"}') return;
          try {
            final event = jsonDecode(raw) as Map<String, dynamic>;
            _handleEvent(event);
          } catch (_) {}
        },
        onDone: () {
          if (mounted) setState(() { _sseConnected = false; _running = false; });
        },
        onError: (_) {
          if (mounted) {
            setState(() => _sseConnected = false);
            // Reconnect after 5 s if session still running
            if (_running && !_stopping) {
              Future.delayed(const Duration(seconds: 5), () {
                if (mounted && _running) _connectSse();
              });
            }
          }
        },
      );
    }).catchError((_) {
      if (mounted) setState(() => _sseConnected = false);
    });
  }

  void _handleEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    setState(() {
      _events.add(event);
      // Update session state from event metadata
      if (event['phase'] != null) _phase = event['phase'] as String;
      if (event['scan_count'] != null) _scanCount = (event['scan_count'] as num).toInt();
      if (event['trades_today'] != null) _tradesCount = (event['trades_today'] as num).toInt();
      if (event['session_pnl'] != null) _sessionPnl = (event['session_pnl'] as num).toDouble();
      if (event['data'] != null && event['data']['signal'] != null) {
        _lastSignal = event['data']['signal'] as String;
      }
      if (event['data'] != null && event['data']['regime'] != null) {
        _lastRegime = event['data']['regime'] as String;
      }

      // When a trade is active, populate the active trade card
      final type = event['type'] as String? ?? '';
      if (type == 'TRADE_PLACED' || type == 'TRADE_EXECUTING') {
        final d = event['data'] as Map<String, dynamic>? ?? {};
        _activeTrade = {
          'option_symbol': d['option_symbol'] ?? '',
          'option_type':   d['option_type'] ?? '',
          'entry_premium': d['entry_premium'] ?? 0,
          'sl_premium':    d['sl_premium'] ?? 0,
          'target_premium': d['target_premium'] ?? 0,
          'lots':          d['lots'] ?? 0,
          'fill_price':    d['fill_price'] ?? d['entry_premium'] ?? 0,
          'current_premium': d['fill_price'] ?? d['entry_premium'] ?? 0,
        };
        // Save to store for background monitoring recovery
        if (type == 'TRADE_PLACED') {
          ActiveTradeStore.save(
            analysisId:     (event['data']['analysis_id'] as String?) ?? widget.sessionId,
            symbol:         (d['option_symbol'] as String?) ?? '',
            optionType:     (d['option_type'] as String?) ?? '',
            entryFillPrice: ((d['fill_price'] ?? 0) as num).toDouble(),
            slTrigger:      ((d['sl_premium'] ?? 0) as num).toDouble(),
            targetPrice:    ((d['target_premium'] ?? 0) as num).toDouble(),
          );
        }
      }

      // Update live premium in active trade card from monitor ticks
      if (type == 'PREMIUM_UPDATE' && _activeTrade != null) {
        final d = event['data'] as Map<String, dynamic>? ?? {};
        if (d['current_premium'] != null) {
          _activeTrade!['current_premium'] = d['current_premium'];
        }
      }

      // Clear active trade on close
      if (type == 'TRADE_CLOSED' || type == 'POSITION_CLOSED') {
        _activeTrade = null;
        ActiveTradeStore.clear();
      }

      // Session ended
      if (type == 'SESSION_STOPPED' || type == 'STREAM_END') {
        _running = false;
        _phase = 'STOPPED';
        // Clean up background service and persisted store
        ActiveSessionStore.clear();
        MonitoringForegroundService.stopMonitoring();
      }
    });

    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Foreground service data (background session/monitor ticks) ──────────────
  void _onForegroundData(Object data) {
    if (!mounted) return;
    if (data is! Map) return;
    final mode = data['mode'] as String?;

    if (mode == 'SESSION') {
      // Status update from the background SESSION poller
      setState(() {
        if (data['phase']       != null) _phase       = data['phase'] as String;
        if (data['running']     != null) _running     = data['running'] as bool;
        if (data['scan_count']  != null) _scanCount   = (data['scan_count'] as num).toInt();
        if (data['trades_today'] != null) _tradesCount = (data['trades_today'] as num).toInt();
        if (data['session_pnl'] != null) _sessionPnl  = (data['session_pnl'] as num).toDouble();
        if (data['active_trade'] != null && _activeTrade != null) {
          final at = data['active_trade'] as Map<String, dynamic>;
          if (at['current_premium'] != null) {
            _activeTrade!['current_premium'] = (at['current_premium'] as num).toDouble();
          }
        }
      });
    } else if (mode == 'MONITOR' && _activeTrade != null) {
      // Premium tick from the background MONITOR poller
      setState(() {
        if (data['current_premium'] != null) {
          _activeTrade!['current_premium'] = (data['current_premium'] as num).toDouble();
        }
      });
    }
  }

  // ── Periodic status poll (syncs state on reconnect) ───────────────────────
  void _pollStatus() {
    Timer.periodic(const Duration(seconds: 15), (t) async {
      if (!mounted || !_running) { t.cancel(); return; }
      try {
        final resp = await http
            .get(Uri.parse(ApiConfig.optionsSessionStatusUrl(widget.sessionId)))
            .timeout(const Duration(seconds: 10));
        if (!mounted) return;
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          setState(() {
            _phase       = data['phase'] ?? _phase;
            _running     = data['running'] ?? _running;
            _scanCount   = (data['scan_count'] as num?)?.toInt() ?? _scanCount;
            _tradesCount = (data['trades_today'] as num?)?.toInt() ?? _tradesCount;
            _sessionPnl  = (data['session_pnl'] as num?)?.toDouble() ?? _sessionPnl;
            _lastSignal  = data['last_signal'] ?? _lastSignal;
            _lastRegime  = data['last_regime'] ?? _lastRegime;
            if (data['active_trade'] != null) {
              _activeTrade = Map<String, dynamic>.from(data['active_trade'] as Map);
            }
          });
        }
      } catch (_) {}
    });
  }

  // ── Stop session ──────────────────────────────────────────────────────────
  Future<void> _stopSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop Trading Session?'),
        content: const Text(
          'This will stop the scan loop. '
          'Any active trade will continue to be monitored until it closes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Stop', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _stopping = true);
    try {
      await http
          .post(Uri.parse(ApiConfig.optionsSessionStopUrl(widget.sessionId)))
          .timeout(const Duration(seconds: 10));
    } catch (_) {}

    // Clear persisted session and stop the background foreground service
    await ActiveSessionStore.clear();
    await MonitoringForegroundService.stopMonitoring();

    if (mounted) setState(() { _running = false; _phase = 'STOPPED'; _stopping = false; });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_running,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave session?'),
            content: const Text(
              'The session will keep running in the background. '
              'You can view it again from the home screen.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Leave'),
              ),
            ],
          ),
        );
        if (leave == true && mounted) {
          // ignore: use_build_context_synchronously
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D1A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A2E),
          foregroundColor: Colors.white,
          title: Row(
            children: [
              _phaseDot(),
              const SizedBox(width: 8),
              Text(
                '${widget.index} Live Session',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ],
          ),
          actions: [
            if (_running)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: _stopping ? null : _stopSession,
                  icon: Icon(
                    Icons.stop_circle_outlined,
                    color: Colors.red[400],
                    size: 20,
                  ),
                  label: Text(
                    'Stop',
                    style: TextStyle(
                      color: Colors.red[400],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            _buildStatusBar(),
            if (_activeTrade != null) _buildActiveTrade(),
            Expanded(child: _buildCommentaryFeed()),
          ],
        ),
      ),
    );
  }

  // ── Phase dot ─────────────────────────────────────────────────────────────
  Widget _phaseDot() {
    Color c;
    switch (_phase) {
      case 'SCANNING':    c = Colors.blue; break;
      case 'EXECUTING':   c = Colors.orange; break;
      case 'MONITORING':  c = Colors.green; break;
      case 'STOPPED':     c = Colors.grey; break;
      default:            c = Colors.white38;
    }
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: _running ? c : Colors.grey,
        shape: BoxShape.circle,
        boxShadow: _running
            ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 6, spreadRadius: 2)]
            : null,
      ),
    );
  }

  // ── Status bar ────────────────────────────────────────────────────────────
  Widget _buildStatusBar() {
    final pnlColor = _sessionPnl >= 0 ? Colors.green[400]! : Colors.red[400]!;
    return Container(
      color: const Color(0xFF1A1A2E),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _statChip(
            Icons.radar,
            'Scans',
            '$_scanCount',
            Colors.blue[300]!,
          ),
          const SizedBox(width: 12),
          _statChip(
            Icons.bolt,
            'Trades',
            '$_tradesCount',
            Colors.orange[300]!,
          ),
          const SizedBox(width: 12),
          _statChip(
            Icons.account_balance_wallet_outlined,
            'P&L',
            _sessionPnl == 0
                ? '—'
                : '${_sessionPnl >= 0 ? '+' : ''}${_currency.format(_sessionPnl)}',
            pnlColor,
          ),
          const Spacer(),
          // SSE connection dot
          Icon(
            Icons.circle,
            size: 8,
            color: _sseConnected ? Colors.green[400] : Colors.red[400],
          ),
          const SizedBox(width: 4),
          Text(
            _sseConnected ? 'Live' : 'Reconnecting',
            style: TextStyle(
              fontSize: 11,
              color: _sseConnected ? Colors.green[400] : Colors.red[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white38, fontSize: 10)),
        Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(value,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ],
    );
  }

  // ── Active trade card ─────────────────────────────────────────────────────
  Widget _buildActiveTrade() {
    final t = _activeTrade!;
    final entry   = (t['fill_price']       as num? ?? 0).toDouble();
    final current = (t['current_premium']  as num? ?? entry).toDouble();
    final sl      = (t['sl_premium']       as num? ?? 0).toDouble();
    final target  = (t['target_premium']   as num? ?? 0).toDouble();
    final qty     = (t['lots'] as num? ?? 1).toInt() *
                    (widget.index == 'NIFTY' ? 75 : 30);
    final pnl     = (current - entry) * qty;
    final pnlPct  = entry > 0 ? ((current - entry) / entry * 100) : 0.0;
    final isProfit = pnl >= 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isProfit
              ? [const Color(0xFF0A2A1A), const Color(0xFF0D3520)]
              : [const Color(0xFF2A0A0A), const Color(0xFF350D0D)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isProfit ? Colors.green[700]! : Colors.red[700]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: t['option_type'] == 'CE'
                      ? Colors.green[900]
                      : Colors.red[900],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${t['option_type']} ${_phase == 'MONITORING' ? '● LIVE' : '⟳ EXECUTING'}',
                  style: TextStyle(
                    color: t['option_type'] == 'CE'
                        ? Colors.green[300]
                        : Colors.red[300],
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t['option_symbol'] ?? '',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${isProfit ? '+' : ''}₹${pnl.toStringAsFixed(0)}',
                style: TextStyle(
                  color: isProfit ? Colors.green[400] : Colors.red[400],
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${pnlPct.toStringAsFixed(1)}%)',
                style: TextStyle(
                  color: (isProfit ? Colors.green[300] : Colors.red[300])!
                      .withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _premiumTile('Entry', entry, Colors.white70),
              _premiumTile('Current', current,
                  isProfit ? Colors.green[300]! : Colors.red[300]!),
              _premiumTile('SL', sl, Colors.orange[300]!),
              _premiumTile('Target', target, Colors.blue[300]!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _premiumTile(String label, double value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
          Text(
            '₹${value.toStringAsFixed(2)}',
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ── Commentary feed ───────────────────────────────────────────────────────
  Widget _buildCommentaryFeed() {
    if (_events.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF7C3AED),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Connecting to session…',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      itemCount: _events.length,
      itemBuilder: (_, i) => _buildEventTile(_events[i]),
    );
  }

  Widget _buildEventTile(Map<String, dynamic> event) {
    final type    = event['type'] as String? ?? '';
    final message = event['message'] as String? ?? '';
    final level   = event['alert_level'] as String? ?? 'INFO';
    final ts      = event['timestamp'] as String? ?? '';

    // Skip internal/heartbeat events
    if (type == 'PING' || type == 'STREAM_END') return const SizedBox.shrink();

    Color borderColor;
    Color iconBg;
    IconData icon;

    switch (type) {
      case 'SESSION_STARTED':
        borderColor = _purple; iconBg = _purple; icon = Icons.play_circle_outline;
        break;
      case 'SIGNAL_FOUND':
      case 'TRADE_EXECUTING':
        borderColor = Colors.orange; iconBg = Colors.orange; icon = Icons.bolt;
        break;
      case 'TRADE_PLACED':
        borderColor = Colors.green; iconBg = Colors.green; icon = Icons.check_circle_outline;
        break;
      case 'MONITOR_UPDATE':
      case 'PREMIUM_UPDATE':
      case 'TRAILING_SL':
        borderColor = Colors.blue[700]!; iconBg = Colors.blue[900]!; icon = Icons.trending_up;
        break;
      case 'TRADE_CLOSED':
      case 'POSITION_CLOSED':
        borderColor = Colors.teal; iconBg = Colors.teal; icon = Icons.flag_outlined;
        break;
      case 'SESSION_STOPPED':
        borderColor = Colors.grey; iconBg = Colors.grey; icon = Icons.stop_circle_outlined;
        break;
      case 'SCAN_START':
        borderColor = Colors.white12; iconBg = Colors.white10; icon = Icons.radar;
        break;
      case 'EXECUTION_FAILED':
      case 'ERROR':
      case 'SCAN_ERROR':
        borderColor = Colors.red[700]!; iconBg = Colors.red[900]!; icon = Icons.warning_amber_outlined;
        break;
      case 'GPT_DECISION':
        borderColor = _indigo; iconBg = _indigo; icon = Icons.psychology_outlined;
        break;
      default:
        borderColor = level == 'DANGER'
            ? Colors.red[700]!
            : level == 'WARNING'
                ? Colors.orange[700]!
                : Colors.white12;
        iconBg = borderColor.withValues(alpha: 0.3);
        icon = Icons.info_outline;
    }

    String? timeStr;
    try {
      final dt = DateTime.parse(ts).toLocal();
      timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {}

    // Low-noise events rendered as slim lines
    final isLowNoise = type == 'SCAN_START' || type == 'PREMIUM_UPDATE';

    if (isLowNoise) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 12, color: Colors.white24),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white30, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (timeStr != null)
              Text(timeStr, style: const TextStyle(color: Colors.white24, fontSize: 10)),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: iconBg.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: borderColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xDEFFFFFF), // white @ 87% opacity
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                if (timeStr != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    timeStr,
                    style: const TextStyle(color: Colors.white30, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
