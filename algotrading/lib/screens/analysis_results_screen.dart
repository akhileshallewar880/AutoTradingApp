import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/analysis_provider.dart';
import '../models/analysis_model.dart';
import '../widgets/stock_card.dart';
import 'execution_tracking_screen.dart';

class AnalysisResultsScreen extends StatefulWidget {
  const AnalysisResultsScreen({super.key});

  @override
  State<AnalysisResultsScreen> createState() => _AnalysisResultsScreenState();
}

class _AnalysisResultsScreenState extends State<AnalysisResultsScreen> {
  bool _allExpanded = false;
  String? _confirmError;

  @override
  Widget build(BuildContext context) {
    final analysisProvider = context.watch<AnalysisProvider>();
    final analysis = analysisProvider.currentAnalysis;

    if (analysis == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Analysis Results'),
          backgroundColor: Colors.green[700],
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('No analysis data available')),
      );
    }

    // Show friendly message if no trades found
    if (analysis.stocks.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('AI Analysis Results'),
          backgroundColor: Colors.green[700],
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Illustration Icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.trending_flat,
                    size: 60,
                    color: Colors.blue[700],
                  ),
                ),
                const SizedBox(height: 32),

                // Heading
                const Text(
                  'No Trades Found Today',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 16),

                // Message
                Text(
                  'GenAI analyzed the market but couldn\'t find any suitable trading opportunities for you today.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 24),

                // Reasons Box
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.amber[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.amber[700],
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Why no trades?',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber[900],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildReasonItem(
                        '📉',
                        'Market volatility is low',
                        'GenAI prefers to wait for clearer signals',
                      ),
                      const SizedBox(height: 8),
                      _buildReasonItem(
                        '⚡',
                        'Risk/reward ratio not favorable',
                        'Better opportunities might appear later',
                      ),
                      const SizedBox(height: 8),
                      _buildReasonItem(
                        '🎯',
                        'Technical indicators not aligned',
                        'GenAI follows strict entry criteria',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Action Buttons
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      analysisProvider.clearAnalysis();
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.refresh, size: 20),
                    label: const Text(
                      'Try Different Settings',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Secondary Action
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.home_outlined, size: 20),
                    label: const Text(
                      'Back to Dashboard',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green[700],
                      side: BorderSide(color: Colors.green[700]!, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Encouragement Text
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[100]!),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: Colors.blue[700],
                        size: 24,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Come back tomorrow',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[900],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Market conditions change daily. Better opportunities might be available tomorrow!',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Analysis Results'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildMetricsCard(context, analysis, analysisProvider),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${analysisProvider.selectedStockCount} of ${analysis.stocks.length} selected',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Expand All / Collapse All
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _allExpanded = !_allExpanded;
                        });
                      },
                      icon: Icon(
                        _allExpanded ? Icons.unfold_less : Icons.unfold_more,
                        size: 20,
                        color: Colors.green[700],
                      ),
                      tooltip: _allExpanded ? 'Collapse All' : 'Expand All',
                      visualDensity: VisualDensity.compact,
                    ),
                    // Select All / Deselect All
                    TextButton.icon(
                      onPressed: () {
                        if (analysisProvider.selectedStockCount ==
                            analysis.stocks.length) {
                          analysisProvider.deselectAllStocks();
                        } else {
                          analysisProvider.selectAllStocks();
                        }
                      },
                      icon: Icon(
                        analysisProvider.selectedStockCount ==
                                analysis.stocks.length
                            ? Icons.deselect
                            : Icons.select_all,
                        size: 18,
                      ),
                      label: Text(
                        analysisProvider.selectedStockCount ==
                                analysis.stocks.length
                            ? 'Deselect All'
                            : 'Select All',
                        style: const TextStyle(fontSize: 13),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: analysis.stocks.length,
              itemBuilder: (context, index) {
                return StockCard(
                  key: ValueKey('stock_${index}_$_allExpanded'),
                  stock: analysis.stocks[index],
                  stockIndex: index,
                  isSelected: analysisProvider.isStockSelected(index),
                  initiallyExpanded: _allExpanded,
                  onSelectionChanged: (val) {
                    analysisProvider.setStockSelected(index, val);
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(context, analysis, analysisProvider),
    );
  }

  Widget _buildMetricsCard(
    BuildContext context,
    AnalysisResponseModel analysis,
    AnalysisProvider provider,
  ) {
    final metrics = analysis.portfolioMetrics;
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
    final holdDays = provider.holdDurationDays;
    final holdLabel = _holdLabel(holdDays);

    return Card(
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Portfolio Overview',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                // Hold duration badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 13,
                        color: Colors.blue[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        holdLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Available Balance
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Available Balance',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    currencyFormat.format(
                      metrics['available_balance'] ?? 100000,
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMetric(
                  'Total Investment',
                  currencyFormat.format(metrics['total_investment'] ?? 0),
                  Colors.blue,
                ),
                _buildMetric(
                  'Total Risk',
                  currencyFormat.format(metrics['total_risk'] ?? 0),
                  Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMetric(
                  'Max Profit',
                  currencyFormat.format(metrics['max_profit'] ?? 0),
                  Colors.green,
                  pct: (metrics['total_investment'] ?? 0) > 0
                      ? (metrics['max_profit'] ?? 0) /
                            (metrics['total_investment'] as num) *
                            100
                      : null,
                ),
                _buildMetric(
                  'Max Loss',
                  currencyFormat.format(metrics['max_loss'] ?? 0),
                  Colors.red,
                  pct: (metrics['total_investment'] ?? 0) > 0
                      ? (metrics['max_loss'] ?? 0) /
                            (metrics['total_investment'] as num) *
                            100
                      : null,
                ),
              ],
            ),
            // Sectors badge row
            if (provider.selectedSectors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: provider.selectedSectors.map((s) {
                  return Chip(
                    label: Text(s, style: const TextStyle(fontSize: 11)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.green[50],
                    side: BorderSide(color: Colors.green[200]!),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _holdLabel(int days) {
    switch (days) {
      case 0:
        return 'Intraday';
      case 1:
        return '1 Day Hold';
      case 3:
        return '3 Days Hold';
      case 7:
        return '1 Week Hold';
      case 14:
        return '2 Weeks Hold';
      case 30:
        return '1 Month Hold';
      default:
        return '$days Days Hold';
    }
  }

  Widget _buildMetric(String label, String value, Color color, {double? pct}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            if (pct != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${pct.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    AnalysisResponseModel analysis,
    AnalysisProvider analysisProvider,
  ) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final selectedCount = analysisProvider.selectedStockCount;
    final hasSelection = selectedCount > 0;
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    // Calculate total investment for selected stocks only
    double selectedInvestment = 0;
    for (final stock in analysisProvider.selectedStocks) {
      selectedInvestment += stock.entryPrice * stock.quantity;
    }

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_confirmError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, color: Colors.red[700], size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _confirmError!,
                        style: TextStyle(fontSize: 13, color: Colors.red[800]),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _confirmError = null),
                      child: Icon(Icons.close, size: 16, color: Colors.red[400]),
                    ),
                  ],
                ),
              ),
            ),
          if (hasSelection && _confirmError == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text(
                    '$selectedCount stock${selectedCount == 1 ? '' : 's'} · ${currencyFormat.format(selectedInvestment)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _handleCancel(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: Colors.grey[400]!),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: hasSelection
                      ? () => _handleConfirm(context, analysis)
                      : null,
                  icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                  label: Text(
                    hasSelection
                        ? 'Execute $selectedCount Trade${selectedCount == 1 ? '' : 's'}'
                        : 'Select Trades',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleCancel(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Analysis'),
        content: const Text('Are you sure you want to cancel this analysis?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      context.read<AnalysisProvider>().clearCurrentAnalysis();
      Navigator.pop(context);
    }
  }

  /// Returns true if NSE is currently open (Mon–Fri, 9:15–15:30 IST).
  bool _isMarketOpen() {
    final now = DateTime.now();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) return false;
    final minuteOfDay = now.hour * 60 + now.minute;
    return minuteOfDay >= 9 * 60 + 15 && minuteOfDay < 15 * 60 + 30;
  }

  /// Returns true during Zerodha's AMO window: Mon–Fri 3:45 PM – 8:57 AM.
  bool _isAmoWindow() {
    final now = DateTime.now();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) return false;
    final minuteOfDay = now.hour * 60 + now.minute;
    return minuteOfDay >= 15 * 60 + 45 || minuteOfDay <= 8 * 60 + 57;
  }

  String _marketClosedReason() {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} IST';
    if (now.weekday == DateTime.saturday) {
      return 'Market is closed today (Saturday).\nNSE trades Monday – Friday, 9:15 AM – 3:30 PM IST.';
    }
    if (now.weekday == DateTime.sunday) {
      return 'Market is closed today (Sunday).\nNSE trades Monday – Friday, 9:15 AM – 3:30 PM IST.';
    }
    final minuteOfDay = now.hour * 60 + now.minute;
    if (minuteOfDay < 9 * 60 + 15) {
      return 'Market has not opened yet (current time: $timeStr).\nNSE opens at 9:15 AM IST.';
    }
    return 'Market is closed for today (current time: $timeStr).\nNSE closed at 3:30 PM IST. Try again tomorrow.';
  }

  Future<void> _showMarketClosedDialog(BuildContext context, String reason) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.access_time_rounded,
                color: Colors.orange[700],
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Market Closed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reason, style: const TextStyle(fontSize: 14, height: 1.5)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'NSE market hours:\nMonday – Friday, 9:15 AM – 3:30 PM IST',
                      style: TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK, Got It'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showAmoConfirmDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo[50],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.schedule_rounded, color: Colors.indigo[700], size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Place After Market Order?',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Market is currently closed. Your swing trade order will be placed as an '
                  'AMO (After Market Order) and will execute at NSE market open (9:15 AM IST).',
                  style: TextStyle(fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber[800]),
                        const SizedBox(width: 6),
                        Text('After order fills at market open:',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber[900])),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        '• Open Zerodha app and set Stop Loss + Target\n'
                        '  via GTT or SL order to protect your position.',
                        style: TextStyle(fontSize: 12, color: Colors.amber[900], height: 1.4),
                      ),
                    ],
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
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo[700],
                  foregroundColor: Colors.white,
                ),
                child: const Text('Place AMO'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _handleConfirm(
    BuildContext context,
    AnalysisResponseModel analysis,
  ) async {
    setState(() => _confirmError = null);

    final analysisProvider = context.read<AnalysisProvider>();
    final isSwing = analysisProvider.holdDurationDays > 0;

    if (!_isMarketOpen()) {
      // Swing trades: allow AMO placement after market hours
      if (isSwing && _isAmoWindow()) {
        final proceed = await _showAmoConfirmDialog(context);
        if (!proceed || !context.mounted) return;
      } else {
        // Intraday or outside AMO window — block
        if (context.mounted) {
          await _showMarketClosedDialog(context, _marketClosedReason());
        }
        return;
      }
    }

    final authProvider = context.read<AuthProvider>();

    try {
      await analysisProvider.confirmAnalysis(
        analysisId: analysis.analysisId,
        confirmed: true,
        accessToken: authProvider.user!.accessToken,
        apiKey: authProvider.user!.apiKey,
        userId: authProvider.user!.userId,
        holdDurationDays: analysisProvider.holdDurationDays,
      );

      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ExecutionTrackingScreen(analysisId: analysis.analysisId),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;

      final errorMsg = e.toString().toLowerCase();
      // HTTP 423 from backend = market closed; also catch keyword-based detection
      final isMarketClosed =
          errorMsg.contains('423') ||
          (errorMsg.contains('market') &&
              (errorMsg.contains('closed') ||
                  errorMsg.contains('open') ||
                  errorMsg.contains('hours')));

      if (isMarketClosed) {
        final detail = e
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('423', '')
            .trim();
        await _showMarketClosedDialog(
          context,
          detail.isNotEmpty ? detail : _marketClosedReason(),
        );
      } else {
        setState(() {
          _confirmError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Widget _buildReasonItem(String emoji, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber[900],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.amber[700],
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
