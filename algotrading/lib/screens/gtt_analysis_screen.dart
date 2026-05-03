import '../theme/vt_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/dashboard_model.dart';
import '../providers/dashboard_provider.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

class GttAnalysisScreen extends StatelessWidget {
  final GttModel gtt;

  const GttAnalysisScreen({super.key, required this.gtt});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
    final isTwoLeg = gtt.gttType.toLowerCase().contains('two');
    final triggers = gtt.triggerValues;

    // Prices
    final ltp = gtt.lastPrice;
    final stopLoss = (isTwoLeg && triggers.length >= 2) ? triggers[0] : (triggers.isNotEmpty ? triggers[0] : 0.0);
    final target = (isTwoLeg && triggers.length >= 2) ? triggers[1] : 0.0;
    final qty = gtt.quantity;

    // Try to find avg buy price from an open position with the same symbol
    final positions = context.read<DashboardProvider>().dashboard?.positions ?? [];
    final matchedPos = positions.where((p) => p.symbol == gtt.symbol).firstOrNull;
    final avgBuy = matchedPos?.avgPrice ?? 0.0;
    final hasBuyPrice = avgBuy > 0;

    // P&L calculations (only meaningful when avgBuy is known)
    final currentPnl = hasBuyPrice ? (ltp - avgBuy) * qty : 0.0;
    final maxProfit = target > 0 ? (target - (hasBuyPrice ? avgBuy : ltp)) * qty : 0.0;
    final maxLoss = stopLoss > 0 ? (stopLoss - (hasBuyPrice ? avgBuy : ltp)) * qty : 0.0;
    final riskReward = (maxLoss != 0 && maxProfit != 0)
        ? (maxProfit / maxLoss.abs()).abs()
        : 0.0;

    // % moves
    final pnlPct = hasBuyPrice ? (ltp - avgBuy) / avgBuy * 100 : 0.0;
    final targetPct = hasBuyPrice && target > 0 ? (target - avgBuy) / avgBuy * 100 : 0.0;
    final slPct = hasBuyPrice && stopLoss > 0 ? (stopLoss - avgBuy) / avgBuy * 100 : 0.0;

    // Distance to trigger
    final distToTarget = target > 0 ? ((target - ltp) / ltp * 100) : 0.0;
    final distToSl = stopLoss > 0 ? ((ltp - stopLoss) / ltp * 100) : 0.0;

    final isCurrentPositive = currentPnl >= 0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          '${gtt.symbol} — GTT Analysis',
          style: AppTextStyles.h2,
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: context.vt.textPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Sp.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderCard(context, currency, ltp, qty, isTwoLeg),
            SizedBox(height: Sp.base),

            hasBuyPrice
                ? _buildPnlCard(context,
                    label: 'Current P&L',
                    value: currentPnl,
                    pct: pnlPct,
                    subtitle:
                        'Based on avg buy ${currency.format(avgBuy)} vs LTP',
                    icon: isCurrentPositive
                        ? Icons.trending_up
                        : Icons.trending_down,
                    color: isCurrentPositive
                        ? context.vt.accentGreen
                        : context.vt.danger,
                    currency: currency,
                  )
                : _buildNoPnlCard(context),
            SizedBox(height: Sp.md),

            if (target > 0) ...[
              _buildPnlCard(context, 
                label: 'Max Profit (at Target)',
                value: maxProfit,
                pct: targetPct,
                subtitle: 'If price reaches ${currency.format(target)}',
                icon: Icons.emoji_events_outlined,
                color: context.vt.accentGreen,
                currency: currency,
                extra: distToTarget > 0
                    ? '${distToTarget.toStringAsFixed(2)}% away from target'
                    : 'Target already reached!',
              ),
              SizedBox(height: Sp.md),
            ],

            if (stopLoss > 0) ...[
              _buildPnlCard(context, 
                label: 'Max Loss (at Stop-Loss)',
                value: maxLoss,
                pct: slPct,
                subtitle: 'If price hits SL at ${currency.format(stopLoss)}',
                icon: Icons.shield_outlined,
                color: context.vt.danger,
                currency: currency,
                extra: distToSl > 0
                    ? '${distToSl.toStringAsFixed(2)}% buffer before SL triggers'
                    : 'SL already triggered!',
              ),
              const SizedBox(height: Sp.md),
            ],

