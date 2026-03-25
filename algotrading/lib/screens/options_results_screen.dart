import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
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

  final _purple = const Color(0xFF7C3AED);
  final _indigo = const Color(0xFF4F46E5);
  final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  // ── Execute trade ────────────────────────────────────────────────────────

  Future<void> _handleConfirm() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    final trade = widget.analysis.trade;
    if (trade == null) return;

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
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber[300]!),
              ),
              child: Text(
                'SL-M order will auto-place. '
                'Exit at target manually or set a SELL limit order. '
                'Auto square-off at 3:15 PM.',
                style: TextStyle(fontSize: 12, color: Colors.amber[900]),
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
              _buildLevelsCard(trade),
              const SizedBox(height: 16),
              _buildRiskCard(trade),
              const SizedBox(height: 16),
              _buildReasoningCard(trade),
              const SizedBox(height: 16),
              _buildIndicatorsCard(),
              const SizedBox(height: 24),
              _buildExecuteButton(trade),
              if (_executeSuccess != null) _buildSuccessBox(_executeSuccess!),
              if (_executeError != null) _buildErrorBox(_executeError!),
              if (_statusUpdates.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildUpdatesCard(),
              ],
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
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
