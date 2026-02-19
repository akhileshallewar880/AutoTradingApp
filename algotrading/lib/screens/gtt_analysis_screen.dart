import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/dashboard_model.dart';

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
    final avgBuy = ltp; // best approximation without position data
    final stopLoss = (isTwoLeg && triggers.length >= 2) ? triggers[0] : (triggers.isNotEmpty ? triggers[0] : 0.0);
    final target = (isTwoLeg && triggers.length >= 2) ? triggers[1] : 0.0;
    final qty = gtt.quantity;

    // P&L calculations
    final currentPnl = (ltp - avgBuy) * qty;
    final maxProfit = target > 0 ? (target - avgBuy) * qty : 0.0;
    final maxLoss = stopLoss > 0 ? (stopLoss - avgBuy) * qty : 0.0;
    final riskReward = (maxLoss != 0 && maxProfit != 0)
        ? (maxProfit / maxLoss.abs()).abs()
        : 0.0;

    // % moves
    final pnlPct = avgBuy > 0 ? (ltp - avgBuy) / avgBuy * 100 : 0.0;
    final targetPct = avgBuy > 0 && target > 0 ? (target - avgBuy) / avgBuy * 100 : 0.0;
    final slPct = avgBuy > 0 && stopLoss > 0 ? (stopLoss - avgBuy) / avgBuy * 100 : 0.0;

    // Distance to trigger
    final distToTarget = target > 0 ? ((target - ltp) / ltp * 100) : 0.0;
    final distToSl = stopLoss > 0 ? ((ltp - stopLoss) / ltp * 100) : 0.0;

    final isCurrentPositive = currentPnl >= 0;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          '${gtt.symbol} — GTT Analysis',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.deepPurple[700],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header card ─────────────────────────────────────────────
            _buildHeaderCard(currency, ltp, qty, isTwoLeg),
            const SizedBox(height: 16),

            // ── Current P&L ─────────────────────────────────────────────
            _buildPnlCard(
              label: 'Current P&L',
              value: currentPnl,
              pct: pnlPct,
              subtitle: 'Based on LTP vs avg buy price',
              icon: isCurrentPositive ? Icons.trending_up : Icons.trending_down,
              color: isCurrentPositive ? Colors.green[700]! : Colors.red[600]!,
              currency: currency,
            ),
            const SizedBox(height: 12),

            // ── Target / Max Profit ─────────────────────────────────────
            if (target > 0) ...[
              _buildPnlCard(
                label: 'Max Profit (at Target)',
                value: maxProfit,
                pct: targetPct,
                subtitle: 'If price reaches ${currency.format(target)}',
                icon: Icons.emoji_events_outlined,
                color: Colors.green[700]!,
                currency: currency,
                extra: distToTarget > 0
                    ? '${distToTarget.toStringAsFixed(2)}% away from target'
                    : 'Target already reached!',
              ),
              const SizedBox(height: 12),
            ],

            // ── Max Loss ────────────────────────────────────────────────
            if (stopLoss > 0) ...[
              _buildPnlCard(
                label: 'Max Loss (at Stop-Loss)',
                value: maxLoss,
                pct: slPct,
                subtitle: 'If price hits SL at ${currency.format(stopLoss)}',
                icon: Icons.shield_outlined,
                color: Colors.red[600]!,
                currency: currency,
                extra: distToSl > 0
                    ? '${distToSl.toStringAsFixed(2)}% buffer before SL triggers'
                    : 'SL already triggered!',
              ),
              const SizedBox(height: 12),
            ],

            // ── Risk/Reward ─────────────────────────────────────────────
            if (riskReward > 0) ...[
              _buildRiskRewardCard(riskReward, maxProfit, maxLoss, currency),
              const SizedBox(height: 12),
            ],

            // ── Price levels ────────────────────────────────────────────
            _buildPriceLevelsCard(
              ltp: ltp,
              stopLoss: stopLoss,
              target: target,
              currency: currency,
            ),
            const SizedBox(height: 12),

            // ── GTT Details ─────────────────────────────────────────────
            _buildDetailsCard(currency),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
      NumberFormat currency, double ltp, int qty, bool isTwoLeg) {
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(gtt.symbol,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold)),
                    Text(gtt.exchange,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isTwoLeg ? 'TWO-LEG GTT' : 'SINGLE GTT',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: gtt.status.toLowerCase() == 'triggered'
                            ? Colors.amber.withOpacity(0.3)
                            : Colors.green.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        gtt.status.toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _headerStat('LTP', currency.format(ltp)),
                const SizedBox(width: 24),
                _headerStat('Qty', qty.toString()),
                const SizedBox(width: 24),
                _headerStat('Product', gtt.product),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(color: Colors.white60, fontSize: 11)),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildPnlCard({
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
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${isPositive ? '+' : ''}${currency.format(value)}',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: color),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${isPositive ? '+' : ''}${pct.toStringAsFixed(2)}%',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: color),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[500])),
                  if (extra != null) ...[
                    const SizedBox(height: 2),
                    Text(extra,
                        style: TextStyle(
                            fontSize: 11,
                            color: color,
                            fontWeight: FontWeight.w500)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskRewardCard(
      double rr, double maxProfit, double maxLoss, NumberFormat currency) {
    final isGood = rr >= 2.0;
    final color = isGood ? Colors.green[700]! : Colors.orange[700]!;
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
                Icon(Icons.balance, color: color, size: 18),
                const SizedBox(width: 8),
                const Text('Risk / Reward Ratio',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _rrBox(
                    label: 'Ratio',
                    value: '1 : ${rr.toStringAsFixed(2)}',
                    color: color,
                    note: isGood ? 'Favourable' : 'Below 1:2',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _rrBox(
                    label: 'Max Profit',
                    value: currency.format(maxProfit),
                    color: Colors.green[700]!,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _rrBox(
                    label: 'Max Loss',
                    value: currency.format(maxLoss.abs()),
                    color: Colors.red[600]!,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _rrBox(
      {required String label,
      required String value,
      required Color color,
      String? note}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color)),
          if (note != null)
            Text(note,
                style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }

  Widget _buildPriceLevelsCard(
      {required double ltp,
      required double stopLoss,
      required double target,
      required NumberFormat currency}) {
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
                Icon(Icons.linear_scale, color: Colors.blueGrey[700], size: 18),
                const SizedBox(width: 8),
                const Text('Price Levels',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 14),
            if (target > 0)
              _priceRow('Target', currency.format(target), Colors.green[700]!,
                  Icons.arrow_upward),
            _priceRow('Current (LTP)', currency.format(ltp),
                Colors.blue[700]!, Icons.radio_button_checked),
            if (stopLoss > 0)
              _priceRow('Stop-Loss', currency.format(stopLoss),
                  Colors.red[600]!, Icons.arrow_downward),
          ],
        ),
      ),
    );
  }

  Widget _priceRow(
      String label, String value, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]))),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }

  Widget _buildDetailsCard(NumberFormat currency) {
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
                Icon(Icons.info_outline, color: Colors.blueGrey[700], size: 18),
                const SizedBox(width: 8),
                const Text('GTT Details',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _detailRow('GTT ID', gtt.gttId),
            _detailRow('Type', gtt.gttType.toUpperCase()),
            _detailRow('Status', gtt.status.toUpperCase()),
            _detailRow('Transaction', gtt.transactionType),
            _detailRow('Quantity', gtt.quantity.toString()),
            _detailRow('Product', gtt.product),
            if (gtt.createdAt.isNotEmpty)
              _detailRow('Created', _formatDate(gtt.createdAt)),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
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
