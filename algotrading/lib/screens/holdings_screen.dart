import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart' show AuthProvider, kDemoAccessToken;
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
  String? _exitingSymbol;
  Timer? _ltpTimer;

  final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _fetchHoldings();
    _ltpTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshLtps());
  }

  @override
  void dispose() {
    _ltpTimer?.cancel();
    super.dispose();
  }

  // ── Data Fetching ─────────────────────────────────────────────────────────

  Future<void> _fetchHoldings() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) {
      if (mounted) setState(() { _loading = false; _error = 'Not logged in.'; });
      return;
    }

    setState(() { _loading = true; _error = null; });

    if (auth.user!.accessToken == kDemoAccessToken) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      setState(() {
        _holdings = _demoHoldings();
        _summary = _demoSummary();
        _loading = false;
      });
      return;
    }

    try {
      final uri = Uri.parse(ApiConfig.holdingsUrl).replace(queryParameters: {
        'api_key': auth.user!.apiKey,
        'access_token': auth.user!.accessToken,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final raw = (data['holdings'] as List? ?? []);
        final list = raw
            .whereType<Map<String, dynamic>>()
            .where((h) =>
                (h['quantity'] as num? ?? 0) > 0 ||
                (h['t1_quantity'] as num? ?? 0) > 0)
            .toList();
        setState(() {
          _holdings = list.map(Holding.fromJson).toList();
          _summary = HoldingsSummary.fromJson(
              (data['summary'] as Map<String, dynamic>?) ?? {});
          _loading = false;
        });
      } else if (resp.statusCode == 403) {
        setState(() { _error = '__UPGRADE_REQUIRED__'; _loading = false; });
      } else {
        String msg = 'Failed to load holdings';
        try { msg = (jsonDecode(resp.body) as Map)['detail'] ?? msg; } catch (_) {}
        setState(() { _error = msg; _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _refreshLtps() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.user == null || auth.user!.accessToken == kDemoAccessToken) return;

    final tokens = _holdings
        .where((h) => h.instrumentToken != null && h.instrumentToken! > 0)
        .map((h) => h.instrumentToken.toString())
        .join(',');
    if (tokens.isEmpty) return;

    try {
      final uri = Uri.parse(ApiConfig.tickerSnapshotUrl).replace(queryParameters: {
        'api_key': auth.user!.apiKey,
        'access_token': auth.user!.accessToken,
        'tokens': tokens,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (!mounted || resp.statusCode != 200) return;

      final snap = (jsonDecode(resp.body) as Map<String, dynamic>)['snapshot'] as Map<String, dynamic>? ?? {};
      setState(() {
        _holdings = _holdings.map((h) {
          final d = snap[h.instrumentToken?.toString() ?? ''] as Map<String, dynamic>?;
          if (d == null) return h;
          final ltp = (d['last_price'] as num?)?.toDouble() ?? h.lastPrice;
          final pnl = (ltp - h.averagePrice) * h.quantity;
          final pnlPct = h.averagePrice > 0 ? (ltp - h.averagePrice) / h.averagePrice * 100 : 0.0;
          return h.copyWith(
            lastPrice: double.parse(ltp.toStringAsFixed(2)),
            pnl: double.parse(pnl.toStringAsFixed(2)),
            pnlPct: double.parse(pnlPct.toStringAsFixed(2)),
            currentValue: double.parse((ltp * h.quantity).toStringAsFixed(2)),
          );
        }).toList();
      });
    } catch (_) {}
  }

  // ── Exit Actions ──────────────────────────────────────────────────────────

  Future<void> _exitHolding(Holding h) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit Holding'),
        content: Text(
          'Sell all ${h.quantity} shares of ${h.symbol} at market price?\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[600], foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Exit Now'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _exitingSymbol = h.symbol);

    try {
      final auth = context.read<AuthProvider>();
      final uri = Uri.parse(ApiConfig.exitHoldingUrl(h.symbol)).replace(queryParameters: {
        'api_key': auth.user!.apiKey,
        'access_token': auth.user!.accessToken,
      });
      final resp = await http.post(uri).timeout(const Duration(seconds: 20));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${h.symbol} exit order placed successfully'),
            backgroundColor: Colors.green[700],
          ),
        );
        _fetchHoldings();
      } else {
        String msg = 'Exit failed';
        try { msg = (jsonDecode(resp.body) as Map)['detail'] ?? msg; } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red[700]),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _exitingSymbol = null);
    }
  }

  Future<void> _exitAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit All Holdings'),
        content: Text(
          'Sell all ${_holdings.length} holdings at market price?\n\n'
          'This will place ${_holdings.length} SELL orders. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Exit All'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _exitingSymbol = '__ALL__');

    try {
      final auth = context.read<AuthProvider>();
      final uri = Uri.parse(ApiConfig.exitAllHoldingsUrl).replace(queryParameters: {
        'api_key': auth.user!.apiKey,
        'access_token': auth.user!.accessToken,
      });
      final resp = await http.post(uri).timeout(const Duration(seconds: 30));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Exit orders placed for all holdings'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchHoldings();
      } else {
        String msg = 'Exit all failed';
        try { msg = (jsonDecode(resp.body) as Map)['detail'] ?? msg; } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red[700]),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _exitingSymbol = null);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final isDemo = auth.user?.accessToken == kDemoAccessToken;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Holdings'),
            if (!isDemo) ...[
              const SizedBox(width: 8),
              _liveBadge(),
            ],
          ],
        ),
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
        actions: [
          if (_holdings.isNotEmpty && !isDemo)
            _exitingSymbol == '__ALL__'
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                  )
                : TextButton.icon(
                    onPressed: _exitAll,
                    icon: const Icon(Icons.exit_to_app, size: 16, color: Colors.white70),
                    label: const Text('Exit All', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
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
                                  child: _buildHoldingCard(_holdings[i], isDemo),
                                ),
                                childCount: _holdings.length,
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 24)),
                        ],
                      ),
                    ),
    );
  }

  Widget _liveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green[400],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5, height: 5,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
          const SizedBox(width: 3),
          const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ── Summary Card ────────────────────────────────────────────────────────────

  Widget _buildSummaryCard() {
    if (_summary == null) return const SizedBox.shrink();
    final s = _summary!;
    final isProfit = s.totalPnl >= 0;

    final gttHoldings = _holdings.where((h) => h.hasGtt && h.maxProfit != null && h.maxLoss != null).toList();
    final totalExpectedProfit = gttHoldings.fold(0.0, (sum, h) => sum + h.maxProfit!);
    final totalExpectedLoss   = gttHoldings.fold(0.0, (sum, h) => sum + h.maxLoss!);
    final gttCount = gttHoldings.length;

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
          if (gttCount > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined, size: 12, color: Colors.white70),
                      const SizedBox(width: 5),
                      Text(
                        'GTT Protection ($gttCount of ${_holdings.length} holdings)',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _gttSummaryTile(
                          label: 'Expected Profit',
                          value: '+${_currency.format(totalExpectedProfit)}',
                          color: Colors.greenAccent[100]!,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _gttSummaryTile(
                          label: 'Expected Loss',
                          value: _currency.format(totalExpectedLoss),
                          color: Colors.red[200]!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _gttSummaryTile({required String label, required String value, required Color color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 10)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _summaryPill(String label, String value, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 3),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // ── Holding Card ─────────────────────────────────────────────────────────────

  Widget _buildHoldingCard(Holding h, bool isDemo) {
    final isProfit = h.pnl >= 0;
    final isDayUp = h.dayChange >= 0;
    final profitColor = isProfit ? Colors.green[700]! : Colors.red[700]!;
    final dayColor = isDayUp ? Colors.green[600]! : Colors.red[600]!;
    final isExiting = _exitingSymbol == h.symbol;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Symbol + exchange + countdown
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(h.symbol,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(
                        '${h.exchange} · ${h.quantity} qty',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      if (h.daysLeft != null) ...[
                        const SizedBox(height: 4),
                        _daysLeftBadge(h.daysLeft!),
                      ],
                    ],
                  ),
                ),
                // Price + day change + exit button
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _currency.format(h.lastPrice),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Row(
                      children: [
                        Icon(
                          isDayUp ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 12, color: dayColor,
                        ),
                        Text(
                          '${h.dayChangePct.abs().toStringAsFixed(2)}% today',
                          style: TextStyle(color: dayColor, fontSize: 11),
                        ),
                      ],
                    ),
                    if (!isDemo) ...[
                      const SizedBox(height: 6),
                      isExiting
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : GestureDetector(
                              onTap: () => _exitHolding(h),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.red[300]!),
                                ),
                                child: Text(
                                  'Exit',
                                  style: TextStyle(
                                    color: Colors.red[700],
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // ── Metrics row ───────────────────────────────────────────────
            Row(
              children: [
                _metric('Avg Buy', _currency.format(h.averagePrice)),
                _metric('Invested', _currency.format(h.investedValue)),
                _metric('Current', _currency.format(h.currentValue)),
              ],
            ),
            const SizedBox(height: 10),

            // ── P&L bar ──────────────────────────────────────────────────
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

            // ── Expected Profit / Loss (from active GTT) ─────────────────
            const SizedBox(height: 10),
            if (h.hasGtt && h.maxProfit != null && h.maxLoss != null)
              _buildExpectedPnl(h)
            else
              _buildNoGttHint(),

            // ── T+1 badge ─────────────────────────────────────────────────
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

  Widget _daysLeftBadge(int daysLeft) {
    Color bg, fg;
    String label;
    if (daysLeft < 0) {
      bg = Colors.grey[100]!; fg = Colors.grey[600]!;
      label = 'Expired';
    } else if (daysLeft <= 2) {
      bg = Colors.red[50]!; fg = Colors.red[700]!;
      label = daysLeft == 0 ? 'Expires today!' : '$daysLeft day${daysLeft == 1 ? '' : 's'} left';
    } else if (daysLeft <= 5) {
      bg = Colors.orange[50]!; fg = Colors.orange[800]!;
      label = '$daysLeft days left';
    } else {
      bg = Colors.green[50]!; fg = Colors.green[700]!;
      label = '$daysLeft days left';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 10, color: fg),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildExpectedPnl(Holding h) {
    final profit = h.maxProfit!;
    final loss = h.maxLoss!;
    return Row(
      children: [
        Expanded(
          child: _pnlTile(
            label: 'Expected Profit',
            amount: profit,
            price: h.target!,
            color: Colors.green[700]!,
            icon: Icons.trending_up_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _pnlTile(
            label: 'Expected Loss',
            amount: loss,
            price: h.stopLoss!,
            color: Colors.red[600]!,
            icon: Icons.trending_down_rounded,
          ),
        ),
      ],
    );
  }

  Widget _pnlTile({
    required String label,
    required double amount,
    required double price,
    required Color color,
    required IconData icon,
  }) {
    final sign = amount >= 0 ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$sign${_currency.format(amount)}',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            '@ ${_currency.format(price)}',
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildNoGttHint() {
    return Row(
      children: [
        Icon(Icons.info_outline, size: 13, color: Colors.grey[400]),
        const SizedBox(width: 4),
        Text(
          'No active GTT — Expected P&L unavailable',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
      ],
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Demo Data ─────────────────────────────────────────────────────────────

  List<Holding> _demoHoldings() => [
        Holding(
          symbol: 'RELIANCE', exchange: 'NSE', isin: 'INE002A01018',
          quantity: 10, t1Quantity: 0, averagePrice: 2750.0, lastPrice: 2875.50,
          closePrice: 2860.0, pnl: 1255.0, pnlPct: 4.56,
          dayChange: 15.5, dayChangePct: 0.54,
          investedValue: 27500.0, currentValue: 28755.0, product: 'CNC',
          stopLoss: 2600.0, target: 3050.0,
          maxProfit: 3000.0, maxLoss: -1500.0,
          hasGtt: true, gttId: 'demo-1',
          daysLeft: 8,
        ),
        Holding(
          symbol: 'TCS', exchange: 'NSE', isin: 'INE467B01029',
          quantity: 5, t1Quantity: 0, averagePrice: 4100.0, lastPrice: 4389.75,
          closePrice: 4350.0, pnl: 1448.75, pnlPct: 7.07,
          dayChange: 39.75, dayChangePct: 0.91,
          investedValue: 20500.0, currentValue: 21948.75, product: 'CNC',
          stopLoss: 3900.0, target: 4600.0,
          maxProfit: 2500.0, maxLoss: -1000.0,
          hasGtt: true, gttId: 'demo-2',
          daysLeft: 3,
        ),
        Holding(
          symbol: 'INFY', exchange: 'NSE', isin: 'INE009A01021',
          quantity: 15, t1Quantity: 5, averagePrice: 1820.0, lastPrice: 1890.75,
          closePrice: 1875.0, pnl: 1061.25, pnlPct: 3.88,
          dayChange: 15.75, dayChangePct: 0.84,
          investedValue: 27300.0, currentValue: 28361.25, product: 'CNC',
          daysLeft: 1,
        ),
      ];

  HoldingsSummary _demoSummary() => HoldingsSummary(
        totalInvested: 75300.0,
        totalCurrentValue: 79065.0,
        totalPnl: 3765.0,
        overallPnlPct: 5.0,
      );

  // ── Empty / Error ──────────────────────────────────────────────────────────

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
              'No CNC delivery holdings found in your Zerodha account.\n\n'
              '• Holdings appear here after T+2 settlement\n'
              '• Intraday MIS positions are not shown here\n'
              '• Stocks bought today may appear tomorrow',
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
