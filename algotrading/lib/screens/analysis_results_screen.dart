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
        body: const Center(
          child: Text('No analysis data available'),
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
                        if (analysisProvider.selectedStockCount == analysis.stocks.length) {
                          analysisProvider.deselectAllStocks();
                        } else {
                          analysisProvider.selectAllStocks();
                        }
                      },
                      icon: Icon(
                        analysisProvider.selectedStockCount == analysis.stocks.length
                            ? Icons.deselect
                            : Icons.select_all,
                        size: 18,
                      ),
                      label: Text(
                        analysisProvider.selectedStockCount == analysis.stocks.length
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
                  onSelectionChanged: (_) {
                    analysisProvider.toggleStockSelection(index);
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

  Widget _buildMetricsCard(BuildContext context,
      AnalysisResponseModel analysis, AnalysisProvider provider) {
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
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // Hold duration badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined,
                          size: 13, color: Colors.blue[700]),
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
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    currencyFormat
                        .format(metrics['available_balance'] ?? 100000),
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
                ),
                _buildMetric(
                  'Max Loss',
                  currencyFormat.format(metrics['max_loss'] ?? 0),
                  Colors.red,
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
                    label: Text(s,
                        style: const TextStyle(fontSize: 11)),
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

  Widget _buildMetric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(
      BuildContext context, AnalysisResponseModel analysis, AnalysisProvider analysisProvider) {
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
          if (hasSelection)
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
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
        content:
            const Text('Are you sure you want to cancel this analysis?'),
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
  /// Uses device local time — assumes the device clock is set correctly.
  bool _isMarketOpen() {
    final now = DateTime.now(); // local device time (IST on user's phone)
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }
    final minuteOfDay = now.hour * 60 + now.minute;
    const openMinute = 9 * 60 + 15;   // 9:15 AM
    const closeMinute = 15 * 60 + 30; // 3:30 PM
    return minuteOfDay >= openMinute && minuteOfDay < closeMinute;
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.access_time_rounded,
                  color: Colors.orange[700], size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Market Closed',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reason,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
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
                  Icon(Icons.info_outline,
                      size: 16, color: Colors.blue[700]),
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

  Future<void> _handleConfirm(
    BuildContext context,
    AnalysisResponseModel analysis,
  ) async {
    // ── Client-side market hours guard ───────────────────────────────────
    // Check before making any network call — gives instant feedback.
    if (!_isMarketOpen()) {
      if (context.mounted) {
        await _showMarketClosedDialog(context, _marketClosedReason());
      }
      return;
    }
    // ────────────────────────────────────────────────────────────────────

    final authProvider = context.read<AuthProvider>();
    final analysisProvider = context.read<AnalysisProvider>();

    try {
      await analysisProvider.confirmAnalysis(
        analysisId: analysis.analysisId,
        confirmed: true,
        accessToken: authProvider.user!.accessToken,
        holdDurationDays: analysisProvider.holdDurationDays,
      );

      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ExecutionTrackingScreen(
              analysisId: analysis.analysisId,
            ),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;

      final errorMsg = e.toString().toLowerCase();
      // HTTP 423 from backend = market closed; also catch keyword-based detection
      final isMarketClosed = errorMsg.contains('423') ||
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
        // Generic error snackbar for other failures
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    e.toString().replaceFirst('Exception: ', ''),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
}
