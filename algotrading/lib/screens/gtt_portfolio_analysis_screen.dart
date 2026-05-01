import '../theme/vt_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/dashboard_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'gtt_analysis_screen.dart';

class GttPortfolioAnalysisScreen extends StatelessWidget {
  final List<GttModel> gtts;

  GttPortfolioAnalysisScreen({super.key, required this.gtts});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

    final items = gtts.map((g) => _GttMetrics.from(g)).toList();

    final totalMaxProfit = items.fold(0.0, (s, m) => s + m.maxProfit);
    final totalMaxLoss   = items.fold(0.0, (s, m) => s + m.maxLoss.abs());
    final totalExposure  = items.fold(0.0, (s, m) => s + m.exposure);
    final overallRR      = totalMaxLoss > 0 ? totalMaxProfit / totalMaxLoss : 0.0;
    final twoLegCount    = items.where((m) => m.isTwoLeg).length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('GTT Portfolio Analysis', style: AppTextStyles.h2),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: context.vt.textPrimary,
        elevation: 0,
      ),
      body: gtts.isEmpty
          ? _buildEmpty()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(Sp.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryCard(
                    currency: currency,
                    totalMaxProfit: totalMaxProfit,
                    totalMaxLoss: totalMaxLoss,
                    totalExposure: totalExposure,
                    overallRR: overallRR,
                    total: items.length,
                    twoLegCount: twoLegCount,
                  ),
                  const SizedBox(height: Sp.base),

                  _buildRiskBar(totalMaxProfit, totalMaxLoss, currency),
                  const SizedBox(height: Sp.base),

                  _sectionHeader('Individual GTT Analysis', Icons.alarm_on),
                  const SizedBox(height: Sp.sm),

                  ...items.map((m) => _buildGttCard(context, m, currency)),
                  const SizedBox(height: Sp.xxl),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard({
    required NumberFormat currency,
    required double totalMaxProfit,
    required double totalMaxLoss,
    required double totalExposure,
    required double overallRR,
    required int total,
    required int twoLegCount,
  }) {
    final rrIsGood = overallRR >= 2.0;
    return Container(
      decoration: BoxDecoration(
        color: context.vt.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: context.vt.accentPurple.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: context.vt.accentPurple.withValues(alpha: 0.12),
            blurRadius: 16,
            spreadRadius: -2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Portfolio Summary', style: AppTextStyles.caption),
              _badge('$total Active GTTs'),
            ],
          ),
          SizedBox(height: Sp.md),
          Row(
            children: [
              Expanded(
                child: _summaryStatBox(
                  label: 'Max Profit',
                  value: currency.format(totalMaxProfit),
                  color: context.vt.accentGreen,
                  icon: Icons.trending_up,
                ),
              ),
              SizedBox(width: Sp.sm),
              Expanded(
                child: _summaryStatBox(
                  label: 'Max Loss',
                  value: currency.format(totalMaxLoss),
                  color: context.vt.danger,
                  icon: Icons.trending_down,
                ),
              ),
            ],
          ),
          SizedBox(height: Sp.sm),
          Row(
            children: [
              Expanded(
                child: _summaryStatBox(
                  label: 'Total Exposure',
                  value: currency.format(totalExposure),
                  color: context.vt.textSecondary,
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ),
              SizedBox(width: Sp.sm),
              Expanded(
                child: _summaryStatBox(
                  label: 'Risk / Reward',
                  value: overallRR > 0
                      ? '1 : ${overallRR.toStringAsFixed(2)}'
                      : 'N/A',
                  color: rrIsGood ? context.vt.accentGreen : context.vt.warning,
                  icon: Icons.balance,
                  note: overallRR > 0
                      ? (rrIsGood ? 'Favourable' : 'Below 1:2')
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.md),
          Row(
            children: [
              _badge('$twoLegCount Two-leg'),
              const SizedBox(width: Sp.sm),
              _badge('${gtts.length - twoLegCount} Single'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryStatBox({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
    String? note,
  }) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 4),
              Text(label, style: AppTextStyles.caption.copyWith(color: color)),
            ],
          ),
          SizedBox(height: 4),
          Text(value,
              style: AppTextStyles.mono.copyWith(
                  fontSize: 14, fontWeight: FontWeight.bold, color: context.vt.textPrimary)),
          if (note != null)
            Text(note, style: AppTextStyles.caption.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _badge(String label) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs),
      decoration: BoxDecoration(
        color: context.vt.accentPurple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Rad.pill),
        border: Border.all(color: context.vt.accentPurple.withValues(alpha: 0.25)),
      ),
      child: Text(label,
          style: AppTextStyles.caption.copyWith(
              color: context.vt.accentPurple, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildRiskBar(double profit, double loss, NumberFormat currency) {
    final total = profit + loss;
    final profitFraction = total > 0 ? profit / total : 0.5;

    return Container(
      padding: EdgeInsets.all(Sp.base),
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
              Icon(Icons.bar_chart, color: context.vt.accentPurple, size: 18),
              const SizedBox(width: Sp.sm),
              Text('Profit vs Risk Distribution', style: AppTextStyles.h3),
            ],
          ),
          SizedBox(height: Sp.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: profitFraction,
              backgroundColor: context.vt.danger.withValues(alpha: 0.3),
              color: context.vt.accentGreen,
              minHeight: 14,
            ),
          ),
          SizedBox(height: Sp.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: context.vt.accentGreen,
                          shape: BoxShape.circle)),
                  SizedBox(width: 4),
                  Text('Profit: ${currency.format(profit)}',
                      style: AppTextStyles.caption.copyWith(
                          color: context.vt.accentGreen,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              Row(
                children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: context.vt.danger,
                          shape: BoxShape.circle)),
                  SizedBox(width: 4),
                  Text('Risk: ${currency.format(loss)}',
                      style: AppTextStyles.caption.copyWith(
                          color: context.vt.danger,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGttCard(BuildContext context, _GttMetrics m, NumberFormat currency) {
    final hasTarget = m.target > 0;
    final hasSl = m.stopLoss > 0;

    return Container(
      margin: EdgeInsets.only(bottom: Sp.md),
      decoration: BoxDecoration(
        color: context.vt.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: context.vt.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Rad.lg),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GttAnalysisScreen(gtt: m.gtt)),
        ),
        child: Padding(
          padding: EdgeInsets.all(Sp.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(Sp.sm),
                    decoration: BoxDecoration(
                      color: context.vt.accentPurpleDim,
                      borderRadius: BorderRadius.circular(Rad.sm),
                    ),
                    child: Icon(
                      m.isTwoLeg ? Icons.swap_vert : Icons.alarm_on,
                      size: 20,
                      color: context.vt.accentPurple,
                    ),
                  ),
                  SizedBox(width: Sp.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(m.gtt.symbol,
                                style: AppTextStyles.h3),
                            const SizedBox(width: 6),
                            _typeBadge(m.isTwoLeg),
                          ],
                        ),
                        Text(
                          'Qty: ${m.gtt.quantity}  •  LTP: ${currency.format(m.ltp)}  •  ${m.gtt.exchange}',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 18, color: context.vt.textTertiary),
                ],
              ),
              SizedBox(height: Sp.md),
              Divider(height: 1, color: context.vt.divider),
              SizedBox(height: Sp.md),

              Row(
                children: [
                  if (hasTarget)
                    Expanded(
                      child: _statCell(
                        label: 'Max Profit',
                        value: '+${currency.format(m.maxProfit)}',
                        sub: '${m.targetPct >= 0 ? '+' : ''}${m.targetPct.toStringAsFixed(2)}%',
                        color: context.vt.accentGreen,
                        icon: Icons.emoji_events_outlined,
                      ),
                    ),
                  if (hasTarget && hasSl) SizedBox(width: Sp.sm),
                  if (hasSl)
                    Expanded(
                      child: _statCell(
                        label: 'Max Loss',
                        value: currency.format(m.maxLoss.abs()),
                        sub: '${m.slPct.toStringAsFixed(2)}%',
                        color: context.vt.danger,
                        icon: Icons.shield_outlined,
                      ),
                    ),
                  if ((hasTarget || hasSl) && m.riskReward > 0)
                    SizedBox(width: Sp.sm),
                  if (m.riskReward > 0)
                    Expanded(
                      child: _statCell(
                        label: 'R:R',
                        value: '1:${m.riskReward.toStringAsFixed(2)}',
                        sub: m.riskReward >= 2.0 ? 'Favourable' : 'Below 1:2',
                        color: m.riskReward >= 2.0
                            ? context.vt.accentGreen
                            : context.vt.warning,
                        icon: Icons.balance,
                      ),
                    ),
                ],
              ),
              SizedBox(height: Sp.sm),

              if (hasTarget || hasSl)
                Row(
                  children: [
                    if (hasTarget)
                      Expanded(
                        child: _distanceChip(
                          label: '📈 Target',
                          dist: m.distToTarget,
                          color: context.vt.accentGreen,
                          reachedMsg: 'Target reached!',
                        ),
                      ),
                    if (hasTarget && hasSl) SizedBox(width: Sp.sm),
                    if (hasSl)
                      Expanded(
                        child: _distanceChip(
                          label: '🛡 Stop-Loss',
                          dist: m.distToSl,
                          color: context.vt.danger,
                          reachedMsg: 'SL triggered!',
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCell({
    required String label,
    required String value,
    required String sub,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(Sp.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Rad.sm),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 3),
              Text(label, style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: 3),
          Text(value,
              style: AppTextStyles.mono.copyWith(
                  fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          Text(sub, style: AppTextStyles.caption.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _distanceChip({
    required String label,
    required double dist,
    required Color color,
    required String reachedMsg,
  }) {
    final text = dist > 0 ? '${dist.toStringAsFixed(2)}% away' : reachedMsg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Rad.sm),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption),
          Text(text,
              style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _typeBadge(bool isTwoLeg) {
    final color = isTwoLeg ? context.vt.accentPurple : context.vt.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Rad.sm),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        isTwoLeg ? 'TWO-LEG' : 'SINGLE',
        style: AppTextStyles.caption.copyWith(
            fontSize: 9, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: context.vt.accentPurple),
        const SizedBox(width: 6),
        Text(title, style: AppTextStyles.h3),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.alarm_off_outlined,
              size: 64, color: context.vt.textTertiary),
          const SizedBox(height: Sp.md),
          Text('No active GTTs found', style: AppTextStyles.h3),
          const SizedBox(height: 6),
          Text('GTT orders will appear here once active.',
              style: AppTextStyles.bodySecondary),
        ],
      ),
    );
  }
}

// ── Per-GTT metric helper ──────────────────────────────────────────────────
class _GttMetrics {
  final GttModel gtt;
  final bool isTwoLeg;
  final double ltp;
  final double stopLoss;
  final double target;
  final double maxProfit;
  final double maxLoss;
  final double riskReward;
  final double targetPct;
  final double slPct;
  final double distToTarget;
  final double distToSl;
  final double exposure;

  const _GttMetrics({
    required this.gtt,
    required this.isTwoLeg,
    required this.ltp,
    required this.stopLoss,
    required this.target,
    required this.maxProfit,
    required this.maxLoss,
    required this.riskReward,
    required this.targetPct,
    required this.slPct,
    required this.distToTarget,
    required this.distToSl,
    required this.exposure,
  });

  factory _GttMetrics.from(GttModel g) {
    final isTwoLeg = g.gttType.toLowerCase().contains('two');
    final triggers = g.triggerValues;
    final ltp = g.lastPrice;
    final qty = g.quantity;

    final sl = (isTwoLeg && triggers.length >= 2)
        ? triggers[0]
        : (triggers.isNotEmpty ? triggers[0] : 0.0);
    final target = (isTwoLeg && triggers.length >= 2) ? triggers[1] : 0.0;

    final maxProfit = target > 0 ? (target - ltp) * qty : 0.0;
    final maxLoss   = sl > 0 ? (sl - ltp) * qty : 0.0;

    final riskReward = (maxLoss.abs() > 0 && maxProfit > 0)
        ? maxProfit / maxLoss.abs()
        : 0.0;

    final targetPct =
        ltp > 0 && target > 0 ? (target - ltp) / ltp * 100 : 0.0;
    final slPct = ltp > 0 && sl > 0 ? (sl - ltp) / ltp * 100 : 0.0;

    final distToTarget =
        target > 0 ? (target - ltp) / ltp * 100 : 0.0;
    final distToSl =
        sl > 0 ? (ltp - sl) / ltp * 100 : 0.0;

    final exposure = ltp * qty;

    return _GttMetrics(
      gtt: g,
      isTwoLeg: isTwoLeg,
      ltp: ltp,
      stopLoss: sl,
      target: target,
      maxProfit: maxProfit,
      maxLoss: maxLoss,
      riskReward: riskReward,
      targetPct: targetPct,
      slPct: slPct,
      distToTarget: distToTarget,
      distToSl: distToSl,
      exposure: exposure,
    );
  }
}