            if (riskReward > 0) ...[
              _buildRiskRewardCard(context, riskReward, maxProfit, maxLoss, currency),
              const SizedBox(height: Sp.md),
            ],

            _buildPriceLevelsCard(context, 
              ltp: ltp,
              stopLoss: stopLoss,
              target: target,
              currency: currency,
            ),
            const SizedBox(height: Sp.md),

            _buildDetailsCard(context, currency),
            const SizedBox(height: Sp.xxl),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context, 
      NumberFormat currency, double ltp, int qty, bool isTwoLeg) {
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
      padding: EdgeInsets.all(Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(gtt.symbol,
                      style: AppTextStyles.display
                          .copyWith(fontSize: 26, color: context.vt.textPrimary)),
                  Text(gtt.exchange, style: AppTextStyles.caption),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Sp.sm, vertical: Sp.xs),
                    decoration: BoxDecoration(
                      color: context.vt.accentPurple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(Rad.pill),
                      border: Border.all(
                          color: context.vt.accentPurple.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      isTwoLeg ? 'TWO-LEG GTT' : 'SINGLE GTT',
                      style: AppTextStyles.caption.copyWith(
                          color: context.vt.accentPurple,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Sp.sm, vertical: Sp.xs),
                    decoration: BoxDecoration(
                      color: gtt.status.toLowerCase() == 'triggered'
                          ? context.vt.warning.withValues(alpha: 0.15)
                          : context.vt.accentGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(Rad.pill),
                      border: Border.all(
                        color: gtt.status.toLowerCase() == 'triggered'
                            ? context.vt.warning.withValues(alpha: 0.3)
                            : context.vt.accentGreen.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      gtt.status.toUpperCase(),
                      style: AppTextStyles.caption.copyWith(
                        color: gtt.status.toLowerCase() == 'triggered'
                            ? context.vt.warning
                            : context.vt.accentGreen,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: Sp.base),
          Row(
            children: [
              _headerStat(context, 'LTP', currency.format(ltp)),
              const SizedBox(width: Sp.xxl),
              _headerStat(context, 'Qty', qty.toString()),
              const SizedBox(width: Sp.xxl),
              _headerStat(context, 'Product', gtt.product),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerStat(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.caption),
        Text(value,
            style: AppTextStyles.mono
                .copyWith(color: context.vt.textPrimary, fontSize: 15)),
      ],
    );
  }

  Widget _buildPnlCard(BuildContext context, {
    required String label,
    required double value,
    required double pct,
    required String subtitle,
    required IconData icon,
    required Color color,
    required NumberFormat currency,
    String? extra,
  }) {
    final isPositive = value >= 0;
    return Container(
      padding: EdgeInsets.all(Sp.base),
      decoration: BoxDecoration(
        color: context.vt.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: context.vt.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Rad.md),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: Sp.base),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.caption),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${isPositive ? '+' : ''}${currency.format(value)}',
                      style: AppTextStyles.mono.copyWith(
                          fontSize: 20, fontWeight: FontWeight.bold, color: color),
                    ),
                    const SizedBox(width: Sp.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(Rad.sm),
                      ),
                      child: Text(
                        '${isPositive ? '+' : ''}${pct.toStringAsFixed(2)}%',
                        style: AppTextStyles.caption.copyWith(
                            fontWeight: FontWeight.bold, color: color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: AppTextStyles.caption),
                if (extra != null) ...[
                  const SizedBox(height: 2),
                  Text(extra,
                      style: AppTextStyles.caption.copyWith(
                          color: color, fontWeight: FontWeight.w500)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoPnlCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.base),
      decoration: BoxDecoration(
        color: context.vt.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: context.vt.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              color: context.vt.textTertiary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Rad.md),
            ),
            child: Icon(Icons.link_off_rounded,
                color: context.vt.textTertiary, size: 28),
          ),
          const SizedBox(width: Sp.base),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current P&L', style: AppTextStyles.caption),
                const SizedBox(height: 4),
                Text('Not available',
                    style: AppTextStyles.mono.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.vt.textTertiary)),
                const SizedBox(height: 4),
                Text(
                  'No open position found for ${gtt.symbol}. '
                  'P&L shows once position is active.',
                  style: AppTextStyles.caption
                      .copyWith(color: context.vt.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskRewardCard(BuildContext context,
      double rr, double maxProfit, double maxLoss, NumberFormat currency) {
    final isGood = rr >= 2.0;
    final color = isGood ? context.vt.accentGreen : context.vt.warning;
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
              Icon(Icons.balance, color: color, size: 18),
              const SizedBox(width: Sp.sm),
              Text('Risk / Reward Ratio', style: AppTextStyles.h3),
            ],
          ),
          const SizedBox(height: Sp.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _rrBox(
                    label: 'Ratio',
                    value: '1 : ${rr.toStringAsFixed(2)}',
                    color: color,
                    note: isGood ? 'Favourable' : 'Below 1:2',
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: _rrBox(
                    label: 'Max Profit',
                    value: currency.format(maxProfit),
                    color: context.vt.accentGreen,
                    note: '',
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: _rrBox(
                    label: 'Max Loss',
                    value: currency.format(maxLoss.abs()),
                    color: context.vt.danger,
                    note: '',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rrBox(
      {required String label,
      required String value,
      required Color color,
      String? note}) {
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
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: 4),
          Text(value,
              style: AppTextStyles.mono
                  .copyWith(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          if (note != null && note.isNotEmpty)
            Text(note,
                style: AppTextStyles.caption.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _buildPriceLevelsCard(BuildContext context, 
      {required double ltp,
      required double stopLoss,
      required double target,
      required NumberFormat currency}) {
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
              Icon(Icons.linear_scale, color: context.vt.textSecondary, size: 18),
              const SizedBox(width: Sp.sm),
              Text('Price Levels', style: AppTextStyles.h3),
            ],
          ),
          SizedBox(height: Sp.md),
          if (target > 0)
            _priceRow(context, 'Target', currency.format(target), context.vt.accentGreen,
                Icons.arrow_upward),
          _priceRow(context, 'Current (LTP)', currency.format(ltp),
              context.vt.accentPurple, Icons.radio_button_checked),
          if (stopLoss > 0)
            _priceRow(context, 'Stop-Loss', currency.format(stopLoss),
                context.vt.danger, Icons.arrow_downward),
        ],
      ),
    );
  }

  Widget _priceRow(BuildContext context, String label, String value, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: Sp.sm),
          Expanded(
              child: Text(label, style: AppTextStyles.body)),
          Text(value,
              style: AppTextStyles.mono.copyWith(
                  fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildDetailsCard(BuildContext context, NumberFormat currency) {
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
              Icon(Icons.info_outline, color: context.vt.textSecondary, size: 18),
              const SizedBox(width: Sp.sm),
              Text('GTT Details', style: AppTextStyles.h3),
            ],
          ),
          const SizedBox(height: Sp.md),
          _detailRow(context, 'GTT ID', gtt.gttId),
          _detailRow(context, 'Type', gtt.gttType.toUpperCase()),
          _detailRow(context, 'Status', gtt.status.toUpperCase()),
          _detailRow(context, 'Transaction', gtt.transactionType),
          _detailRow(context, 'Quantity', gtt.quantity.toString()),
          _detailRow(context, 'Product', gtt.product),
          if (gtt.createdAt.isNotEmpty)
            _detailRow(context, 'Created', _formatDate(gtt.createdAt)),
        ],
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodySecondary),
          Text(value,
              style: AppTextStyles.body
                  .copyWith(fontWeight: FontWeight.w600, color: context.vt.textPrimary)),
        ],
      ),
    );
  }

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      return DateFormat('dd MMM yyyy, HH:mm').format(dt);
    } catch (_) {
      return raw;
    }
  }
}
