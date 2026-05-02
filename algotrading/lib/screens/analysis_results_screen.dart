import '../theme/vt_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/analysis_provider.dart';
import '../models/analysis_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/status_badge.dart';
import '../widgets/stock_card.dart';
import '../widgets/vt_button.dart';
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
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          title: Text('AI Results', style: AppTextStyles.h2),
        ),
        body: Center(
          child: Text('No analysis data available',
              style: AppTextStyles.bodySecondary),
        ),
      );
    }

    if (analysis.stocks.isEmpty) {
      return _buildEmptyState(analysisProvider);
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Row(
          children: [
            Text('AI Results', style: AppTextStyles.h2),
            const SizedBox(width: Sp.sm),
            StatusBadge(
              label: '${analysis.stocks.length} Picks',
              type: BadgeType.ai,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Metrics strip ──────────────────────────────────────────────────
          _buildMetricsStrip(analysis, analysisProvider),

          // ── Selection controls + disclaimer ────────────────────────────────
          Padding(
            padding:
                EdgeInsets.symmetric(horizontal: Sp.base, vertical: Sp.xs),
            child: Row(
              children: [
                Text(
                  '${analysisProvider.selectedStockCount} of ${analysis.stocks.length} selected',
                  style: AppTextStyles.caption
                      .copyWith(color: context.vt.textSecondary),
                ),
                SizedBox(width: Sp.xs),
                Text('·',
                    style: AppTextStyles.caption
                        .copyWith(color: context.vt.textTertiary)),
                SizedBox(width: Sp.xs),
                Expanded(
                  child: Text(
                    'Not financial advice.',
                    style: AppTextStyles.caption
                        .copyWith(color: context.vt.textTertiary, fontSize: 11),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _allExpanded = !_allExpanded),
                  child: Icon(
                    _allExpanded
                        ? Icons.unfold_less_rounded
                        : Icons.unfold_more_rounded,
                    size: 18,
                    color: context.vt.textSecondary,
                  ),
                ),
                SizedBox(width: Sp.sm),
                GestureDetector(
                  onTap: () {
                    if (analysisProvider.selectedStockCount ==
                        analysis.stocks.length) {
                      analysisProvider.deselectAllStocks();
                    } else {
                      analysisProvider.selectAllStocks();
                    }
                  },
                  child: Text(
                    analysisProvider.selectedStockCount == analysis.stocks.length
                        ? 'Deselect All'
                        : 'Select All',
                    style: AppTextStyles.caption.copyWith(
                        color: context.vt.accentGreen,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.vt.divider),
          const SizedBox(height: Sp.xs),

          // ── Stock list ──────────────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: Sp.base),
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
      bottomNavigationBar:
          _buildBottomBar(context, analysis, analysisProvider),
    );
  }

  // ── Portfolio summary card ─────────────────────────────────────────────────

  Widget _buildMetricsStrip(
    AnalysisResponseModel analysis,
    AnalysisProvider provider,
  ) {
    final metrics = analysis.portfolioMetrics;
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final holdDays = provider.holdDurationDays;

    final totalInvestment =
        ((metrics['total_investment'] ?? 0) as num).toDouble();
    final maxProfit = ((metrics['max_profit'] ?? 0) as num).toDouble();
    final maxLoss = ((metrics['max_loss'] ?? 0) as num).toDouble();
    final profitPct =
        totalInvestment > 0 ? maxProfit / totalInvestment * 100 : 0.0;
    final lossPct =
        totalInvestment > 0 ? maxLoss / totalInvestment * 100 : 0.0;

    final double overallConfidence = analysis.stocks.isEmpty
        ? 0.0
        : analysis.stocks
                .map((s) => s.confidenceScore)
                .reduce((a, b) => a + b) /
            analysis.stocks.length;
    final int confPct = (overallConfidence * 100).round();
    final Color confColor = confPct >= 80
        ? context.vt.accentGreen
        : confPct >= 70
            ? context.vt.warning
            : context.vt.danger;

    return Padding(
      padding: EdgeInsets.fromLTRB(Sp.base, Sp.sm, Sp.base, 0),
      child: Container(
        decoration: BoxDecoration(
          color: context.vt.surface1,
          borderRadius: BorderRadius.circular(Rad.lg),
          border: Border.all(color: context.vt.divider),
          boxShadow: AppColors.ambientShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(Sp.base, Sp.md, Sp.base, Sp.sm),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: context.vt.accentPurpleDim,
                      borderRadius: BorderRadius.circular(Rad.sm),
                    ),
                    child: Icon(Icons.auto_awesome_rounded,
                        size: 14, color: context.vt.accentPurple),
                  ),
                  SizedBox(width: Sp.sm),
                  Text('Portfolio Summary', style: AppTextStyles.h3),
                  Spacer(),
                  // Hold badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Sp.sm, vertical: 3),
                    decoration: BoxDecoration(
                      color: context.vt.accentPurpleDim,
                      borderRadius: BorderRadius.circular(Rad.pill),
                    ),
                    child: Text(
                      _holdLabel(holdDays),
                      style: AppTextStyles.caption.copyWith(
                          color: context.vt.accentPurple,
                          fontWeight: FontWeight.w600,
                          fontSize: 11),
                    ),
                  ),
                  SizedBox(width: Sp.xs),
                  // Picks count
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Sp.sm, vertical: 3),
                    decoration: BoxDecoration(
                      color: context.vt.surface2,
                      borderRadius: BorderRadius.circular(Rad.pill),
                      border: Border.all(color: context.vt.divider),
                    ),
                    child: Text(
                      '${analysis.stocks.length} picks',
                      style: AppTextStyles.caption.copyWith(
                          color: context.vt.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: context.vt.divider),

            // ── Investment hero ──────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(Sp.base, Sp.md, Sp.base, Sp.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TOTAL CAPITAL AT RISK',
                      style: AppTextStyles.caption.copyWith(
                          fontSize: 10,
                          letterSpacing: 0.8,
                          color: context.vt.textTertiary)),
                  const SizedBox(height: 4),
                  Text(
                    currency.format(totalInvestment),
                    style: AppTextStyles.display.copyWith(fontSize: 30),
                  ),
                ],
              ),
            ),

            // ── Profit / Loss row ────────────────────────────────────────
            Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: Sp.base),
              child: Row(
                children: [
                  // Max Profit
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(Sp.sm),
                      decoration: BoxDecoration(
                        color: context.vt.accentGreen.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(Rad.md),
                        border: Border.all(
                            color:
                                context.vt.accentGreen.withValues(alpha: 0.18)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.trending_up_rounded,
                                size: 12, color: context.vt.accentGreen),
                            SizedBox(width: 4),
                            Text('MAX PROFIT',
                                style: AppTextStyles.caption.copyWith(
                                    color: context.vt.accentGreen,
                                    fontSize: 9,
                                    letterSpacing: 0.6)),
                          ]),
                          SizedBox(height: 5),
                          Text(currency.format(maxProfit),
                              style: AppTextStyles.mono.copyWith(
                                  color: context.vt.accentGreen,
                                  fontWeight: FontWeight.w700)),
                          SizedBox(height: 2),
                          Text('+${profitPct.toStringAsFixed(1)}%',
                              style: AppTextStyles.caption.copyWith(
                                  color: context.vt.accentGreen,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: Sp.sm),
                  // Max Loss
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(Sp.sm),
                      decoration: BoxDecoration(
                        color: context.vt.danger.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(Rad.md),
                        border: Border.all(
                            color: context.vt.danger.withValues(alpha: 0.18)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.trending_down_rounded,
                                size: 12, color: context.vt.danger),
                            SizedBox(width: 4),
                            Text('MAX LOSS',
                                style: AppTextStyles.caption.copyWith(
                                    color: context.vt.danger,
                                    fontSize: 9,
                                    letterSpacing: 0.6)),
                          ]),
                          SizedBox(height: 5),
                          Text(currency.format(maxLoss),
                              style: AppTextStyles.mono.copyWith(
                                  color: context.vt.danger,
                                  fontWeight: FontWeight.w700)),
                          SizedBox(height: 2),
                          Text('-${lossPct.toStringAsFixed(1)}%',
                              style: AppTextStyles.caption.copyWith(
                                  color: context.vt.danger,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── AI Confidence hero ───────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(Sp.base, Sp.sm, Sp.base, Sp.md),
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: Sp.md, vertical: Sp.md),
                decoration: BoxDecoration(
                  color: confColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(Rad.md),
                  border: Border.all(
                      color: confColor.withValues(alpha: 0.28), width: 1),
                ),
                child: Row(
                  children: [
                    // Left: label + big % + qualifier pill
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.auto_awesome_rounded,
                                size: 11, color: context.vt.accentPurple),
                            SizedBox(width: 4),
                            Text('AI CONFIDENCE',
                                style: AppTextStyles.caption.copyWith(
                                    fontSize: 10,
                                    letterSpacing: 0.8,
                                    color: context.vt.textTertiary)),
                          ]),
                          SizedBox(height: 6),
                          Text(
                            '$confPct%',
                            style: AppTextStyles.display.copyWith(
                                fontSize: 38,
                                color: confColor,
                                height: 1.0),
                          ),
                          SizedBox(height: 6),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: Sp.sm, vertical: 3),
                            decoration: BoxDecoration(
                              color: confColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(Rad.pill),
                            ),
                            child: Text(
                              _confLabel(confPct),
                              style: AppTextStyles.caption.copyWith(
                                  color: confColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                  letterSpacing: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: Sp.md),
                    // Right: circular arc gauge
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox.expand(
                            child: CircularProgressIndicator(
                              value: overallConfidence,
                              strokeWidth: 7,
                              backgroundColor:
                                  context.vt.divider,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(confColor),
                              strokeCap: StrokeCap.round,
                            ),
                          ),
                          Icon(Icons.auto_awesome_rounded,
                              size: 24, color: confColor),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _confLabel(int pct) {
    if (pct >= 80) return 'HIGH CONFIDENCE';
    if (pct >= 70) return 'MODERATE';
    return 'LOW CONFIDENCE';
  }

  String _holdLabel(int days) {
    switch (days) {
      case 0:
        return 'Intraday';
      case 1:
        return '1 Day';
      case 3:
        return '3 Days';
      case 7:
        return '1 Week';
      case 14:
        return '2 Weeks';
      case 30:
        return '1 Month';
      default:
        return '$days Days';
    }
  }

  // ── Bottom bar ─────────────────────────────────────────────────────────────

  Widget _buildBottomBar(
    BuildContext context,
    AnalysisResponseModel analysis,
    AnalysisProvider analysisProvider,
  ) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final selectedCount = analysisProvider.selectedStockCount;
    final hasSelection = selectedCount > 0;
    final currency =
        NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    double selectedInvestment = 0;
    for (final stock in analysisProvider.selectedStocks) {
      selectedInvestment += stock.entryPrice * stock.quantity;
    }

    return Container(
      padding:
          EdgeInsets.fromLTRB(Sp.base, Sp.sm, Sp.base, Sp.sm + bottomPadding),
      decoration: BoxDecoration(
        color: context.vt.surface1,
        border: Border(top: BorderSide(color: context.vt.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_confirmError != null)
            Padding(
              padding: EdgeInsets.only(bottom: Sp.sm),
              child: Container(
                padding: EdgeInsets.all(Sp.md),
                decoration: BoxDecoration(
                  color: context.vt.dangerDim,
                  borderRadius: BorderRadius.circular(Rad.md),
                  border: Border.all(
                      color: context.vt.danger.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: context.vt.danger, size: 16),
                    SizedBox(width: Sp.sm),
                    Expanded(
                      child: Text(
                        _confirmError!,
                        style: AppTextStyles.caption
                            .copyWith(color: context.vt.danger),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _confirmError = null),
                      child: Icon(Icons.close,
                          size: 14, color: context.vt.danger),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              // Cancel
              VtButton(
                label: 'Cancel',
                onPressed: () => _handleCancel(context),
                variant: VtButtonVariant.ghost,
                width: 90,
              ),
              const SizedBox(width: Sp.sm),
              // Execute
              Expanded(
                child: VtButton(
                  label: hasSelection
                      ? 'Execute $selectedCount Trade${selectedCount == 1 ? '' : 's'}'
                      : 'Select Trades',
                  onPressed:
                      hasSelection ? () => _handleConfirm(context, analysis) : null,
                  icon: hasSelection
                      ? const Icon(Icons.rocket_launch_rounded,
                          size: 16, color: Colors.white)
                      : null,
                ),
              ),
            ],
          ),
          if (hasSelection) ...[
            SizedBox(height: Sp.xs),
            Text(
              '${currency.format(selectedInvestment)} total investment',
              style: AppTextStyles.caption
                  .copyWith(color: context.vt.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmptyState(AnalysisProvider analysisProvider) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text('AI Results', style: AppTextStyles.h2),
      ),
      body: SingleChildScrollView(
        padding:
            EdgeInsets.symmetric(horizontal: Sp.xl, vertical: Sp.xxl),
        child: Column(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: context.vt.accentPurpleDim,
                shape: BoxShape.circle,
                border: Border.all(
                    color: context.vt.accentPurple.withValues(alpha: 0.2),
                    width: 1.5),
              ),
              child: Icon(Icons.search_off_rounded,
                  size: 44, color: context.vt.accentPurple),
            ),
            SizedBox(height: Sp.xl),
            Text(
              'No Trades Found',
              style: AppTextStyles.h1,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: Sp.sm),
            Text(
              "Market conditions aren't favorable right now. Our AI skips low-confidence setups to protect your capital.",
              style: AppTextStyles.bodySecondary.copyWith(height: 1.6),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: Sp.xxl),

            // Reasons
            Container(
              padding: EdgeInsets.all(Sp.base),
              decoration: BoxDecoration(
                color: context.vt.surface1,
                borderRadius: BorderRadius.circular(Rad.lg),
                border: Border.all(color: context.vt.divider),
              ),
              child: Column(
                children: [
                  _buildReasonTile(
                    Icons.show_chart_rounded,
                    context.vt.textSecondary,
                    'Low momentum signals',
                    'AI prefers to wait for clearer directional moves',
                  ),
                  Divider(height: Sp.base, color: context.vt.divider),
                  _buildReasonTile(
                    Icons.balance_rounded,
                    context.vt.warning,
                    'Risk/reward not favorable',
                    'Entry price vs. stop-loss creates unfavorable ratio',
                  ),
                  Divider(height: Sp.base, color: context.vt.divider),
                  _buildReasonTile(
                    Icons.align_vertical_center_rounded,
                    context.vt.danger,
                    'Indicators not aligned',
                    'AI follows strict multi-indicator entry criteria',
                  ),
                ],
              ),
            ),

            const SizedBox(height: Sp.xxl),
            VtButton(
              label: 'Adjust Parameters',
              onPressed: () {
                analysisProvider.clearCurrentAnalysis();
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.tune_rounded,
                  size: 16, color: Colors.white),
            ),
            SizedBox(height: Sp.sm),
            VtButton(
              label: 'Back to Dashboard',
              onPressed: () => Navigator.of(context).pop(),
              variant: VtButtonVariant.ghost,
            ),

            SizedBox(height: Sp.xl),
            Container(
              padding: EdgeInsets.all(Sp.md),
              decoration: BoxDecoration(
                color: context.vt.surface1,
                borderRadius: BorderRadius.circular(Rad.md),
                border: Border.all(color: context.vt.divider),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline_rounded,
                      color: context.vt.accentGold, size: 18),
                  SizedBox(width: Sp.sm),
                  Expanded(
                    child: Text(
                      'Market conditions change daily. Better setups often appear at different times or sectors.',
                      style: AppTextStyles.caption
                          .copyWith(color: context.vt.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReasonTile(
      IconData icon, Color color, String title, String body) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(Rad.sm),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: AppTextStyles.body
                      .copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(body, style: AppTextStyles.caption),
            ],
          ),
        ),
      ],
    );
  }

  // ── Business logic (unchanged) ─────────────────────────────────────────────

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

  bool _isMarketOpen() {
    final now = DateTime.now();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }
    final minuteOfDay = now.hour * 60 + now.minute;
    return minuteOfDay >= 9 * 60 + 15 && minuteOfDay < 15 * 60 + 30;
  }

  bool _isAmoWindow() {
    final now = DateTime.now();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return true;
    }
    final minuteOfDay = now.hour * 60 + now.minute;
    return minuteOfDay >= 15 * 60 + 45 || minuteOfDay < 9 * 60 + 15;
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

  Future<void> _showMarketClosedDialog(
      BuildContext context, String reason) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(Sp.sm),
              decoration: BoxDecoration(
                color: context.vt.warning.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.access_time_rounded,
                  color: context.vt.warning, size: 22),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Text('Market Closed',
                  style: AppTextStyles.h2),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reason, style: AppTextStyles.body),
            SizedBox(height: Sp.base),
            Container(
              padding: EdgeInsets.all(Sp.md),
              decoration: BoxDecoration(
                color: context.vt.surface2,
                borderRadius: BorderRadius.circular(Rad.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: context.vt.textSecondary),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: Text(
                      'NSE market hours:\nMonday – Friday, 9:15 AM – 3:30 PM IST',
                      style: AppTextStyles.caption,
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

  String _amoDialogBody() {
    final now = DateTime.now();
    final isWeekend =
        now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    if (isWeekend) {
      return 'Market is closed today (weekend). Your swing trade order will be '
          'placed as an AMO (After Market Order) and will execute at NSE market '
          'open on Monday (9:15 AM IST).';
    }
    final minuteOfDay = now.hour * 60 + now.minute;
    if (minuteOfDay < 9 * 60 + 15) {
      return 'Market has not opened yet. Your swing trade order will be placed '
          'as an AMO (After Market Order) and will execute at market open today '
          '(9:15 AM IST).';
    }
    return 'Market is currently closed. Your swing trade order will be placed '
        'as an AMO (After Market Order) and will execute at NSE market open '
        'tomorrow (9:15 AM IST).';
  }

  Future<bool> _showAmoConfirmDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(Sp.sm),
                  decoration: BoxDecoration(
                    color: context.vt.accentPurpleDim,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.schedule_rounded,
                      color: context.vt.accentPurple, size: 22),
                ),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: Text('Place After Market Order?',
                      style: AppTextStyles.h2),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_amoDialogBody(), style: AppTextStyles.body),
                SizedBox(height: Sp.md),
                Container(
                  padding: EdgeInsets.all(Sp.md),
                  decoration: BoxDecoration(
                    color: context.vt.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(Rad.md),
                    border: Border.all(
                        color: context.vt.warning.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 14, color: context.vt.warning),
                        SizedBox(width: Sp.xs),
                        Text('After order fills at market open:',
                            style: AppTextStyles.caption.copyWith(
                                color: context.vt.warning,
                                fontWeight: FontWeight.w600)),
                      ]),
                      SizedBox(height: Sp.xs),
                      Text(
                        '• Open Zerodha app and set Stop Loss + Target\n'
                        '  via GTT or SL order to protect your position.',
                        style: AppTextStyles.caption
                            .copyWith(color: context.vt.warning),
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
                  backgroundColor: context.vt.accentPurple,
                  foregroundColor: context.vt.surface0,
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
      if (isSwing && _isAmoWindow()) {
        final proceed = await _showAmoConfirmDialog(context);
        if (!proceed || !context.mounted) return;
      } else {
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
        setState(() {
          _confirmError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }
}

