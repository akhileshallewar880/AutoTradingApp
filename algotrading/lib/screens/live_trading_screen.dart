import '../theme/vt_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/live_trading_provider.dart';
import '../models/live_trading_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

class LiveTradingScreen extends StatefulWidget {
  const LiveTradingScreen({super.key});

  @override
  State<LiveTradingScreen> createState() => _LiveTradingScreenState();
}

class _LiveTradingScreenState extends State<LiveTradingScreen>
    with SingleTickerProviderStateMixin {
  final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
  final _capitalController = TextEditingController();

  bool _isInitializing = false;
  String _overlayMessage = 'Processing...';
  late AnimationController _pulseController;

  // Config state
  String _orderType = 'LIMIT';
  int _maxPositions = 3;
  double _riskPercent = 1.5;
  double _maxDailyLossPct = 3.0;
  int _leverage = 1;
  double _deployPct = 100.0;

  // Candidate selection state
  bool _showCandidateSelection = false;
  final Map<String, bool> _checkedCandidates = {};
  final Map<String, TextEditingController> _qtyControllers = {};

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStatus());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _capitalController.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _loadStatus() {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;
    final provider = context.read<LiveTradingProvider>();
    final s = provider.status.isRunning
        ? provider.status.settings
        : provider.lastSettings;
    _applyFromSettings(s);
    provider.fetchStatus(auth.user!.userId);
    _fetchBalance();
  }

  void _fetchBalance() {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;
    context.read<LiveTradingProvider>().fetchBalance(
          apiKey: auth.user!.apiKey,
          accessToken: auth.user!.accessToken,
        );
  }

  void _applyFromSettings(AgentSettingsModel s) {
    setState(() {
      _maxPositions = s.maxPositions;
      _riskPercent = s.riskPercent;
      _maxDailyLossPct = s.maxDailyLossPct;
      _leverage = s.leverage;
      if (s.capitalToUse > 0) {
        _capitalController.text = s.capitalToUse.toStringAsFixed(0);
      }
    });
  }

  double _computeCapital(LiveTradingProvider live) {
    if (live.availableBalance > 0) {
      return (live.availableBalance * _deployPct / 100).roundToDouble();
    }
    return double.tryParse(
            _capitalController.text.replaceAll(',', '').trim()) ??
        0.0;
  }

  // ── Step 1: Analyze market ─────────────────────────────────────────────────

  Future<void> _runAnalysis() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    final live = context.read<LiveTradingProvider>();
    final capital = _computeCapital(live);
    if (capital <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please enter a valid capital amount first.'),
        backgroundColor: context.vt.danger,
      ));
      return;
    }

    live.clearAnalysis();

    setState(() {
      _isInitializing = true;
      _overlayMessage = 'Analyzing market...';
      _showCandidateSelection = false;
    });
    _pulseController.repeat();

    try {
      await live.analyzeMarket(
        userId: auth.user!.userId,
        accessToken: auth.user!.accessToken,
        apiKey: auth.user!.apiKey,
        limit: _maxPositions + 3,
      );
      if (!mounted) return;
      if (live.analyzeError != null) throw Exception(live.analyzeError);

      final qualifying = live.analysisResults
          .where((c) => c['signal'] == 'BUY' || c['signal'] == 'SELL')
          .toList();

      if (qualifying.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No qualifying signals found. Try again in a few minutes.'),
          backgroundColor: context.vt.warning,
          duration: const Duration(seconds: 5),
        ));
        return;
      }

      for (final c in qualifying) {
        final sym = c['symbol'] as String? ?? '';
        _checkedCandidates[sym] = true;
        _qtyControllers[sym]?.dispose();
        _qtyControllers[sym] =
            TextEditingController(text: '${_estimateQty(c, capital)}');
      }
      setState(() => _showCandidateSelection = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: context.vt.danger,
          duration: const Duration(seconds: 5),
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _overlayMessage = 'Processing...';
        });
        _pulseController.stop();
      }
    }
  }

  // ── Step 2: Execute selected candidates ───────────────────────────────────

  Future<void> _executeSelected() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    final live = context.read<LiveTradingProvider>();
    final capital = _computeCapital(live);

    final selected = live.analysisResults
        .where((c) =>
            _checkedCandidates[c['symbol'] as String? ?? ''] == true)
        .toList();

    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Select at least one trade to execute.'),
        backgroundColor: context.vt.warning,
      ));
      return;
    }

    final settings = AgentSettingsModel(
      maxPositions: _maxPositions,
      riskPercent: _riskPercent,
      scanIntervalMinutes: 5,
      maxTradesPerDay: _maxPositions * 2,
      maxDailyLossPct: _maxDailyLossPct,
      capitalToUse: capital,
      leverage: _leverage,
    );

    setState(() {
      _isInitializing = true;
      _overlayMessage = 'Starting monitor...';
    });
    _pulseController.repeat();

    try {
      await live.startAgent(
        userId: auth.user!.userId,
        accessToken: auth.user!.accessToken,
        apiKey: auth.user!.apiKey,
        settings: settings,
      );
      if (!mounted) return;
      if (live.error != null) throw Exception(live.error);

      live.placedOrderSymbols.clear();
      int placed = 0;
      int failed = 0;
      for (int i = 0; i < selected.length; i++) {
        if (!mounted) break;
        final c = selected[i];
        final symbol = c['symbol'] as String? ?? '';
        final qtyStr = _qtyControllers[symbol]?.text ?? '';
        final overrideQty = int.tryParse(qtyStr) ?? 0;

        setState(() =>
            _overlayMessage = 'Placing order ${i + 1}/${selected.length} — $symbol...');

        final ltp = (c['ltp'] as num?)?.toDouble() ?? 0;
        final qty = await live.placeLimitOrder(
          userId: auth.user!.userId,
          accessToken: auth.user!.accessToken,
          apiKey: auth.user!.apiKey,
          symbol: symbol,
          action: c['signal'] == 'SELL' ? 'SELL' : 'BUY',
          limitPrice: (c['entry_price'] as num?)?.toDouble() ?? ltp,
          stopLoss: (c['stop_loss'] as num?)?.toDouble() ?? 0,
          target: (c['target'] as num?)?.toDouble() ?? 0,
          atr: (c['atr'] as num?)?.toDouble() ?? 0,
          capitalToUse: overrideQty > 0 ? 0.0 : capital,
          riskPercent: _riskPercent,
          leverage: _leverage,
          orderType: _orderType,
        );
        if (qty > 0) {
          placed++;
        } else {
          failed++;
        }
      }

      if (!mounted) return;
      setState(() => _showCandidateSelection = false);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(placed > 0
            ? '✓ $placed $_orderType order${placed == 1 ? '' : 's'} placed. Agent is monitoring...'
                '${failed > 0 ? ' ($failed failed)' : ''}'
            : 'All orders failed. Check Zerodha. Agent is still running.'),
        backgroundColor: placed > 0 ? context.vt.accentGreen : context.vt.danger,
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: context.vt.danger,
          duration: const Duration(seconds: 5),
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _overlayMessage = 'Processing...';
        });
        _pulseController.stop();
      }
    }
  }

  int _estimateQty(Map<String, dynamic> c, double capital) {
    if (capital <= 0) return 1;
    final entry = (c['entry_price'] as num?)?.toDouble() ?? 0;
    final sl = (c['stop_loss'] as num?)?.toDouble() ?? 0;
    final risk = (entry - sl).abs();
    if (risk <= 0) return 1;
    final maxRisk = capital * _leverage * (_riskPercent / 100);
    final qty = (maxRisk / risk).floor();
    return qty < 1 ? 1 : qty;
  }

  // ── Candidate selection (Step 2) ───────────────────────────────────────────

  Widget _buildCandidateSelectionSection(LiveTradingProvider live) {
    final candidates = live.analysisResults
        .where((c) => c['signal'] == 'BUY' || c['signal'] == 'SELL')
        .toList();

    final checkedCount = _checkedCandidates.values.where((v) => v).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.checklist_rounded, size: 16, color: context.vt.accentPurple),
          SizedBox(width: 6),
          Text(
            'Select Trades ($checkedCount/${candidates.length})',
            style: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.bold, color: context.vt.accentPurple),
          ),
          Spacer(),
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Icon(Icons.arrow_back, size: 14, color: context.vt.textSecondary),
            label: Text('Back', style: AppTextStyles.caption),
            onPressed: () => setState(() {
              _showCandidateSelection = false;
              live.clearAnalysis();
            }),
          ),
        ]),
        SizedBox(height: Sp.sm),

        ...candidates.map((c) => _buildLiveCandidateCard(c)),
        SizedBox(height: Sp.md),

        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: checkedCount > 0
                  ? context.vt.accentPurple
                  : context.vt.surface2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Rad.lg)),
            ),
            icon: Icon(Icons.rocket_launch_rounded,
                color: checkedCount > 0
                    ? context.vt.surface0
                    : context.vt.textTertiary),
            label: Text(
              checkedCount > 0
                  ? 'Execute $checkedCount Trade${checkedCount == 1 ? '' : 's'} & Monitor'
                  : 'Select at least one trade',
              style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.bold,
                  color: checkedCount > 0
                      ? context.vt.surface0
                      : context.vt.textTertiary),
            ),
            onPressed: checkedCount > 0 && !live.isLoading ? _executeSelected : null,
          ),
        ),
      ],
    );
  }

  Widget _buildLiveCandidateCard(Map<String, dynamic> c) {
    final symbol = c['symbol'] as String? ?? '';
    final signal = c['signal'] as String? ?? 'NEUTRAL';
    final isBuy = signal == 'BUY';
    final ltp = (c['ltp'] as num?)?.toDouble() ?? 0;
    final entry = (c['entry_price'] as num?)?.toDouble() ?? ltp;
    final sl = (c['stop_loss'] as num?)?.toDouble() ?? 0;
    final t1 = (c['t1'] as num?)?.toDouble() ?? 0;
    final target = (c['target'] as num?)?.toDouble() ?? 0;
    final rrRatio = (c['rr_ratio'] as num?)?.toDouble() ?? 0;
    final strength = (c['strength'] as num?)?.toDouble() ?? 0;
    final rsi = c['rsi'];
    final macd = c['macd_histogram'];
    final reasons = (c['reasons'] as List?)?.cast<String>() ?? [];
    final isChecked = _checkedCandidates[symbol] ?? false;
    final qtyCtrl = _qtyControllers[symbol];
    final accentColor = isBuy ? context.vt.accentGreen : context.vt.danger;

    return Container(
      margin: EdgeInsets.only(bottom: Sp.sm),
      decoration: BoxDecoration(
        color: context.vt.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(
          color: isChecked
              ? accentColor.withValues(alpha: 0.5)
              : context.vt.divider,
          width: isChecked ? 1.5 : 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Checkbox(
            value: isChecked,
            activeColor: accentColor,
            checkColor: context.vt.surface0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4)),
            side: BorderSide(color: context.vt.textTertiary),
            onChanged: (v) =>
                setState(() => _checkedCandidates[symbol] = v ?? false),
          ),
          title: Row(children: [
            Text(symbol, style: AppTextStyles.h3),
            const SizedBox(width: Sp.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Rad.sm),
              ),
              child: Text(signal,
                  style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.bold, color: accentColor)),
            ),
            const Spacer(),
            Text('₹${ltp.toStringAsFixed(2)}',
                style: AppTextStyles.mono.copyWith(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Text('R:R ${rrRatio.toStringAsFixed(1)}',
                  style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w500)),
              SizedBox(width: Sp.sm),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (strength / 100).clamp(0.0, 1.0),
                    backgroundColor: context.vt.surface2,
                    color: accentColor,
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text('${strength.toInt()}%', style: AppTextStyles.caption),
            ]),
          ),
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(Sp.base, 0, Sp.base, Sp.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _candidatePrice('Entry', entry, context.vt.textPrimary),
                      _candidatePrice('SL', sl, context.vt.danger),
                      _candidatePrice('T1', t1, context.vt.accentGreen),
                      _candidatePrice('Target', target, context.vt.accentGreen),
                    ],
                  ),
                  SizedBox(height: Sp.md),

                  Wrap(spacing: 6, runSpacing: 6, children: [
                    if (rsi != null)
                      _indicatorChip(
                          'RSI ${(rsi as num).toStringAsFixed(1)}',
                          context.vt.accentPurple),
                    if (macd != null)
                      _indicatorChip(
                          'MACD ${macd >= 0 ? '+' : ''}${(macd as num).toStringAsFixed(2)}',
                          macd >= 0 ? context.vt.accentGreen : context.vt.danger),
                  ]),

                  if (reasons.isNotEmpty) ...[
                    SizedBox(height: Sp.sm),
                    ...reasons.map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 12, color: accentColor),
                              const SizedBox(width: 5),
                              Expanded(
                                  child: Text(r,
                                      style: AppTextStyles.caption)),
                            ],
                          ),
                        )),
                  ],

                  SizedBox(height: Sp.md),

                  Row(children: [
                    Text('Quantity:',
                        style: AppTextStyles.caption
                            .copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(width: Sp.sm),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        textAlign: TextAlign.center,
                        style: AppTextStyles.mono
                            .copyWith(fontSize: 13, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: context.vt.surface2,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                                color: context.vt.accentPurple,
                                width: 0.8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                                color: context.vt.accentPurple, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Sp.sm),
                    Text(
                      '× ₹${entry.toStringAsFixed(2)} = '
                      '₹${((int.tryParse(qtyCtrl?.text ?? '') ?? 0) * entry).toStringAsFixed(0)}',
                      style: AppTextStyles.caption,
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _candidatePrice(String label, double value, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: AppTextStyles.caption),
      Text('₹${value.toStringAsFixed(2)}',
          style: AppTextStyles.mono.copyWith(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    ]);
  }

  Widget _indicatorChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Rad.pill),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.w600, color: color)),
    );
  }

  // ── Stop agent ─────────────────────────────────────────────────────────────

  Future<void> _stopAgent() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    final provider = context.read<LiveTradingProvider>();
    final positions = provider.status.openPositions;
    final hasPositions = positions.isNotEmpty;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.vt.surface1,
        title: Text('Stop Agent', style: AppTextStyles.h2),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasPositions) ...[
              Text(
                '${positions.length} open position${positions.length > 1 ? 's' : ''} will be squared off at market price.',
                style: AppTextStyles.body,
              ),
              SizedBox(height: Sp.md),
              ...positions.map((p) {
                final isProfit = p.currentPnl >= 0;
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: p.action == 'BUY'
                            ? context.vt.accentGreenDim
                            : context.vt.dangerDim,
                        borderRadius: BorderRadius.circular(Rad.sm),
                      ),
                      child: Text(p.action,
                          style: AppTextStyles.caption.copyWith(
                              fontWeight: FontWeight.bold,
                              color: p.action == 'BUY'
                                  ? context.vt.accentGreen
                                  : context.vt.danger)),
                    ),
                    SizedBox(width: 6),
                    Expanded(child: Text(p.symbol, style: AppTextStyles.body)),
                    Text(
                      '${isProfit ? '+' : ''}${_currency.format(p.currentPnl)}',
                      style: AppTextStyles.mono.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isProfit ? context.vt.accentGreen : context.vt.danger),
                    ),
                  ]),
                );
              }),
              const SizedBox(height: Sp.md),
              Text('This action cannot be undone.',
                  style: AppTextStyles.caption),
            ] else
              Text('The agent will stop. No open positions to close.',
                  style: AppTextStyles.body),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: AppTextStyles.body.copyWith(color: context.vt.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: context.vt.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              hasPositions ? 'Stop & Square Off' : 'Stop',
              style: AppTextStyles.body.copyWith(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await context.read<LiveTradingProvider>().stopAgent(auth.user!.userId);
    if (mounted) {
      _applyFromSettings(context.read<LiveTradingProvider>().lastSettings);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final live = context.watch<LiveTradingProvider>();
    final status = live.status;
    final isRunning = status.isRunning;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text('Live Trading', style: AppTextStyles.h2),
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            foregroundColor: context.vt.textPrimary,
            elevation: 0,
            actions: [
              if (isRunning)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh status',
                  onPressed: _loadStatus,
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                Sp.base, Sp.base, Sp.base, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusCard(status, live.isLoading, isRunning),
                SizedBox(height: Sp.base),

                if (live.error != null)
                  _buildBanner(live.error!.replaceFirst('Exception: ', '')),

                if (isRunning) ...[
                  if (status.pendingOrders.isNotEmpty) ...[
                    _buildSectionHeader(
                        'Pending Orders (${status.pendingOrders.length})',
                        Icons.pending_actions,
                        context.vt.warning),
                    const SizedBox(height: Sp.sm),
                    ...status.pendingOrders.map(_buildPendingOrderCard),
                    SizedBox(height: Sp.base),
                  ],

                  if (status.openPositions.isNotEmpty) ...[
                    _buildSectionHeader(
                        'Monitored Positions (${status.openPositions.length})',
                        Icons.track_changes,
                        context.vt.accentGreen),
                    const SizedBox(height: Sp.sm),
                    ...status.openPositions.map(_buildPositionCard),
                    SizedBox(height: Sp.base),
                  ],

                  _buildSectionHeader('Active Settings', Icons.tune,
                      context.vt.accentPurple),
                  const SizedBox(height: Sp.sm),
                  _buildActiveSettingsBadges(status.settings),
                  const SizedBox(height: Sp.base),
                ],

                if (!isRunning) ...[
                  if (!_showCandidateSelection) ...[
                    _buildConfigCard(),
                    SizedBox(height: Sp.base),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.vt.accentGreen,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(Rad.lg)),
                        ),
                        icon: const Icon(Icons.search_rounded,
                            color: Colors.white),
                        label: Text(
                          'Analyze Market',
                          style: AppTextStyles.body.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                        onPressed: live.isLoading || live.isAnalyzing
                            ? null
                            : _runAnalysis,
                      ),
                    ),
                    const SizedBox(height: Sp.base),
                  ],

                  if (_showCandidateSelection) ...[
                    _buildCandidateSelectionSection(live),
                    SizedBox(height: Sp.base),
                  ],
                ],

                _buildSectionHeader(
                    'Activity Log', Icons.receipt_long, context.vt.textSecondary),
                const SizedBox(height: Sp.sm),
                _buildLogList(status.recentLogs),
              ],
            ),
          ),
        ),

        if (_isInitializing) _buildLoadingOverlay(_overlayMessage),
      ],
    );
  }

  // ── Config card ────────────────────────────────────────────────────────────

  Widget _buildConfigCard() {
    final live = context.watch<LiveTradingProvider>();
    final available = live.availableBalance;
    final deployAmount = available > 0
        ? (available * _deployPct / 100)
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: context.vt.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: context.vt.divider),
      ),
      padding: EdgeInsets.all(Sp.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Trading Configuration', style: AppTextStyles.h3),
          SizedBox(height: Sp.base),

          // ── Balance row ────────────────────────────────────────────
          Container(
            padding: EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              color: context.vt.accentPurple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(Rad.md),
              border: Border.all(
                  color: context.vt.accentPurple.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.account_balance_wallet_rounded,
                      size: 15, color: context.vt.accentPurple),
                  SizedBox(width: 6),
                  Text('Zerodha Balance',
                      style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.vt.accentPurple)),
                  Spacer(),
                  GestureDetector(
                    onTap: live.isFetchingBalance ? null : _fetchBalance,
                    child: live.isFetchingBalance
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: context.vt.accentPurple
                                    .withValues(alpha: 0.6)))
                        : Icon(Icons.refresh_rounded,
                            size: 16,
                            color: context.vt.accentPurple
                                .withValues(alpha: 0.7)),
                  ),
                ]),
                SizedBox(height: Sp.sm),
                if (live.balanceError != null)
                  Text(live.balanceError!,
                      style: AppTextStyles.caption
                          .copyWith(color: context.vt.danger))
                else if (available <= 0 && !live.isFetchingBalance)
                  Text('Tap refresh to fetch balance',
                      style: AppTextStyles.caption)
                else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _balanceStat('Available',
                          _currency.format(available), context.vt.accentGreen),
                      _balanceStat('Net',
                          _currency.format(live.netBalance),
                          context.vt.textSecondary),
                      _balanceStat(
                          'Used',
                          _currency.format(
                              (live.netBalance - available)
                                  .clamp(0, double.infinity)),
                          context.vt.warning),
                    ],
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: Sp.base),

          // ── Deploy % slider ────────────────────────────────────────
          Row(children: [
            SizedBox(
              width: 110,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Deploy',
                    style: AppTextStyles.caption
                        .copyWith(fontWeight: FontWeight.w600)),
                Text(
                  deployAmount > 0
                      ? _currency.format(deployAmount)
                      : '${_deployPct.toInt()}%',
                  style: AppTextStyles.mono.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: context.vt.accentPurple),
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: context.vt.accentPurple,
                  inactiveTrackColor: context.vt.surface2,
                  thumbColor: context.vt.accentPurple,
                  overlayColor: context.vt.accentPurple.withValues(alpha: 0.15),
                ),
                child: Slider(
                  value: _deployPct,
                  min: 10, max: 100, divisions: 9,
                  onChanged: (v) =>
                      setState(() => _deployPct = (v / 10).round() * 10.0),
                ),
              ),
            ),
            Text('${_deployPct.toInt()}%',
                style: AppTextStyles.mono.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: context.vt.accentPurple)),
          ]),

          // Quick-select buttons: 25 / 50 / 75 / 100
          Row(children: [
            SizedBox(width: 110),
            SizedBox(width: 8),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [25, 50, 75, 100].map((pct) {
                  final selected = _deployPct == pct.toDouble();
                  return GestureDetector(
                    onTap: () =>
                        setState(() => _deployPct = pct.toDouble()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Sp.sm, vertical: Sp.xs),
                      decoration: BoxDecoration(
                        color: selected
                            ? context.vt.accentPurple
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(Rad.sm),
                        border: Border.all(
                            color: selected
                                ? context.vt.accentPurple
                                : context.vt.divider),
                      ),
                      child: Text('$pct%',
                          style: AppTextStyles.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? context.vt.surface0
                                  : context.vt.textSecondary)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ]),
          SizedBox(height: Sp.sm),

          // ── Leverage selector ──────────────────────────────────────
          _buildSlider(
            label: 'Leverage',
            displayLabel: '${_leverage}x',
            value: _leverage.toDouble(),
            min: 1, max: 5, divisions: 4,
            onChanged: (v) => setState(() => _leverage = v.round()),
          ),

          if (available > 0 && _leverage > 1) ...[
            Padding(
              padding: EdgeInsets.only(left: 4, bottom: Sp.sm),
              child: Text(
                'Effective buying power: ${_currency.format(deployAmount * _leverage)} '
                '(${_leverage}x MIS leverage)',
                style: AppTextStyles.caption
                    .copyWith(color: context.vt.accentGreen),
              ),
            ),
          ],
          SizedBox(height: Sp.sm),

          // ── Order type toggle ──────────────────────────────────────
          Row(children: [
            Text('Order Type:',
                style: AppTextStyles.body
                    .copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: Sp.md),
            _typeChip('LIMIT'),
            const SizedBox(width: Sp.sm),
            _typeChip('MARKET'),
          ]),
          if (_orderType == 'MARKET') ...[
            SizedBox(height: Sp.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Sp.sm, vertical: 7),
              decoration: BoxDecoration(
                color: context.vt.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(Rad.sm),
                border: Border.all(
                    color: context.vt.warning.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Icon(Icons.info_outline,
                    size: 14, color: context.vt.warning),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Market orders execute immediately at the current market price.',
                    style: AppTextStyles.caption
                        .copyWith(color: context.vt.warning),
                  ),
                ),
              ]),
            ),
          ],
          const SizedBox(height: Sp.base),

          // ── Other sliders ──────────────────────────────────────────
          _buildSlider(
            label: 'Max Stocks',
            displayLabel: '$_maxPositions',
            value: _maxPositions.toDouble(),
            min: 1, max: 10, divisions: 9,
            onChanged: (v) => setState(() => _maxPositions = v.round()),
          ),
          _buildSlider(
            label: 'Risk / Trade',
            displayLabel: '${_riskPercent.toStringAsFixed(1)}%',
            value: _riskPercent,
            min: 0.5, max: 5.0, divisions: 9,
            onChanged: (v) =>
                setState(() => _riskPercent = (v * 10).round() / 10),
          ),
          _buildSlider(
            label: 'Daily Loss Cap',
            displayLabel: '${_maxDailyLossPct.toStringAsFixed(1)}%',
            value: _maxDailyLossPct,
            min: 1.0, max: 10.0, divisions: 9,
            onChanged: (v) =>
                setState(() => _maxDailyLossPct = (v * 10).round() / 10),
          ),
        ],
      ),
    );
  }

  Widget _balanceStat(String label, String value, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: AppTextStyles.caption),
      Text(value,
          style: AppTextStyles.mono.copyWith(
              fontSize: 12, fontWeight: FontWeight.bold, color: color)),
    ]);
  }

  Widget _typeChip(String type) {
    final selected = _orderType == type;
    return GestureDetector(
      onTap: () => setState(() => _orderType = type),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? context.vt.accentPurple : Colors.transparent,
          borderRadius: BorderRadius.circular(Rad.sm),
          border: Border.all(
              color: selected ? context.vt.accentPurple : context.vt.divider),
        ),
        child: Text(
          type,
          style: AppTextStyles.body.copyWith(
            color: selected ? context.vt.surface0 : context.vt.textSecondary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required String displayLabel,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Row(children: [
        SizedBox(
          width: 110,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: AppTextStyles.caption
                    .copyWith(fontWeight: FontWeight.w600)),
            Text(displayLabel,
                style: AppTextStyles.mono.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.vt.accentPurple)),
          ]),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: context.vt.accentPurple,
              inactiveTrackColor: context.vt.surface2,
              thumbColor: context.vt.accentPurple,
              overlayColor: context.vt.accentPurple.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
      ]),
    );
  }

  // ── Status card ────────────────────────────────────────────────────────────

  Widget _buildStatusCard(
      AgentStatusModel status, bool isLoading, bool isRunning) {
    final pnl = status.dailyPnl;
    final isProfit = pnl >= 0;
    final glowColor =
        isRunning ? context.vt.accentPurple : context.vt.textTertiary;

    return Container(
      decoration: BoxDecoration(
        color: context.vt.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: glowColor.withValues(alpha: 0.3)),
        boxShadow: isRunning
            ? [
                BoxShadow(
                    color: context.vt.accentPurple.withValues(alpha: 0.15),
                    blurRadius: 16,
                    spreadRadius: -2)
              ]
            : [],
      ),
      padding: EdgeInsets.all(Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: isRunning ? context.vt.accentGreen : context.vt.textTertiary,
                shape: BoxShape.circle,
                boxShadow: isRunning
                    ? [
                        BoxShadow(
                            color: context.vt.accentGreen.withValues(alpha: 0.5),
                            blurRadius: 6)
                      ]
                    : [],
              ),
            ),
            SizedBox(width: Sp.sm),
            Text(
              isRunning ? 'Agent Running' : 'Agent Stopped',
              style: AppTextStyles.h3,
            ),
            Spacer(),
            if (isRunning)
              GestureDetector(
                onTap: isLoading ? null : _stopAgent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Sp.md, vertical: 7),
                  decoration: BoxDecoration(
                    color: context.vt.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Rad.pill),
                    border: Border.all(
                        color: context.vt.danger.withValues(alpha: 0.4)),
                  ),
                  child: isLoading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: context.vt.danger))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.stop_rounded,
                              color: context.vt.danger, size: 16),
                          SizedBox(width: 4),
                          Text('Stop',
                              style: AppTextStyles.caption.copyWith(
                                  color: context.vt.danger,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ]),
                ),
              ),
          ]),
          SizedBox(height: Sp.md),
          Row(children: [
            _buildStatChip(
                'Positions',
                '${status.openPositions.length}/${status.settings.maxPositions}',
                Icons.layers),
            const SizedBox(width: Sp.sm),
            _buildStatChip(
                'Trades', '${status.tradeCountToday}', Icons.swap_horiz),
            SizedBox(width: Sp.sm),
            _buildStatChip(
              'Day P&L',
              '${isProfit ? '+' : ''}${_currency.format(pnl)}',
              isProfit ? Icons.trending_up : Icons.trending_down,
              valueColor: isProfit ? context.vt.accentGreen : context.vt.danger,
            ),
          ]),
          if (isRunning) ...[
            SizedBox(height: Sp.sm),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Sp.sm, vertical: 3),
                decoration: BoxDecoration(
                  color: context.vt.accentGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Rad.pill),
                  border: Border.all(
                      color: context.vt.accentGreen.withValues(alpha: 0.3)),
                ),
                child: Text('Monitoring Active',
                    style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.bold,
                        color: context.vt.accentGreen)),
              ),
              SizedBox(width: Sp.sm),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: status.tickerConnected
                      ? context.vt.accentGreen
                      : context.vt.warning,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 4),
              Text(
                status.tickerConnected ? 'Live feed' : 'Polling',
                style: AppTextStyles.caption.copyWith(
                    color: status.tickerConnected
                        ? context.vt.accentGreen
                        : context.vt.warning),
              ),
            ]),
          ],
          if (status.dailyLossLimitHit) ...[
            SizedBox(height: Sp.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Sp.sm, vertical: 6),
              decoration: BoxDecoration(
                color: context.vt.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Rad.sm),
                border: Border.all(
                    color: context.vt.danger.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.warning_amber_rounded,
                    color: context.vt.danger, size: 16),
                SizedBox(width: 6),
                Text('Daily loss limit hit — no new trades',
                    style: AppTextStyles.caption
                        .copyWith(color: context.vt.danger)),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value, IconData icon,
      {Color? valueColor}) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(Sp.sm),
        decoration: BoxDecoration(
          color: context.vt.surface2,
          borderRadius: BorderRadius.circular(Rad.sm),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 12, color: context.vt.textSecondary),
            const SizedBox(width: 4),
            Text(label, style: AppTextStyles.caption),
          ]),
          SizedBox(height: 4),
          Text(value,
              style: AppTextStyles.mono.copyWith(
                  color: valueColor ?? context.vt.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  // ── Active settings badges ─────────────────────────────────────────────────

  Widget _buildActiveSettingsBadges(AgentSettingsModel s) {
    final badges = [
      '${s.maxPositions} stocks',
      '${s.riskPercent}% risk/trade',
      '${s.maxDailyLossPct}% loss cap',
      if (s.leverage > 1) '${s.leverage}x leverage',
      if (s.capitalToUse > 0)
        '₹${(s.capitalToUse / 1000).toStringAsFixed(0)}k capital',
    ];
    return Wrap(
      spacing: Sp.sm,
      runSpacing: 6,
      children: badges
          .map((b) => Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Sp.sm, vertical: 5),
                decoration: BoxDecoration(
                  color: context.vt.accentPurpleDim,
                  borderRadius: BorderRadius.circular(Rad.pill),
                  border: Border.all(
                      color: context.vt.accentPurple.withValues(alpha: 0.25)),
                ),
                child: Text(b,
                    style: AppTextStyles.caption.copyWith(
                        color: context.vt.accentPurple,
                        fontWeight: FontWeight.w600)),
              ))
          .toList(),
    );
  }

  // ── Pending order card ─────────────────────────────────────────────────────

  Widget _buildPendingOrderCard(PendingOrderModel order) {
    return Container(
      margin: EdgeInsets.only(bottom: Sp.sm),
      padding: EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: context.vt.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: context.vt.warning.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
              color: context.vt.warning.withValues(alpha: 0.08),
              blurRadius: 6)
        ],
      ),
      child: Row(children: [
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: context.vt.warning),
        ),
        SizedBox(width: Sp.md),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              Text(order.symbol, style: AppTextStyles.h3),
              SizedBox(width: Sp.sm),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.vt.accentGreenDim,
                  borderRadius: BorderRadius.circular(Rad.sm),
                ),
                child: Text(order.action,
                    style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.bold,
                        color: context.vt.accentGreen)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              'Limit ₹${order.limitPrice.toStringAsFixed(2)} · '
              'SL ₹${order.stopLoss.toStringAsFixed(2)} · '
              'Tgt ₹${order.target.toStringAsFixed(2)} · '
              'qty ${order.quantity}',
              style: AppTextStyles.caption,
            ),
          ]),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: context.vt.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(Rad.sm),
            border:
                Border.all(color: context.vt.warning.withValues(alpha: 0.3)),
          ),
          child: Text('PENDING',
              style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  color: context.vt.warning,
                  fontSize: 9,
                  letterSpacing: 0.8)),
        ),
      ]),
    );
  }

  // ── Position card ──────────────────────────────────────────────────────────

  Widget _buildPositionCard(AgentPositionModel pos) {
    final isBuy = pos.action == 'BUY';
    final isProfit = pos.currentPnl >= 0;
    final accentColor = isBuy ? context.vt.accentGreen : context.vt.danger;

    return ClipRRect(
      borderRadius: BorderRadius.circular(Rad.lg),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accentColor),
            Expanded(
              child: Container(
                margin: EdgeInsets.only(bottom: Sp.sm),
                padding: EdgeInsets.all(Sp.md),
                color: context.vt.surface1,
                child: Column(children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(Rad.sm),
                      ),
                      child: Text(pos.action,
                          style: AppTextStyles.caption.copyWith(
                              fontWeight: FontWeight.bold,
                              color: accentColor)),
                    ),
                    SizedBox(width: Sp.sm),
                    Text(pos.symbol, style: AppTextStyles.h3),
                    if (pos.trailActivated) ...[
                      SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: context.vt.warning.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(Rad.sm),
                            border: Border.all(
                                color:
                                    context.vt.warning.withValues(alpha: 0.3))),
                        child: Text(
                          pos.trailCount > 0
                              ? 'TRAIL ×${pos.trailCount}'
                              : 'TRAIL',
                          style: AppTextStyles.caption.copyWith(
                              fontWeight: FontWeight.bold,
                              color: context.vt.warning),
                        ),
                      ),
                    ],
                    Spacer(),
                    Text(
                      '${isProfit ? '+' : ''}${_currency.format(pos.currentPnl)}',
                      style: AppTextStyles.mono.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isProfit
                              ? context.vt.accentGreen
                              : context.vt.danger),
                    ),
                  ]),
                  SizedBox(height: Sp.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildPriceLabel('Entry', pos.entryPrice),
                      _buildPriceLabel('SL', pos.stopLoss,
                          color: context.vt.danger),
                      _buildPriceLabel('Target', pos.target,
                          color: context.vt.accentGreen),
                      _buildPriceLabel('Qty', pos.quantity.toDouble(),
                          isQty: true),
                    ],
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceLabel(String label, double value,
      {Color? color, bool isQty = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: AppTextStyles.caption),
      Text(
        isQty ? value.toInt().toString() : _currency.format(value),
        style: AppTextStyles.mono.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color ?? context.vt.textPrimary),
      ),
    ]);
  }

  // ── Log list ───────────────────────────────────────────────────────────────

  Widget _buildLogList(List<AgentLogModel> logs) {
    if (logs.isEmpty) {
      return Container(
        padding: EdgeInsets.all(Sp.lg),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.vt.surface1,
          borderRadius: BorderRadius.circular(Rad.lg),
          border: Border.all(color: context.vt.divider),
        ),
        child: Text('No activity yet.', style: AppTextStyles.bodySecondary),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: context.vt.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: context.vt.divider),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        itemCount: logs.length > 30 ? 30 : logs.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: context.vt.divider),
        itemBuilder: (_, i) => _buildLogItem(logs[i]),
      ),
    );
  }

  Widget _buildLogItem(AgentLogModel log) {
    final color = _eventColor(log.event);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(log.timestamp,
            style: AppTextStyles.caption
                .copyWith(fontFamily: 'monospace', fontSize: 10)),
        const SizedBox(width: Sp.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Rad.sm)),
          child: Text(log.event,
              style: AppTextStyles.caption.copyWith(
                  fontSize: 9, fontWeight: FontWeight.bold, color: color)),
        ),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: Text(log.message,
              style: AppTextStyles.caption,
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }

  Color _eventColor(String event) {
    switch (event) {
      case 'TRADE_OPEN':
      case 'POSITION_REGISTERED':
        return context.vt.accentGreen;
      case 'TARGET_HIT':
        return context.vt.accentGreen;
      case 'SQUAREOFF':
      case 'TRADE_FAIL':
        return context.vt.danger;
      case 'WARN':
      case 'ERROR':
        return context.vt.warning;
      case 'TRAIL':
      case 'GTT_UPDATED':
        return context.vt.accentPurple;
      case 'STARTED':
        return context.vt.accentPurple;
      default:
        return context.vt.textSecondary;
    }
  }

  // ── Section header ─────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 6),
      Text(title,
          style: AppTextStyles.body
              .copyWith(fontWeight: FontWeight.bold, color: color)),
    ]);
  }

  Widget _buildBanner(String message) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: Sp.sm),
      padding: EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: context.vt.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: context.vt.danger.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(Icons.error_outline, color: context.vt.danger, size: 16),
        SizedBox(width: Sp.sm),
        Expanded(
            child: Text(message,
                style: AppTextStyles.caption
                    .copyWith(color: context.vt.danger))),
      ]),
    );
  }

  // ── Loading overlay ────────────────────────────────────────────────────────

  Widget _buildLoadingOverlay(String message) {
    return Container(
      color: context.vt.overlayScrim,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (ctx, _) => Stack(
                alignment: Alignment.center,
                children: [
                  Transform.scale(
                    scale: 1.0 + _pulseController.value * 0.5,
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.vt.accentPurple.withValues(
                            alpha: 0.3 * (1 - _pulseController.value)),
                      ),
                    ),
                  ),
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.vt.accentPurple,
                      boxShadow: [
                        BoxShadow(
                            color: context.vt.accentPurple
                                .withValues(alpha: 0.4),
                            blurRadius: 20),
                      ],
                    ),
                    child: Icon(Icons.rocket_launch_rounded,
                        color: context.vt.textPrimary, size: 34),
                  ),
                ],
              ),
            ),
            SizedBox(height: 36),
            Text(message,
                style: AppTextStyles.h2.copyWith(color: context.vt.textPrimary)),
            SizedBox(height: Sp.sm),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: context.vt.accentPurple),
            ),
          ],
        ),
      ),
    );
  }
}
