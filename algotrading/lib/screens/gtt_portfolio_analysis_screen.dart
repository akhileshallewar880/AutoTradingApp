import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/dashboard_model.dart';
import 'gtt_analysis_screen.dart';

class GttPortfolioAnalysisScreen extends StatelessWidget {
  final List<GttModel> gtts;

  const GttPortfolioAnalysisScreen({super.key, required this.gtts});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

    // Compute per-GTT metrics
    final items = gtts.map((g) => _GttMetrics.from(g)).toList();

    // Portfolio totals
    final totalMaxProfit = items.fold(0.0, (s, m) => s + m.maxProfit);
    final totalMaxLoss   = items.fold(0.0, (s, m) => s + m.maxLoss.abs());
    final totalExposure  = items.fold(0.0, (s, m) => s + m.exposure);
    final overallRR      = totalMaxLoss > 0 ? totalMaxProfit / totalMaxLoss : 0.0;
    final twoLegCount    = items.where((m) => m.isTwoLeg).length;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'GTT Portfolio Analysis',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.deepPurple[700],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: gtts.isEmpty
          ? _buildEmpty()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Portfolio summary ──────────────────────────────────
                  _buildSummaryCard(
                    currency: currency,
                    totalMaxProfit: totalMaxProfit,
                    totalMaxLoss: totalMaxLoss,
                    totalExposure: totalExposure,
                    overallRR: overallRR,
                    total: items.length,
                    twoLegCount: twoLegCount,
                  ),
                  const SizedBox(height: 16),

                  // ── Risk bar ───────────────────────────────────────────
                  _buildRiskBar(totalMaxProfit, totalMaxLoss, currency),
                  const SizedBox(height: 16),

                  // ── Section header ────────────────────────────────────
                  _sectionHeader('Individual GTT Analysis',
                      Icons.alarm_on, Colors.deepPurple),
                  const SizedBox(height: 10),

