import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import '../providers/auth_provider.dart';
import '../models/options_model.dart';
import '../utils/api_config.dart';

class OptionsResultsScreen extends StatefulWidget {
  final OptionsAnalysis analysis;

  const OptionsResultsScreen({super.key, required this.analysis});

  @override
  State<OptionsResultsScreen> createState() => _OptionsResultsScreenState();
}

class _OptionsResultsScreenState extends State<OptionsResultsScreen> {
  bool _isExecuting = false;
  String? _executeError;
  String? _executeSuccess;
  List<Map<String, dynamic>> _statusUpdates = [];
  bool _polling = false;

  // ── Monitoring state ──────────────────────────────────────────────────────
  bool _monitoring = false;
  Map<String, dynamic>? _monitorState;
  List<Map<String, dynamic>> _monitorEvents = [];
  bool _hasHumanAlert = false;
  final AudioPlayer _audioPlayer = AudioPlayer();

  final _purple = const Color(0xFF7C3AED);
  final _indigo = const Color(0xFF4F46E5);
  final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  // ── Execute trade ────────────────────────────────────────────────────────

  Future<bool> _showPasswordSheet() async {
    final controller = TextEditingController();
    bool obscure = true;
    String? error;

    final now = DateTime.now();
    final expected =
        '${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.year}';

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Icon(Icons.lock_outline, color: _purple, size: 24),
                        const SizedBox(width: 10),
                        const Text(
                          'Confirm Execution',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the password to proceed with execution.',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 20),
                    StatefulBuilder(
                      builder: (_, setFieldState) {
                        return TextField(
                          controller: controller,
                          obscureText: obscure,
                          keyboardType: TextInputType.number,
                          maxLength: 8,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            counterText: '',
                            errorText: error,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: _purple, width: 2),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setFieldState(() => obscure = !obscure),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _purple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              if (controller.text.trim() == expected) {
                                Navigator.pop(ctx, true);
                              } else {
                                setSheetState(() => error = 'Incorrect password. Try again.');
                              }
                            },
                            child: const Text(
                              'Unlock & Execute',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    return result == true;
  }

  Future<void> _handleConfirm() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    final trade = widget.analysis.trade;
    if (trade == null) return;

    // ── Password gate ────────────────────────────────────────────────────
    final unlocked = await _showPasswordSheet();
    if (!unlocked || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Trade'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dialogRow('Option', trade.optionSymbol),
            _dialogRow('Type', trade.optionType == 'CE' ? 'BUY CALL (CE)' : 'BUY PUT (PE)'),
            _dialogRow('Lots', '${trade.lots} × ${trade.lotSize} = ${trade.quantity} units'),
            _dialogRow('Entry Premium', _currency.format(trade.entryPremium)),
            _dialogRow('Stop Loss', _currency.format(trade.stopLossPremium)),
            _dialogRow('Target', _currency.format(trade.targetPremium)),
            _dialogRow('Max Loss', _currency.format(trade.maxLoss)),
            _dialogRow('Max Profit', _currency.format(trade.maxProfit)),
            _dialogRow('Hold Duration', '~${trade.suggestedHoldMinutes} min'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[300]!),
              ),
              child: Text(
                '⏱ Hold ~${trade.suggestedHoldMinutes} min. '
                'SL and target orders will auto-place. '
                'Cancel the unfilled order after exit. '
                'Auto square-off at 3:15 PM.',
                style: TextStyle(fontSize: 12, color: Colors.orange[900]),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _purple, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Execute'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() { _isExecuting = true; _executeError = null; _executeSuccess = null; });

    try {
      final resp = await http.post(
        Uri.parse(ApiConfig.optionsConfirmUrl(widget.analysis.analysisId)),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'confirmed': true,
          'api_key': auth.user!.apiKey,
          'access_token': auth.user!.accessToken,
        }),
      ).timeout(const Duration(seconds: 30));

      if (!mounted) return;

      if (resp.statusCode == 200) {
        setState(() => _executeSuccess = 'Trade executing! Polling status…');
        _startPolling();
      } else {
        String msg = 'Execution failed';
        try { msg = jsonDecode(resp.body)['detail'] ?? msg; } catch (_) {}
        setState(() => _executeError = msg);
      }
    } catch (e) {
      if (mounted) setState(() => _executeError = e.toString());
    } finally {
      if (mounted) setState(() => _isExecuting = false);
    }
  }

  void _startPolling() {
    if (_polling) return;
    _polling = true;
    _pollStatus();
  }

  Future<void> _pollStatus() async {
    // Phase 1: poll execution status until MONITORING or terminal state
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted) return;

      try {
        final resp = await http.get(
          Uri.parse(ApiConfig.optionsStatusUrl(widget.analysis.analysisId)),
        ).timeout(const Duration(seconds: 10));

        if (!mounted) return;
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final status = data['status'] ?? '';
          final updates = (data['updates'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();

          setState(() => _statusUpdates = updates);

          if (status == 'MONITORING') {
            setState(() {
              _monitoring = true;
              _executeSuccess = 'Trade active — AI monitoring position…';
            });
            _polling = false;
            _startMonitoringPoll();
            return;
          }
          if (status == 'COMPLETED' || status == 'FAILED') {
            setState(() => _executeSuccess =
                status == 'COMPLETED' ? 'Trade completed!' : 'Trade failed.');
            break;
          }
        }
      } catch (_) {}
    }
    _polling = false;
  }

