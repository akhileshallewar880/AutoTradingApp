import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../models/holdings_model.dart';
import '../utils/api_config.dart';

class HoldingsScreen extends StatefulWidget {
  const HoldingsScreen({super.key});

  @override
  State<HoldingsScreen> createState() => _HoldingsScreenState();
}

class _HoldingsScreenState extends State<HoldingsScreen> {
  List<Holding> _holdings = [];
  HoldingsSummary? _summary;
  bool _loading = true;
  String? _error;

  final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _fetchHoldings();
  }

  Future<void> _fetchHoldings() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    setState(() { _loading = true; _error = null; });

    try {
      final uri = Uri.parse(ApiConfig.holdingsUrl).replace(queryParameters: {
        'api_key': auth.user!.apiKey,
        'access_token': auth.user!.accessToken,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = (data['holdings'] as List).cast<Map<String, dynamic>>();
        setState(() {
          _holdings = list.map(Holding.fromJson).toList();
          _summary = HoldingsSummary.fromJson(data['summary'] ?? {});
        });
      } else if (resp.statusCode == 403) {
        setState(() => _error = '__UPGRADE_REQUIRED__');
      } else {
        String msg = 'Failed to load holdings';
        try { msg = jsonDecode(resp.body)['detail'] ?? msg; } catch (_) {}
        setState(() => _error = msg);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Holdings'),
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchHoldings,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _holdings.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _fetchHoldings,
                      child: CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(child: _buildSummaryCard()),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (ctx, i) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _buildHoldingCard(_holdings[i]),
                                ),
                                childCount: _holdings.length,
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(
                              child: SizedBox(height: 24)),
                        ],
                      ),
                    ),
    );
  }

  // ── Summary Card ────────────────────────────────────────────────────────────

  Widget _buildSummaryCard() {
    if (_summary == null) return const SizedBox.shrink();
    final s = _summary!;
    final isProfit = s.totalPnl >= 0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo[700]!, Colors.indigo[500]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Portfolio Holdings',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            _currency.format(s.totalCurrentValue),
            style: const TextStyle(
                color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _summaryPill(
                'Invested',
                _currency.format(s.totalInvested),
                Colors.white.withValues(alpha: 0.25),
              ),
              const SizedBox(width: 8),
              _summaryPill(
                isProfit ? 'Total Gain' : 'Total Loss',
                '${isProfit ? '+' : ''}${_currency.format(s.totalPnl)} '
                    '(${s.overallPnlPct.toStringAsFixed(1)}%)',
                isProfit
                    ? Colors.green.withValues(alpha: 0.35)
                    : Colors.red.withValues(alpha: 0.35),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryPill(String label, String value, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 3),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // ── Holding Card ─────────────────────────────────────────────────────────────

  Widget _buildHoldingCard(Holding h) {
    final isProfit = h.pnl >= 0;
    final isDayUp = h.dayChange >= 0;
    final profitColor = isProfit ? Colors.green[700]! : Colors.red[700]!;
    final dayColor = isDayUp ? Colors.green[600]! : Colors.red[600]!;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(h.symbol,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                      '${h.exchange} · ${h.quantity} qty',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _currency.format(h.lastPrice),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Row(
                      children: [
                        Icon(
                          isDayUp ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 12,
                          color: dayColor,
                        ),
                        Text(
                          '${h.dayChangePct.abs().toStringAsFixed(2)}% today',
                          style: TextStyle(color: dayColor, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // ── Metrics row ─────────────────────────────────────────────
            Row(
              children: [
                _metric('Avg Buy', _currency.format(h.averagePrice)),
                _metric('Invested', _currency.format(h.investedValue)),
                _metric('Current', _currency.format(h.currentValue)),
              ],
            ),
            const SizedBox(height: 10),

            // ── P&L bar ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: profitColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: profitColor.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isProfit ? 'Total Gain' : 'Total Loss',
                    style: TextStyle(color: profitColor, fontSize: 13),
                  ),
                  Text(
                    '${isProfit ? '+' : ''}${_currency.format(h.pnl)} '
                    '(${h.pnlPct.toStringAsFixed(1)}%)',
                    style: TextStyle(
                        color: profitColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                ],
              ),
            ),

            // ── T+1 badge ───────────────────────────────────────────────
            if (h.t1Quantity > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber[300]!),
                ),
                child: Text(
                  'T+1: ${h.t1Quantity} shares pending settlement',
                  style: TextStyle(fontSize: 11, color: Colors.amber[900]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          Text(value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Empty / Error ────────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('No Holdings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'You have no long-term CNC holdings yet. '
              'Buy stocks with CNC product to see them here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    if (_error == '__UPGRADE_REQUIRED__') return _buildUpgradeCard();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
            const SizedBox(height: 12),
            Text(_error ?? 'Error',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red[700])),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchHoldings,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpgradeCard() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber[300]!),
              ),
              child: Column(
                children: [
                  Icon(Icons.workspace_premium, size: 56, color: Colors.amber[700]),
                  const SizedBox(height: 16),
                  const Text(
                    'Kite Connect Paid Plan Required',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Portfolio holdings require the Zerodha Kite Connect paid API subscription (₹2000/month). '
                    'Enable it from your Kite developer console.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _fetchHoldings,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber[700],
                      foregroundColor: Colors.white,
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
}
