import '../theme/vt_color_scheme.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart' show AuthProvider, kDemoAccessToken;
import '../models/holdings_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../utils/api_config.dart';
import '../widgets/status_badge.dart';
import '../widgets/vt_button.dart';

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
    _ltpTimer =
        Timer.periodic(Duration(seconds: 30), (_) => _refreshLtps());
  }

  @override
  void dispose() {
    _ltpTimer?.cancel();
    super.dispose();
  }

  // ── Data Fetching ──────────────────────────────────────────────────────────

  Future<void> _fetchHoldings() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Not logged in.';
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    if (auth.user!.accessToken == kDemoAccessToken) {
      await Future.delayed(Duration(milliseconds: 400));
      if (!mounted) return;
      setState(() {
        _holdings = _demoHoldings();
        _summary = _demoSummary();
        _loading = false;
      });
      return;
    }

    try {
      final uri =
          Uri.parse(ApiConfig.holdingsUrl).replace(queryParameters: {
        'api_key': auth.user!.apiKey,
        'access_token': auth.user!.accessToken,
      });
      final resp = await http.get(uri).timeout(Duration(seconds: 20));

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
        setState(() {
          _error = '__UPGRADE_REQUIRED__';
          _loading = false;
        });
      } else {
        String msg = 'Failed to load holdings';
        try {
          msg = (jsonDecode(resp.body) as Map)['detail'] ?? msg;
        } catch (_) {}
        setState(() {
          _error = msg;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
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
      final uri =
          Uri.parse(ApiConfig.tickerSnapshotUrl).replace(queryParameters: {
        'api_key': auth.user!.apiKey,
        'access_token': auth.user!.accessToken,
        'tokens': tokens,
      });
      final resp = await http.get(uri).timeout(Duration(seconds: 10));
      if (!mounted || resp.statusCode != 200) return;

      final snap = (jsonDecode(resp.body) as Map<String, dynamic>)['snapshot']
              as Map<String, dynamic>? ??
          {};
      setState(() {
        _holdings = _holdings.map((h) {
          final d = snap[h.instrumentToken?.toString() ?? '']
              as Map<String, dynamic>?;
          if (d == null) return h;
          final ltp =
              (d['last_price'] as num?)?.toDouble() ?? h.lastPrice;
          final pnl = (ltp - h.averagePrice) * h.quantity;
          final pnlPct = h.averagePrice > 0
              ? (ltp - h.averagePrice) / h.averagePrice * 100
              : 0.0;
          return h.copyWith(
            lastPrice: double.parse(ltp.toStringAsFixed(2)),
            pnl: double.parse(pnl.toStringAsFixed(2)),
            pnlPct: double.parse(pnlPct.toStringAsFixed(2)),
            currentValue:
                double.parse((ltp * h.quantity).toStringAsFixed(2)),
          );
        }).toList();
      });
    } catch (_) {}
  }

  // ── Exit Actions ───────────────────────────────────────────────────────────

  Future<void> _exitHolding(Holding h) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Exit Holding'),
        content: Text(
          'Sell all ${h.quantity} shares of ${h.symbol} at current price (limit order).\n\n'
          'The order will fill immediately for liquid stocks. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: context.vt.danger,
                foregroundColor: context.vt.textPrimary),
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
      final uri =
          Uri.parse(ApiConfig.exitHoldingUrl(h.symbol)).replace(queryParameters: {
        'api_key': auth.user!.apiKey,
        'access_token': auth.user!.accessToken,
      });
      final resp = await http.post(uri).timeout(Duration(seconds: 20));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${h.symbol} exit order placed successfully'),
          backgroundColor: context.vt.accentGreen,
        ));
        _fetchHoldings();
      } else {
        String msg = 'Exit failed';
        try {
          msg = (jsonDecode(resp.body) as Map)['detail'] ?? msg;
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: context.vt.danger));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), backgroundColor: context.vt.danger));
      }
    } finally {
      if (mounted) setState(() => _exitingSymbol = null);
    }
  }

  Future<void> _exitAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Exit All Holdings'),
        content: Text(
          'Sell all ${_holdings.length} holdings at market price?\n\n'
          'This will place ${_holdings.length} SELL orders. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: context.vt.danger,
                foregroundColor: context.vt.textPrimary),
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
      final uri =
          Uri.parse(ApiConfig.exitAllHoldingsUrl).replace(queryParameters: {
        'api_key': auth.user!.apiKey,
        'access_token': auth.user!.accessToken,
      });
      final resp = await http.post(uri).timeout(Duration(seconds: 30));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Exit orders placed for all holdings'),
          backgroundColor: context.vt.accentGreen,
        ));
        _fetchHoldings();
      } else {
        String msg = 'Exit all failed';
        try {
          msg = (jsonDecode(resp.body) as Map)['detail'] ?? msg;
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: context.vt.danger));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), backgroundColor: context.vt.danger));
      }
    } finally {
      if (mounted) setState(() => _exitingSymbol = null);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final isDemo = auth.user?.accessToken == kDemoAccessToken;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Row(
          children: [
            Text('Holdings', style: AppTextStyles.h2),
            if (!isDemo) ...[
              const SizedBox(width: Sp.sm),
              const StatusBadge(
                label: 'LIVE',
                type: BadgeType.success,
                pulseDot: true,
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: context.vt.accentGreen, size: 20),
            onPressed: _fetchHoldings,
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: context.vt.accentGreen))
          : _error != null
              ? _buildError()
              : _holdings.isEmpty
                  ? _buildEmpty()
                  : Column(
                      children: [
                        Expanded(
                          child: RefreshIndicator(
                            color: context.vt.accentGreen,
                            backgroundColor: context.vt.surface1,
                            onRefresh: _fetchHoldings,
                            child: CustomScrollView(
                              slivers: [
                                SliverToBoxAdapter(
                                    child: _buildSummaryCard()),
                                SliverPadding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: Sp.base),
                                  sliver: SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (ctx, i) => Padding(
                                        padding: const EdgeInsets.only(
                                            bottom: Sp.sm),
                                        child: _buildHoldingCard(
                                            _holdings[i], isDemo),
                                      ),
                                      childCount: _holdings.length,
                                    ),
                                  ),
                                ),
                                const SliverToBoxAdapter(
                                    child: SizedBox(height: Sp.xxl)),
                              ],
                            ),
                          ),
                        ),
                        // Sticky "Exit All" bar
                        if (_holdings.isNotEmpty && !isDemo)
                          _buildExitAllBar(),
                      ],
                    ),
    );
  }

  // ── Summary Card ───────────────────────────────────────────────────────────

  Widget _buildSummaryCard() {
    if (_summary == null) return SizedBox.shrink();
    final s = _summary!;
    final isProfit = s.totalPnl >= 0;
    final pnlColor =
        isProfit ? context.vt.accentGreen : context.vt.danger;

    final gttHoldings = _holdings
        .where((h) => h.hasGtt && h.maxProfit != null && h.maxLoss != null)
        .toList();
    final totalExpectedProfit =
        gttHoldings.fold(0.0, (sum, h) => sum + h.maxProfit!);
    final totalExpectedLoss =
        gttHoldings.fold(0.0, (sum, h) => sum + h.maxLoss!);
    final gttCount = gttHoldings.length;

    return Container(
      margin: const EdgeInsets.all(Sp.base),
      padding: EdgeInsets.all(Sp.base),
      decoration: BoxDecoration(
        color: context.vt.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(
            color: pnlColor.withValues(alpha: 0.2)),
        boxShadow: isProfit ? AppColors.greenGlow : AppColors.dangerGlow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Portfolio Holdings', style: AppTextStyles.caption),
          const SizedBox(height: Sp.xs),
          Text(
            _currency.format(s.totalCurrentValue),
            style: AppTextStyles.display.copyWith(fontSize: 32),
          ),
          SizedBox(height: Sp.md),
          Row(
            children: [
              _summaryPill('Invested', _currency.format(s.totalInvested),
                  context.vt.textSecondary),
              const SizedBox(width: Sp.sm),
              _summaryPill(
                isProfit ? 'Total Gain' : 'Total Loss',
                '${isProfit ? '+' : ''}${_currency.format(s.totalPnl)} '
                    '(${s.overallPnlPct.toStringAsFixed(1)}%)',
                pnlColor,
              ),
            ],
          ),
          if (gttCount > 0) ...[
            SizedBox(height: Sp.md),
            Container(
              padding: EdgeInsets.all(Sp.md),
              decoration: BoxDecoration(
                color: context.vt.surface2,
                borderRadius: BorderRadius.circular(Rad.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 12, color: context.vt.accentGreen),
                      SizedBox(width: Sp.xs),
                      Text(
                        'GTT Protection · $gttCount of ${_holdings.length} holdings',
                        style: AppTextStyles.caption
                            .copyWith(color: context.vt.accentGreen),
                      ),
                    ],
                  ),
                  SizedBox(height: Sp.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _gttSummaryTile(
                          label: 'Expected Profit',
                          value: '+${_currency.format(totalExpectedProfit)}',
                          color: context.vt.accentGreen,
                        ),
                      ),
                      SizedBox(width: Sp.sm),
                      Expanded(
                        child: _gttSummaryTile(
                          label: 'Expected Loss',
                          value: _currency.format(totalExpectedLoss),
                          color: context.vt.danger,
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

  Widget _summaryPill(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Sp.md, vertical: Sp.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(Rad.md),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption.copyWith(fontSize: 10)),
            const SizedBox(height: 2),
            Text(value,
                style: AppTextStyles.monoSm.copyWith(
                    color: color, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _gttSummaryTile(
      {required String label, required String value, required Color color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTextStyles.caption
                .copyWith(color: color, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value,
            style: AppTextStyles.monoSm
                .copyWith(color: color, fontWeight: FontWeight.w700)),
      ],
    );
  }

  // ── Holding Card ───────────────────────────────────────────────────────────

  Widget _buildHoldingCard(Holding h, bool isDemo) {
    final isProfit = h.pnl >= 0;
    final isDayUp = h.dayChange >= 0;
    final accentColor =
        isProfit ? context.vt.accentGreen : context.vt.danger;
    final dayColor = isDayUp ? context.vt.accentGreen : context.vt.danger;
    final isExiting = _exitingSymbol == h.symbol;

    return ClipRRect(
      borderRadius: BorderRadius.circular(Rad.lg),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accentColor),
            Expanded(
              child: Container(
                color: context.vt.surface1,
                child: Padding(
                  padding: EdgeInsets.all(Sp.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header ────────────────────────────────────────
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(h.symbol, style: AppTextStyles.h3),
                                Text(
                                  '${h.exchange} · ${h.quantity} qty',
                                  style: AppTextStyles.caption,
                                ),
                                if (h.daysLeft != null) ...[
                                  const SizedBox(height: Sp.xs),
                                  _daysLeftBadge(h.daysLeft!),
                                ],
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _currency.format(h.lastPrice),
                                style: AppTextStyles.mono.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isDayUp
                                        ? Icons.arrow_upward_rounded
                                        : Icons.arrow_downward_rounded,
                                    size: 10,
                                    color: dayColor,
                                  ),
                                  Text(
                                    '${h.dayChangePct.abs().toStringAsFixed(2)}%',
                                    style: AppTextStyles.caption.copyWith(
                                        color: dayColor, fontSize: 11),
                                  ),
                                ],
                              ),
                              if (!isDemo) ...[
                                SizedBox(height: Sp.xs),
                                isExiting
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: context.vt.danger,
                                        ),
                                      )
                                    : GestureDetector(
                                        onTap: () => _exitHolding(h),
                                        child: Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: Sp.sm,
                                                  vertical: 3),
                                          decoration: BoxDecoration(
                                            color: context.vt.danger
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(
                                                    Rad.sm),
                                            border: Border.all(
                                              color: context.vt.danger
                                                  .withValues(alpha: 0.4),
                                            ),
                                          ),
                                          child: Text(
                                            'Exit',
                                            style: AppTextStyles.label
                                                .copyWith(
                                                    color: context.vt.danger,
                                                    fontSize: 11),
                                          ),
                                        ),
                                      ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: Sp.md),
                      Divider(height: 1, color: context.vt.divider),
                      const SizedBox(height: Sp.md),

                      // ── Metrics row ────────────────────────────────────
                      Row(
                        children: [
                          _metric('Avg Buy',
                              _currency.format(h.averagePrice)),
                          _metric(
                              'Invested', _currency.format(h.investedValue)),
                          _metric(
                              'Current', _currency.format(h.currentValue)),
                        ],
                      ),
                      SizedBox(height: Sp.sm),

                      // ── P&L bar ────────────────────────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Sp.md, vertical: Sp.sm),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(Rad.md),
                          border: Border.all(
                              color: accentColor.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isProfit ? 'Total Gain' : 'Total Loss',
                              style: AppTextStyles.caption
                                  .copyWith(color: accentColor),
                            ),
                            Text(
                              '${isProfit ? '+' : ''}${_currency.format(h.pnl)} '
                              '(${h.pnlPct.toStringAsFixed(1)}%)',
                              style: AppTextStyles.mono.copyWith(
                                  color: accentColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      ),

                      // ── GTT expected P&L ────────────────────────────────
                      SizedBox(height: Sp.sm),
                      if (h.hasGtt &&
                          h.maxProfit != null &&
                          h.maxLoss != null)
                        _buildExpectedPnl(h)
                      else
                        _buildNoGttHint(),

                      // ── T+1 badge ──────────────────────────────────────
                      if (h.t1Quantity > 0) ...[
                        SizedBox(height: Sp.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: Sp.sm, vertical: Sp.xs),
                          decoration: BoxDecoration(
                            color: context.vt.warning.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(Rad.sm),
                            border: Border.all(
                                color:
                                    context.vt.warning.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            'T+1: ${h.t1Quantity} shares pending settlement',
                            style: AppTextStyles.caption.copyWith(
                                color: context.vt.warning),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _daysLeftBadge(int daysLeft) {
    Color color;
    String label;
    if (daysLeft < 0) {
      color = context.vt.textTertiary;
      label = 'Expired';
    } else if (daysLeft <= 2) {
      color = context.vt.danger;
      label = daysLeft == 0
          ? 'Expires today!'
          : '$daysLeft day${daysLeft == 1 ? '' : 's'} left';
    } else if (daysLeft <= 5) {
      color = context.vt.warning;
      label = '$daysLeft days left';
    } else {
      color = context.vt.accentGreen;
      label = '$daysLeft days left';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Rad.pill),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 10, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: AppTextStyles.caption.copyWith(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildExpectedPnl(Holding h) {
    return Row(
      children: [
        Expanded(
          child: _pnlTile(
            label: 'Expected Profit',
            amount: h.maxProfit!,
            price: h.target!,
            color: context.vt.accentGreen,
            icon: Icons.trending_up_rounded,
          ),
        ),
        SizedBox(width: Sp.sm),
        Expanded(
          child: _pnlTile(
            label: 'Expected Loss',
            amount: h.maxLoss!,
            price: h.stopLoss!,
            color: context.vt.danger,
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
      padding: const EdgeInsets.symmetric(
          horizontal: Sp.sm, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(Rad.md),
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
                  style: AppTextStyles.caption
                      .copyWith(color: color, fontSize: 10)),
            ],
          ),
          SizedBox(height: 3),
          Text(
            '$sign${_currency.format(amount)}',
            style: AppTextStyles.monoSm
                .copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          Text(
            '@ ${_currency.format(price)}',
            style: AppTextStyles.caption
                .copyWith(color: context.vt.textTertiary, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildNoGttHint() {
    return Row(
      children: [
        Icon(Icons.info_outline_rounded,
            size: 12, color: context.vt.textTertiary),
        SizedBox(width: Sp.xs),
        Text(
          'No active GTT — Expected P&L unavailable',
          style: AppTextStyles.caption
              .copyWith(color: context.vt.textTertiary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTextStyles.caption.copyWith(fontSize: 10)),
          Text(value,
              style: AppTextStyles.monoSm
                  .copyWith(fontWeight: FontWeight.w600, fontSize: 11)),
        ],
      ),
    );
  }

  // ── Exit All bar ────────────────────────────────────────────────────────────

  Widget _buildExitAllBar() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(
          Sp.base, Sp.sm, Sp.base, Sp.sm + bottomPadding),
      decoration: BoxDecoration(
        color: context.vt.surface1,
        border: Border(top: BorderSide(color: context.vt.divider)),
      ),
      child: _exitingSymbol == '__ALL__'
          ? Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: context.vt.danger),
              ),
            )
          : VtButton(
              label: 'Exit All Holdings',
              onPressed: _exitAll,
              variant: VtButtonVariant.danger,
              icon: Icon(Icons.exit_to_app_rounded,
                  size: 16, color: context.vt.textPrimary),
            ),
    );
  }

  // ── Demo Data ──────────────────────────────────────────────────────────────

  List<Holding> _demoHoldings() => [
        Holding(
          symbol: 'RELIANCE',
          exchange: 'NSE',
          isin: 'INE002A01018',
          quantity: 10,
          t1Quantity: 0,
          averagePrice: 2750.0,
          lastPrice: 2875.50,
          closePrice: 2860.0,
          pnl: 1255.0,
          pnlPct: 4.56,
          dayChange: 15.5,
          dayChangePct: 0.54,
          investedValue: 27500.0,
          currentValue: 28755.0,
          product: 'CNC',
          stopLoss: 2600.0,
          target: 3050.0,
          maxProfit: 3000.0,
          maxLoss: -1500.0,
          hasGtt: true,
          gttId: 'demo-1',
          daysLeft: 8,
        ),
        Holding(
          symbol: 'TCS',
          exchange: 'NSE',
          isin: 'INE467B01029',
          quantity: 5,
          t1Quantity: 0,
          averagePrice: 4100.0,
          lastPrice: 4389.75,
          closePrice: 4350.0,
          pnl: 1448.75,
          pnlPct: 7.07,
          dayChange: 39.75,
          dayChangePct: 0.91,
          investedValue: 20500.0,
          currentValue: 21948.75,
          product: 'CNC',
          stopLoss: 3900.0,
          target: 4600.0,
          maxProfit: 2500.0,
          maxLoss: -1000.0,
          hasGtt: true,
          gttId: 'demo-2',
          daysLeft: 3,
        ),
        Holding(
          symbol: 'INFY',
          exchange: 'NSE',
          isin: 'INE009A01021',
          quantity: 15,
          t1Quantity: 5,
          averagePrice: 1820.0,
          lastPrice: 1890.75,
          closePrice: 1875.0,
          pnl: 1061.25,
          pnlPct: 3.88,
          dayChange: 15.75,
          dayChangePct: 0.84,
          investedValue: 27300.0,
          currentValue: 28361.25,
          product: 'CNC',
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
        padding: EdgeInsets.all(Sp.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_outlined,
                size: 56, color: context.vt.textTertiary),
            const SizedBox(height: Sp.base),
            Text('No Holdings',
                style: AppTextStyles.h2, textAlign: TextAlign.center),
            const SizedBox(height: Sp.sm),
            Text(
              'No CNC delivery holdings found in your Zerodha account.\n\n'
              '• Holdings appear here after T+2 settlement\n'
              '• Intraday MIS positions are not shown here\n'
              '• Stocks bought today may appear tomorrow',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySecondary.copyWith(height: 1.6),
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
        padding: EdgeInsets.all(Sp.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 44, color: context.vt.danger),
            SizedBox(height: Sp.md),
            Text(_error ?? 'Error',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySecondary
                    .copyWith(color: context.vt.danger)),
            const SizedBox(height: Sp.base),
            VtButton(
              label: 'Retry',
              onPressed: _fetchHoldings,
              variant: VtButtonVariant.secondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpgradeCard() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(Sp.xxl),
        child: Container(
          padding: EdgeInsets.all(Sp.xl),
          decoration: BoxDecoration(
            color: context.vt.surface1,
            borderRadius: BorderRadius.circular(Rad.lg),
            border: Border.all(
                color: context.vt.accentGold.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium_rounded,
                  size: 48, color: context.vt.accentGold),
              const SizedBox(height: Sp.base),
              Text('Kite Connect Paid Plan Required',
                  style: AppTextStyles.h2, textAlign: TextAlign.center),
              const SizedBox(height: Sp.sm),
              Text(
                'Portfolio holdings require the Zerodha Kite Connect paid API subscription (₹2000/month). '
                'Enable it from your Kite developer console.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySecondary,
              ),
              SizedBox(height: Sp.xl),
              VtButton(
                label: 'Retry',
                onPressed: _fetchHoldings,
                variant: VtButtonVariant.secondary,
                icon: Icon(Icons.refresh_rounded,
                    size: 16, color: context.vt.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