  // ── Monitoring poll ───────────────────────────────────────────────────────

  void _startMonitoringPoll() {
    _pollMonitor();
  }

  Future<void> _pollMonitor() async {
    while (mounted && _monitoring) {
      await Future.delayed(const Duration(seconds: 15));
      if (!mounted) return;

      try {
        final resp = await http.get(
          Uri.parse(ApiConfig.optionsMonitorUrl(widget.analysis.analysisId)),
        ).timeout(const Duration(seconds: 10));

        if (!mounted) return;
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final status = data['status'] ?? 'MONITORING';
          final events = (data['events'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();
          final hasAlert = data['has_human_alert'] == true;

          setState(() {
            _monitorState = data;
            _monitorEvents = events;
          });

          // Danger alert — play sound and show banner
          if (hasAlert && !_hasHumanAlert) {
            setState(() => _hasHumanAlert = true);
            _playDangerSound();
            _showHumanAlertBanner(events);
          }

          // Stop polling when monitoring ends
          if (status == 'EXITED' || status == 'STOPPED' || status == 'HUMAN_NEEDED') {
            setState(() => _monitoring = false);
            break;
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _playDangerSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/alert.mp3'));
    } catch (_) {
      // If asset missing, vibration or silent fallback — don't crash
    }
  }

  void _showHumanAlertBanner(List<Map<String, dynamic>> events) {
    final alertMsg = events.lastWhere(
      (e) => e['alert_level'] == 'DANGER',
      orElse: () => {'message': 'Immediate attention required on your open position.'},
    )['message'] as String;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        backgroundColor: Colors.red[900],
        leading: const Icon(Icons.warning_rounded, color: Colors.white, size: 28),
        content: Text(
          alertMsg,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('DISMISS', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _stopMonitoring() async {
    try {
      await http.post(
        Uri.parse(ApiConfig.optionsMonitorStopUrl(widget.analysis.analysisId)),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
    if (mounted) setState(() => _monitoring = false);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final trade = widget.analysis.trade;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.analysis.index} Options Analysis'),
        backgroundColor: _purple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildIndexSummary(),
            const SizedBox(height: 16),
            if (trade == null) _buildNoTradeCard() else ...[
              _buildTradeCard(trade),
              const SizedBox(height: 16),
              _buildHoldDurationCard(trade),
              const SizedBox(height: 16),
              _buildLevelsCard(trade),
              const SizedBox(height: 16),
              _buildRiskCard(trade),
              const SizedBox(height: 16),
              _buildReasoningCard(trade),
              const SizedBox(height: 16),
              _buildIndicatorsCard(),
              const SizedBox(height: 24),
              if (!_monitoring) _buildExecuteButton(trade),
              if (_executeSuccess != null) _buildSuccessBox(_executeSuccess!),
              if (_executeError != null) _buildErrorBox(_executeError!),
              if (_statusUpdates.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildUpdatesCard(),
              ],
              if (_monitoring) ...[
                const SizedBox(height: 16),
                _buildMonitoringCard(),
              ],
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildMonitoringCard() {
    final s = _monitorState;
    final pnl = s?['pnl'] as double?;
    final pnlPct = s?['pnl_pct'] as double?;
    final currentPremium = (s?['current_premium'] as num?)?.toDouble();
    final slTrigger = (s?['sl_trigger'] as num?)?.toDouble();
    final target = (s?['target_price'] as num?)?.toDouble();
    final peakPremium = (s?['peak_premium'] as num?)?.toDouble();
    final pollCount = s?['poll_count'] as int? ?? 0;
    final status = s?['status'] as String? ?? 'MONITORING';

    final pnlColor = (pnl ?? 0) >= 0 ? Colors.green[700]! : Colors.red[700]!;
    final isAlert = _hasHumanAlert;

    // Latest events (newest first, up to 6)
    final recentEvents = _monitorEvents.reversed.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Live P&L banner ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isAlert ? Colors.red[900] : Colors.grey[900],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      if (isAlert)
                        const Icon(Icons.warning_rounded, color: Colors.white, size: 18)
                      else
                        const _PulsingDot(),
                      const SizedBox(width: 8),
                      Text(
                        isAlert ? 'ATTENTION REQUIRED' : 'AI Monitoring Active',
                        style: TextStyle(
                          color: isAlert ? Colors.red[200] : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Poll #$pollCount',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _liveStatBox('Premium', currentPremium != null ? '₹${currentPremium.toStringAsFixed(2)}' : '--', Colors.white),
                  _liveStatBox('P&L', pnl != null ? '₹${pnl.toStringAsFixed(0)}' : '--', pnlColor),
                  _liveStatBox('%', pnlPct != null ? '${pnlPct >= 0 ? '+' : ''}${pnlPct.toStringAsFixed(1)}%' : '--', pnlColor),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _liveStatBox('SL', slTrigger != null ? '₹${slTrigger.toStringAsFixed(2)}' : '--', Colors.red[300]!),
                  _liveStatBox('Target', target != null ? '₹${target.toStringAsFixed(2)}' : '--', Colors.green[300]!),
                  _liveStatBox('Peak', peakPremium != null ? '₹${peakPremium.toStringAsFixed(2)}' : '--', Colors.amber[300]!),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // ── Stop monitoring button ──────────────────────────────────────
        OutlinedButton.icon(
          onPressed: status == 'EXITED' || status == 'STOPPED' ? null : _stopMonitoring,
          icon: Icon(
            status == 'EXITED' ? Icons.check_circle_outline : Icons.stop_circle_outlined,
            size: 16,
          ),
          label: Text(
            status == 'EXITED' ? 'Position Closed' : 'Stop Monitoring (Manual Exit)',
            style: const TextStyle(fontSize: 13),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red[700],
            side: BorderSide(color: Colors.red[300]!),
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        // ── Event log ────────────────────────────────────────────────────
        if (recentEvents.isNotEmpty) ...[
          const SizedBox(height: 12),
          _card(
            icon: Icons.timeline,
            title: 'Monitor Log',
            child: Column(
              children: recentEvents.map((e) {
                final level = e['alert_level'] as String? ?? 'INFO';
                final type = e['event_type'] as String? ?? '';
                final msg = e['message'] as String? ?? '';
                final ts = e['timestamp'] as String? ?? '';
                final timeStr = ts.length >= 19 ? ts.substring(11, 19) : ts;

                Color dotColor;
                switch (level) {
                  case 'DANGER': dotColor = Colors.red[700]!; break;
                  case 'WARNING': dotColor = Colors.orange[700]!; break;
                  default: dotColor = Colors.green[600]!;
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8, height: 8,
                        margin: const EdgeInsets.only(top: 4, right: 8),
                        decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '[$type] $msg',
                              style: TextStyle(
                                fontSize: 12,
                                color: level == 'DANGER' ? Colors.red[700] : Colors.grey[800],
                                fontWeight: level == 'DANGER' ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            Text(timeStr, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _liveStatBox(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: valueColor, fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildIndexSummary() {
    final ind = widget.analysis.indexIndicators;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_purple, _indigo]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.analysis.index,
            style: const TextStyle(
                color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          Text(
            _currency.format(widget.analysis.currentIndexPrice),
            style: const TextStyle(
                color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _pillStat('RSI', (ind['rsi'] as num?)?.toStringAsFixed(1) ?? '--'),
              const SizedBox(width: 8),
              _pillStat('VWAP', ind['price_vs_vwap'] ?? '--'),
              const SizedBox(width: 8),
              _pillStat('BB', ind['bb_position'] ?? '--'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pillStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }

  Widget _buildTradeCard(OptionsTrade trade) {
    final isCE = trade.optionType == 'CE';
    final color = isCE ? Colors.green[700]! : Colors.red[700]!;
    final bgColor = isCE ? Colors.green[50]! : Colors.red[50]!;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isCE ? 'BUY CALL (CE)' : 'BUY PUT (PE)',
                      style: TextStyle(
                          color: color,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      trade.optionSymbol,
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${(trade.confidenceScore * 100).toStringAsFixed(0)}%\nconfidence',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _infoBox('Strike', '₹${trade.strikePrice.toStringAsFixed(0)}', color)),
                const SizedBox(width: 8),
                Expanded(child: _infoBox('Lots', '${trade.lots} × ${trade.lotSize}', color)),
                const SizedBox(width: 8),
                Expanded(child: _infoBox('Quantity', '${trade.quantity} units', color)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }

  Widget _buildHoldDurationCard(OptionsTrade trade) {
    final mins = trade.suggestedHoldMinutes;
    final exitTime = DateTime.now().add(Duration(minutes: mins));
    final exitStr =
        '${exitTime.hour.toString().padLeft(2, '0')}:${exitTime.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange[300]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[100],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.timer_outlined, color: Colors.orange[800], size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hold for ~$mins minutes',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[900],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Exit by $exitStr if SL/target not hit',
                  style: TextStyle(fontSize: 13, color: Colors.orange[800]),
                ),
                if (trade.holdReasoning.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    trade.holdReasoning,
                    style: TextStyle(fontSize: 12, color: Colors.orange[700], height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelsCard(OptionsTrade trade) {
    return _card(
      icon: Icons.price_change_outlined,
      title: 'Premium Levels (per unit)',
      child: Column(
        children: [
          _levelRow('Entry Premium', trade.entryPremium, Colors.blue[700]!),
          const Divider(height: 16),
          _levelRow('Stop Loss Premium', trade.stopLossPremium, Colors.red[700]!),
          const Divider(height: 16),
          _levelRow('Target Premium', trade.targetPremium, Colors.green[700]!),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Risk:Reward', style: TextStyle(color: Colors.grey[700], fontSize: 14)),
              Text(
                '1 : ${trade.riskRewardRatio.toStringAsFixed(1)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _levelRow(String label, double value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[700], fontSize: 14)),
        Text(
          _currency.format(value),
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildRiskCard(OptionsTrade trade) {
    return _card(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Risk / Reward Summary',
      child: Row(
        children: [
          Expanded(
            child: _summaryBox(
              'Investment',
              _currency.format(trade.totalInvestment),
              Colors.blue[700]!,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _summaryBox(
              'Max Loss',
              _currency.format(trade.maxLoss),
              Colors.red[700]!,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _summaryBox(
              'Max Profit',
              _currency.format(trade.maxProfit),
              Colors.green[700]!,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }

  Widget _buildReasoningCard(OptionsTrade trade) {
    return _card(
      icon: Icons.psychology_outlined,
      title: 'AI Reasoning',
      child: Text(
        trade.aiReasoning,
        style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.5),
      ),
    );
  }

  Widget _buildIndicatorsCard() {
    final ind = widget.analysis.indexIndicators;
    final rows = <MapEntry<String, String>>[
      MapEntry('RSI(14)', (ind['rsi'] as num?)?.toStringAsFixed(1) ?? '--'),
      MapEntry('VWAP', '₹${(ind['vwap'] as num?)?.toStringAsFixed(2) ?? '--'}'),
      MapEntry('Price vs VWAP', ind['price_vs_vwap'] ?? '--'),
      MapEntry('MACD Histogram', (ind['macd_histogram'] as num?)?.toStringAsFixed(4) ?? '--'),
      MapEntry('BB Position', ind['bb_position'] ?? '--'),
      MapEntry('EMA 9', '₹${(ind['ema_9'] as num?)?.toStringAsFixed(2) ?? '--'}'),
      MapEntry('EMA 21', '₹${(ind['ema_21'] as num?)?.toStringAsFixed(2) ?? '--'}'),
      MapEntry('Stoch K', (ind['stoch_k'] as num?)?.toStringAsFixed(1) ?? '--'),
      MapEntry('Stoch D', (ind['stoch_d'] as num?)?.toStringAsFixed(1) ?? '--'),
    ];

    return _card(
      icon: Icons.bar_chart,
      title: 'Technical Indicators',
      child: Column(
        children: rows
            .map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e.key,
                          style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                      Text(e.value,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildNoTradeCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(Icons.trending_flat, size: 60, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No Trade Recommended',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'The AI did not find a strong enough signal (need 3/5 votes). '
              'Market conditions are unclear — wait for a clearer setup.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecuteButton(OptionsTrade trade) {
    final isCE = trade.optionType == 'CE';
    return ElevatedButton.icon(
      onPressed: _isExecuting ? null : _handleConfirm,
      icon: _isExecuting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Icon(isCE ? Icons.trending_up : Icons.trending_down),
      label: Text(
        _isExecuting
            ? 'Executing…'
            : 'Execute ${isCE ? 'BUY CALL' : 'BUY PUT'} — ${trade.lots} Lot${trade.lots > 1 ? 's' : ''}',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isCE ? Colors.green[700] : Colors.red[700],
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey[300],
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _buildUpdatesCard() {
    return _card(
      icon: Icons.update,
      title: 'Execution Updates',
      child: Column(
        children: _statusUpdates.reversed.take(10).map((u) {
          final type = u['update_type'] ?? '';
          final msg = u['message'] ?? '';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _updateIcon(type),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(msg,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _updateIcon(String type) {
    IconData icon;
    Color color;
    switch (type) {
      case 'ORDER_PLACED':
        icon = Icons.receipt_long;
        color = Colors.blue;
        break;
      case 'ORDER_FILLED':
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case 'COMPLETED':
        icon = Icons.done_all;
        color = Colors.green[800]!;
        break;
      case 'ERROR':
        icon = Icons.error_outline;
        color = Colors.red;
        break;
      default:
        icon = Icons.info_outline;
        color = Colors.grey;
    }
    return Icon(icon, color: color, size: 16);
  }

  Widget _buildSuccessBox(String msg) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green[700], size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(msg, style: TextStyle(color: Colors.green[700])),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBox(String msg) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[700], size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(msg, style: TextStyle(color: Colors.red[700])),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required IconData icon, required String title, required Widget child}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: _purple, size: 20),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _dialogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}

// ── Pulsing green dot — indicates live monitoring ─────────────────────────────
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
          color: Colors.greenAccent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
