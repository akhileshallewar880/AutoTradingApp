import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import '../providers/auth_provider.dart';
import '../models/options_model.dart';
import '../utils/api_config.dart';
import '../services/monitoring_foreground_service.dart';
import '../services/active_trade_store.dart';

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
  List<Map<String, dynamic>> _commentary = [];
  bool _hasHumanAlert = false;
  int _logTabIndex = 0; // 0 = Commentary, 1 = Raw Log
  final AudioPlayer _audioPlayer = AudioPlayer();

  // ── Trade conclusion ──────────────────────────────────────────────────────
  // Set when monitoring ends — drives the conclusion overlay.
  Map<String, dynamic>? _conclusion;

  final _purple = const Color(0xFF7C3AED);
  final _indigo = const Color(0xFF4F46E5);
  final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    // Receive live updates forwarded from the background isolate
    MonitoringForegroundService.addDataCallback(_onForegroundData);
  }

  @override
  void dispose() {
    MonitoringForegroundService.removeDataCallback(_onForegroundData);
    _audioPlayer.dispose();
    super.dispose();
  }

  // Called by the foreground task isolate every 15 s with fresh monitor data
  void _onForegroundData(Object data) {
    if (!mounted || data is! Map) return;
    final map = Map<String, dynamic>.from(data);
    final hasAlert = map['has_human_alert'] == true;
    setState(() {
      _monitorState = map;
    });
    if (hasAlert && !_hasHumanAlert) {
      setState(() => _hasHumanAlert = true);
      _playDangerSound();
      _showHumanAlertBanner(_monitorEvents);
    }
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
            // Keep monitoring alive even when app is backgrounded / screen off
            MonitoringForegroundService.startMonitoring(
              monitorUrl: ApiConfig.optionsMonitorUrl(widget.analysis.analysisId),
              symbol: widget.analysis.index,
            );
            // Persist session so the user can reopen the monitor after closing the app
            final tradeData = (data['trade'] as Map<String, dynamic>?);
            ActiveTradeStore.save(
              analysisId: widget.analysis.analysisId,
              symbol: widget.analysis.trade?.optionSymbol ?? widget.analysis.index,
              optionType: widget.analysis.trade?.optionType ?? 'CE',
              entryFillPrice: (tradeData?['entry_premium'] as num?)?.toDouble()
                  ?? widget.analysis.trade?.entryPremium ?? 0,
              slTrigger: (tradeData?['stop_loss_premium'] as num?)?.toDouble()
                  ?? widget.analysis.trade?.stopLossPremium ?? 0,
              targetPrice: (tradeData?['target_premium'] as num?)?.toDouble()
                  ?? widget.analysis.trade?.targetPremium ?? 0,
            );
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

          // Fetch commentary in parallel with the monitor poll
          List<Map<String, dynamic>> commentary = _commentary;
          try {
            final cResp = await http.get(
              Uri.parse(ApiConfig.optionsCommentaryUrl(widget.analysis.analysisId)),
            ).timeout(const Duration(seconds: 5));
            if (cResp.statusCode == 200) {
              final cData = jsonDecode(cResp.body) as Map<String, dynamic>;
              commentary = (cData['commentary'] as List<dynamic>? ?? [])
                  .cast<Map<String, dynamic>>();
            }
          } catch (_) {}

          setState(() {
            _monitorState = data;
            _monitorEvents = events;
            _commentary = commentary;
          });

          // Danger alert — play sound and show banner
          if (hasAlert && !_hasHumanAlert) {
            setState(() => _hasHumanAlert = true);
            _playDangerSound();
            _showHumanAlertBanner(events);
          }

          // Stop polling when monitoring ends → show conclusion screen
          if (status == 'EXITED' || status == 'STOPPED' || status == 'HUMAN_NEEDED') {
            final finalPnl = (data['pnl'] as num?)?.toDouble();
            final finalPremium = (data['current_premium'] as num?)?.toDouble();
            final closeReason = _inferCloseReason(events, status);
            setState(() {
              _monitoring = false;
              _conclusion = {
                'status': status,
                'pnl': finalPnl,
                'pnl_pct': (data['pnl_pct'] as num?)?.toDouble(),
                'exit_premium': finalPremium,
                'entry_premium': (data['entry_fill_price'] as num?)?.toDouble()
                    ?? widget.analysis.trade?.entryPremium,
                'sl_trigger': (data['sl_trigger'] as num?)?.toDouble(),
                'target_price': (data['target_price'] as num?)?.toDouble(),
                'reason': closeReason,
                'human_alert': status == 'HUMAN_NEEDED',
              };
            });
            // Stop backend monitoring & foreground service
            _stopMonitoringQuiet();
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

  /// Infer a human-readable close reason from the last POSITION_CLOSED event.
  String _inferCloseReason(List<Map<String, dynamic>> events, String status) {
    if (status == 'HUMAN_NEEDED') return 'Manual intervention required';
    if (status == 'STOPPED') return 'Monitoring stopped manually';
    // Walk events newest-first looking for a POSITION_CLOSED message
    for (final e in events.reversed) {
      final type = e['event_type'] as String? ?? '';
      final msg  = (e['message'] as String? ?? '').toLowerCase();
      if (type == 'POSITION_CLOSED') {
        if (msg.contains('target')) return 'Target hit';
        if (msg.contains('sl') || msg.contains('stop')) return 'Stop-loss hit';
        if (msg.contains('manual')) return 'Manually closed on Zerodha';
        if (msg.contains('time') || msg.contains('3:')) return '3 PM time exit';
        return 'Position closed';
      }
      if (type == 'EXIT_PLACED') {
        if (msg.contains('target')) return 'Target hit';
        if (msg.contains('time')) return '3 PM time exit';
        if (msg.contains('gpt') || msg.contains('ai')) return 'AI recommended exit';
        return 'Exit placed';
      }
    }
    return 'Position closed';
  }

  /// Stop backend + foreground service without flipping _monitoring (already false).
  Future<void> _stopMonitoringQuiet() async {
    try {
      await http.post(
        Uri.parse(ApiConfig.optionsMonitorStopUrl(widget.analysis.analysisId)),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
    await MonitoringForegroundService.stopMonitoring();
    await ActiveTradeStore.clear();
  }

  Future<void> _stopMonitoring() async {
    // Show a loading indicator while the backend cancels SL and exits the position
    if (mounted) setState(() => _monitoring = true); // keep spinner visible

    try {
      // Backend cancels SL order + places exit SELL — allow up to 20s for order ops
      await http.post(
        Uri.parse(ApiConfig.optionsMonitorStopUrl(widget.analysis.analysisId)),
      ).timeout(const Duration(seconds: 20));
    } catch (_) {
      // If request fails/times out, still clean up locally
    }

    await MonitoringForegroundService.stopMonitoring();
    await ActiveTradeStore.clear();

    // Let _pollMonitor pick up the EXITED/STOPPED status and build conclusion screen
    if (mounted) setState(() => _monitoring = false);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final trade = widget.analysis.trade;

    // Show conclusion overlay as soon as monitoring ends
    if (_conclusion != null) {
      return _buildConclusionScreen(_conclusion!);
    }

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

  Widget _buildConclusionScreen(Map<String, dynamic> c) {
    final pnl         = (c['pnl'] as num?)?.toDouble() ?? 0.0;
    final pnlPct      = (c['pnl_pct'] as num?)?.toDouble() ?? 0.0;
    final exitPremium = (c['exit_premium'] as num?)?.toDouble();
    final entryPremium= (c['entry_premium'] as num?)?.toDouble();
    final slTrigger   = (c['sl_trigger'] as num?)?.toDouble();
    final targetPrice = (c['target_price'] as num?)?.toDouble();
    final reason      = c['reason'] as String? ?? 'Position closed';
    final isHuman     = c['human_alert'] == true;
    final isProfit    = pnl >= 0;

    final bgGradient  = isHuman
        ? [Colors.red[900]!, Colors.red[700]!]
        : isProfit
            ? [const Color(0xFF065F46), const Color(0xFF059669)]
            : [const Color(0xFF7F1D1D), const Color(0xFFB91C1C)];

    final resultLabel = isHuman ? 'Action Required' : isProfit ? 'Profit' : 'Loss';
    final resultIcon  = isHuman
        ? Icons.warning_rounded
        : isProfit
            ? Icons.trending_up_rounded
            : Icons.trending_down_rounded;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Trade Concluded'),
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            icon: const Icon(Icons.home_outlined, color: Colors.white, size: 18),
            label: const Text('Home', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Result hero card ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: bgGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Icon(resultIcon, color: Colors.white, size: 52),
                  const SizedBox(height: 12),
                  Text(
                    resultLabel,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '₹${pnl.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${pnlPct >= 0 ? '+' : ''}${pnlPct.toStringAsFixed(1)}%  on premium',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      reason,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Trade summary stats ─────────────────────────────────────
            _card(
              icon: Icons.receipt_long_outlined,
              title: 'Trade Summary',
              child: Column(
                children: [
                  _summaryRow('Symbol', widget.analysis.trade?.optionSymbol ?? widget.analysis.index),
                  _summaryRow('Type', widget.analysis.trade?.optionType == 'CE' ? 'CALL (CE)' : 'PUT (PE)'),
                  if (entryPremium != null)
                    _summaryRow('Entry Premium', '₹${entryPremium.toStringAsFixed(2)}'),
                  if (exitPremium != null)
                    _summaryRow('Exit Premium', '₹${exitPremium.toStringAsFixed(2)}'),
                  if (slTrigger != null)
                    _summaryRow('Stop-Loss', '₹${slTrigger.toStringAsFixed(2)}'),
                  if (targetPrice != null)
                    _summaryRow('Target', '₹${targetPrice.toStringAsFixed(2)}'),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Realised P&L',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(
                        '₹${pnl.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isProfit ? Colors.green[700] : Colors.red[700],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Human alert warning ─────────────────────────────────────
            if (isHuman) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red[700], size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'AI monitoring stopped — manual intervention was required. '
                        'Please check your Zerodha positions immediately.',
                        style: TextStyle(color: Colors.red[800], fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Actions ────────────────────────────────────────────────
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              icon: const Icon(Icons.home_outlined),
              label: const Text('Back to Dashboard',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                // Pop back to the options input screen
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Analyze Another Trade'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _purple,
                side: BorderSide(color: _purple),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          Text(value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
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

    final allEvents = _monitorEvents.reversed.toList();
    final allCommentary = _commentary; // already newest-first from backend

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
        // ── Commentary + Log tabs ────────────────────────────────────────
        const SizedBox(height: 12),
        _buildLogTabs(allCommentary, allEvents),
      ],
    );
  }

  Widget _buildLogTabs(
    List<Map<String, dynamic>> commentary,
    List<Map<String, dynamic>> events,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Tab bar ──────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                _logTab(0, Icons.record_voice_over_outlined,
                    'Commentary (${commentary.length})'),
                _logTab(1, Icons.timeline, 'Raw Log (${events.length})'),
              ],
            ),
          ),
          // ── Tab content ──────────────────────────────────────────────
          SizedBox(
            height: 280,
            child: _logTabIndex == 0
                ? _buildCommentaryList(commentary)
                : _buildRawLogList(events),
          ),
        ],
      ),
    );
  }

  Widget _logTab(int index, IconData icon, String label) {
    final selected = _logTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _logTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(index == 0 ? 14 : 0),
              topRight: Radius.circular(index == 1 ? 14 : 0),
            ),
            border: selected
                ? Border(bottom: BorderSide(color: _purple, width: 2))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: selected ? _purple : Colors.grey[500]),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? _purple : Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommentaryList(List<Map<String, dynamic>> commentary) {
    if (commentary.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.record_voice_over_outlined, color: Colors.grey[300], size: 36),
            const SizedBox(height: 8),
            Text('Commentary will appear here once monitoring starts.',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: commentary.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: Colors.grey[100]),
      itemBuilder: (_, i) {
        final entry = commentary[i];
        final event = entry['event'] as String? ?? '';
        final text = entry['text'] as String? ?? '';
        final ts = entry['timestamp'] as String? ?? '';

        // Icon per event type
        IconData icon;
        Color iconColor;
        switch (event) {
          case 'TRAILING_SL':
            icon = Icons.trending_up; iconColor = Colors.blue[600]!; break;
          case 'POSITION_CLOSED':
            icon = Icons.flag_rounded; iconColor = Colors.purple[600]!; break;
          case 'EXIT_PLACED':
            icon = Icons.logout; iconColor = Colors.orange[700]!; break;
          case 'GPT_DECISION':
            icon = Icons.psychology_outlined; iconColor = Colors.indigo[600]!; break;
          case 'HUMAN_ALERT':
            icon = Icons.warning_rounded; iconColor = Colors.red[700]!; break;
          case 'STARTED':
            icon = Icons.play_circle_outline; iconColor = Colors.green[600]!; break;
          default:
            icon = Icons.info_outline; iconColor = Colors.grey[500]!;
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text,
                        style: TextStyle(
                          fontSize: 13,
                          color: event == 'HUMAN_ALERT' ? Colors.red[700] : Colors.grey[850],
                          fontWeight: event == 'HUMAN_ALERT' || event == 'POSITION_CLOSED'
                              ? FontWeight.bold : FontWeight.normal,
                        )),
                    const SizedBox(height: 2),
                    Text(ts, style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRawLogList(List<Map<String, dynamic>> events) {
    if (events.isEmpty) {
      return Center(
        child: Text('No events yet.',
            style: TextStyle(color: Colors.grey[400], fontSize: 12)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: events.length,
      itemBuilder: (_, i) {
        final e = events[i];
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
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 7, height: 7,
                margin: const EdgeInsets.only(top: 5, right: 8),
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('[$type] $msg',
                        style: TextStyle(
                          fontSize: 11,
                          color: level == 'DANGER' ? Colors.red[700] : Colors.grey[700],
                          fontWeight: level == 'DANGER' ? FontWeight.bold : FontWeight.normal,
                        )),
                    Text(timeStr,
                        style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
    // Once the trade is live, show ACTUAL execution levels (fill price, real SL/target
    // orders placed on Zerodha) rather than the AI analysis estimates.
    final s = _monitorState;
    final isLive = _monitoring && s != null;

    final entryDisplay = isLive
        ? (s['entry_fill_price'] as num?)?.toDouble() ?? trade.entryPremium
        : trade.entryPremium;
    final slDisplay = isLive
        ? (s['sl_trigger'] as num?)?.toDouble() ?? trade.stopLossPremium
        : trade.stopLossPremium;
    final targetDisplay = isLive
        ? (s['target_price'] as num?)?.toDouble() ?? trade.targetPremium
        : trade.targetPremium;

    final rr = (entryDisplay > slDisplay)
        ? (targetDisplay - entryDisplay) / (entryDisplay - slDisplay)
        : trade.riskRewardRatio;

    return _card(
      icon: Icons.price_change_outlined,
      title: isLive ? 'Actual Execution Levels' : 'Premium Levels (per unit)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLive) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_outlined, size: 14, color: Colors.blue[700]),
                  const SizedBox(width: 6),
                  Text(
                    'Live — actual order prices on Zerodha',
                    style: TextStyle(fontSize: 11, color: Colors.blue[700]),
                  ),
                ],
              ),
            ),
          ],
          _levelRow('Entry (Fill Price)', entryDisplay, Colors.blue[700]!),
          const Divider(height: 16),
          _levelRow('Stop Loss (Order Trigger)', slDisplay, Colors.red[700]!),
          const Divider(height: 16),
          _levelRow('Target (Limit Order)', targetDisplay, Colors.green[700]!),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Risk:Reward', style: TextStyle(color: Colors.grey[700], fontSize: 14)),
              Text(
                '1 : ${rr.toStringAsFixed(1)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          if (isLive) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Analysis Estimate', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                Text(
                  'Entry ${_currency.format(trade.entryPremium)}  '
                  'SL ${_currency.format(trade.stopLossPremium)}  '
                  'T ${_currency.format(trade.targetPremium)}',
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ],
            ),
          ],
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
