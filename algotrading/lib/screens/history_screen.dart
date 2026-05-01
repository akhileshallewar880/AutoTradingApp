import '../theme/vt_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/analysis_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/status_badge.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      final analysisProvider = context.read<AnalysisProvider>();
      analysisProvider.loadHistory(authProvider.user!.accessToken);
    });
  }

  @override
  Widget build(BuildContext context) {
    final analysisProvider = context.watch<AnalysisProvider>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text('Analysis History', style: AppTextStyles.h2),
      ),
      body: analysisProvider.isLoading
          ? Center(
              child: CircularProgressIndicator(color: context.vt.accentGreen))
          : analysisProvider.history.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      Sp.base, Sp.sm, Sp.base, Sp.xxl),
                  itemCount: analysisProvider.history.length,
                  itemBuilder: (context, index) {
                    final item = analysisProvider.history[index];
                    return _HistoryTile(item: item, index: index);
                  },
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(Sp.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: context.vt.accentPurpleDim,
                shape: BoxShape.circle,
                border: Border.all(
                    color: context.vt.accentPurple.withValues(alpha: 0.2)),
              ),
              child: Icon(Icons.history_rounded,
                  size: 40, color: context.vt.accentPurple),
            ),
            const SizedBox(height: Sp.xl),
            Text('No History Yet',
                style: AppTextStyles.h2, textAlign: TextAlign.center),
            const SizedBox(height: Sp.sm),
            Text(
              'Your analysis history will appear here after you run your first AI analysis.',
              style: AppTextStyles.bodySecondary.copyWith(height: 1.6),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── History Tile ──────────────────────────────────────────────────────────────

class _HistoryTile extends StatelessWidget {
  _HistoryTile({required this.item, required this.index});
  final dynamic item;
  final int index;

  @override
  Widget build(BuildContext context) {
    final dateStr = item['created_at'] as String? ?? '';
    DateTime? date;
    try {
      date = DateTime.parse(dateStr).toLocal();
    } catch (_) {}

    final stocks = (item['stocks'] as List?)?.length ?? 0;
    final holdDays = item['hold_duration_days'] as int? ?? 0;
    final status = item['status'] as String? ?? 'unknown';
    final investment = (item['total_investment'] as num?)?.toDouble() ?? 0.0;
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    final holdLabel = holdDays == 0
        ? 'Intraday'
        : holdDays == 1
            ? '1 Day'
            : holdDays <= 7
                ? '${holdDays}D'
                : holdDays <= 30
                    ? '${(holdDays / 7).round()}W'
                    : '1M';

    BadgeType badgeType;
    switch (status.toUpperCase()) {
      case 'COMPLETED':
        badgeType = BadgeType.success;
        break;
      case 'FAILED':
        badgeType = BadgeType.danger;
        break;
      case 'PENDING':
      case 'RUNNING':
        badgeType = BadgeType.warning;
        break;
      default:
        badgeType = BadgeType.neutral;
    }

    return Container(
      margin: EdgeInsets.only(bottom: Sp.sm),
      padding: EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: context.vt.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: context.vt.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Date + time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date != null
                          ? DateFormat('EEE, dd MMM yyyy').format(date)
                          : 'Analysis ${index + 1}',
                      style: AppTextStyles.body
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (date != null)
                      Text(
                        DateFormat('hh:mm a').format(date),
                        style: AppTextStyles.caption,
                      ),
                  ],
                ),
              ),
              StatusBadge(label: status, type: badgeType),
            ],
          ),
          SizedBox(height: Sp.sm),
          Divider(height: 1, color: context.vt.divider),
          SizedBox(height: Sp.sm),
          Row(
            children: [
              _pill(Icons.show_chart_rounded, '$stocks stocks',
                  context.vt.accentGreen),
              SizedBox(width: Sp.sm),
              _pill(Icons.timer_outlined, holdLabel, context.vt.accentPurple),
              if (investment > 0) ...[
                SizedBox(width: Sp.sm),
                _pill(Icons.account_balance_wallet_outlined,
                    currency.format(investment), context.vt.textSecondary),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Sp.sm, vertical: Sp.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Rad.pill),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: AppTextStyles.caption
                  .copyWith(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}