                  // ── GTT cards ─────────────────────────────────────────
                  ...items.map(
                    (m) => _buildGttCard(context, m, currency),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // ── Summary card ───────────────────────────────────────────────────────────
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
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.deepPurple[700]!, Colors.deepPurple[400]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Portfolio Summary',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
                _badge('$total Active GTTs', Colors.white24),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _summaryStatBox(
                    label: 'Max Profit',
                    value: currency.format(totalMaxProfit),
                    color: Colors.greenAccent[100]!,
                    icon: Icons.trending_up,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _summaryStatBox(
                    label: 'Max Loss',
                    value: currency.format(totalMaxLoss),
                    color: Colors.red[200]!,
                    icon: Icons.trending_down,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _summaryStatBox(
                    label: 'Total Exposure',
                    value: currency.format(totalExposure),
                    color: Colors.white70,
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _summaryStatBox(
                    label: 'Risk / Reward',
                    value: overallRR > 0
                        ? '1 : ${overallRR.toStringAsFixed(2)}'
                        : 'N/A',
                    color: rrIsGood ? Colors.greenAccent[100]! : Colors.orange[200]!,
                    icon: Icons.balance,
                    note: overallRR > 0
                        ? (rrIsGood ? 'Favourable' : 'Below 1:2')
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _badge('$twoLegCount Two-leg', Colors.white24),
                const SizedBox(width: 8),
                _badge('${gtts.length - twoLegCount} Single', Colors.white24),
              ],
            ),
          ],
        ),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(color: color, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          if (note != null)
            Text(note,
                style: TextStyle(color: color, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _badge(String label, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  // ── Risk / Reward bar ──────────────────────────────────────────────────────
  Widget _buildRiskBar(
      double profit, double loss, NumberFormat currency) {
    final total = profit + loss;
    final profitFraction = total > 0 ? profit / total : 0.5;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart, color: Colors.deepPurple[700], size: 18),
                const SizedBox(width: 8),
                const Text('Profit vs Risk Distribution',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: profitFraction,
                backgroundColor: Colors.red[200],
                color: Colors.green[600],
                minHeight: 14,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: Colors.green[600],
                            shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('Profit: ${currency.format(profit)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                Row(
                  children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: Colors.red[200],
                            shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('Risk: ${currency.format(loss)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.red[600],
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Individual GTT card ────────────────────────────────────────────────────
  Widget _buildGttCard(
      BuildContext context, _GttMetrics m, NumberFormat currency) {
    final hasTarget = m.target > 0;
    final hasSl = m.stopLoss > 0;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => GttAnalysisScreen(gtt: m.gtt)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Card header ────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple[50],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      m.isTwoLeg ? Icons.swap_vert : Icons.alarm_on,
                      size: 20,
                      color: Colors.deepPurple[700],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(m.gtt.symbol,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            const SizedBox(width: 6),
                            _typeBadge(m.isTwoLeg),
                          ],
                        ),
                        Text(
                          'Qty: ${m.gtt.quantity}  •  LTP: ${currency.format(m.ltp)}  •  ${m.gtt.exchange}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 18, color: Colors.grey[400]),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // ── P&L stats row ──────────────────────────────────────────
              Row(
                children: [
                  if (hasTarget)
                    Expanded(
                      child: _statCell(
                        label: 'Max Profit',
                        value:
                            '+${currency.format(m.maxProfit)}',
                        sub:
                            '${m.targetPct >= 0 ? '+' : ''}${m.targetPct.toStringAsFixed(2)}%',
                        color: Colors.green[700]!,
                        icon: Icons.emoji_events_outlined,
                      ),
                    ),
                  if (hasTarget && hasSl)
                    const SizedBox(width: 8),
                  if (hasSl)
                    Expanded(
                      child: _statCell(
                        label: 'Max Loss',
                        value: currency.format(m.maxLoss.abs()),
                        sub:
                            '${m.slPct.toStringAsFixed(2)}%',
                        color: Colors.red[600]!,
                        icon: Icons.shield_outlined,
                      ),
                    ),
                  if ((hasTarget || hasSl) && m.riskReward > 0)
                    const SizedBox(width: 8),
                  if (m.riskReward > 0)
                    Expanded(
                      child: _statCell(
                        label: 'R:R',
                        value:
                            '1:${m.riskReward.toStringAsFixed(2)}',
                        sub: m.riskReward >= 2.0
                            ? 'Favourable'
                            : 'Below 1:2',
                        color: m.riskReward >= 2.0
                            ? Colors.green[700]!
                            : Colors.orange[700]!,
                        icon: Icons.balance,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              // ── Distance to triggers ───────────────────────────────────
              if (hasTarget || hasSl)
                Row(
                  children: [
                    if (hasTarget)
                      Expanded(
                        child: _distanceChip(
                          label: '📈 Target',
                          dist: m.distToTarget,
                          color: Colors.green[700]!,
                          bgColor: Colors.green[50]!,
                          reachedMsg: 'Target reached!',
                        ),
                      ),
                    if (hasTarget && hasSl)
                      const SizedBox(width: 8),
                    if (hasSl)
                      Expanded(
                        child: _distanceChip(
                          label: '🛡 Stop-Loss',
                          dist: m.distToSl,
                          color: Colors.red[600]!,
                          bgColor: Colors.red[50]!,
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 3),
              Text(label,
                  style:
                      TextStyle(fontSize: 10, color: Colors.grey[600])),
            ],
          ),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color)),
          Text(sub,
              style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }

  Widget _distanceChip({
    required String label,
    required double dist,
    required Color color,
    required Color bgColor,
    required String reachedMsg,
  }) {
    final text = dist > 0
        ? '${dist.toStringAsFixed(2)}% away'
        : reachedMsg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        TextStyle(fontSize: 10, color: Colors.grey[600])),
                Text(text,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeBadge(bool isTwoLeg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (isTwoLeg ? Colors.deepPurple : Colors.orange).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isTwoLeg ? 'TWO-LEG' : 'SINGLE',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: isTwoLeg ? Colors.deepPurple[700] : Colors.orange[700],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800])),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.alarm_off_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text('No active GTTs found',
              style: TextStyle(fontSize: 16, color: Colors.grey[500])),
          const SizedBox(height: 6),
          Text('GTT orders will appear here once active.',
              style: TextStyle(fontSize: 13, color: Colors.grey[400])),
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

    // Using LTP as avg price approximation (same as GttAnalysisScreen)
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
