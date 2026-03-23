import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/live_trading_provider.dart';
import '../models/live_trading_model.dart';

class LiveTradingScreen extends StatefulWidget {
  const LiveTradingScreen({super.key});

  @override
  State<LiveTradingScreen> createState() => _LiveTradingScreenState();
}

class _LiveTradingScreenState extends State<LiveTradingScreen>
    with SingleTickerProviderStateMixin {
  final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  bool _isInitializing = false; // full-screen overlay during start
  late AnimationController _pulseController;

  // Settings (editable before starting)
  int _maxPositions = 5;
  double _riskPercent = 3.0;
  int _scanIntervalMinutes = 5;
  int _maxTradesPerDay = 10;
  double _maxDailyLossPct = 5.0;
  double _capitalToUse = 0.0;
  int _leverage = 1;

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
    super.dispose();
  }

  void _loadStatus() {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;
    final provider = context.read<LiveTradingProvider>();
    final settings = provider.status.isRunning
        ? provider.status.settings
        : provider.lastSettings;
    _applySlidersFromSettings(settings);
    provider.fetchStatus(auth.user!.userId);
  }

  void _applySlidersFromSettings(AgentSettingsModel s) {
    setState(() {
      _maxPositions = s.maxPositions;
      _riskPercent = s.riskPercent;
      _scanIntervalMinutes = s.scanIntervalMinutes;
      _maxTradesPerDay = s.maxTradesPerDay;
      _maxDailyLossPct = s.maxDailyLossPct;
      _capitalToUse = s.capitalToUse;
      _leverage = s.leverage;
    });
  }

  void _persistCurrentSliders() {
    context.read<LiveTradingProvider>().updateLastSettings(
      AgentSettingsModel(
        maxPositions: _maxPositions,
        riskPercent: _riskPercent,
        scanIntervalMinutes: _scanIntervalMinutes,
        maxTradesPerDay: _maxTradesPerDay,
        maxDailyLossPct: _maxDailyLossPct,
        capitalToUse: _capitalToUse,
        leverage: _leverage,
      ),
    );
  }

  // ── Analyze market ─────────────────────────────────────────────────────────

  Future<void> _analyzeMarket() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;
    await context.read<LiveTradingProvider>().analyzeMarket(
      userId: auth.user!.userId,
      accessToken: auth.user!.accessToken,
      apiKey: auth.user!.apiKey,
      limit: 5,
    );
  }

  // ── Start monitoring agent ─────────────────────────────────────────────────

  Future<void> _startMonitoringAgent() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start Position Monitor'),
        content: const Text(
          'The agent will monitor positions you register — watching stop-loss, '
          'targets, and trailing SL.\n\n'
          'The agent does NOT place trades automatically. '
          'You must execute trades manually on Zerodha, then register them here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start Monitor', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isInitializing = true;
      _pulseController.repeat();
    });
    _persistCurrentSliders();
    try {
      await context.read<LiveTradingProvider>().startAgent(
        userId: auth.user!.userId,
        accessToken: auth.user!.accessToken,
        apiKey: auth.user!.apiKey,
        settings: AgentSettingsModel(
          maxPositions: _maxPositions,
          riskPercent: _riskPercent,
          scanIntervalMinutes: _scanIntervalMinutes,
          maxTradesPerDay: _maxTradesPerDay,
          maxDailyLossPct: _maxDailyLossPct,
          capitalToUse: _capitalToUse,
          leverage: _leverage,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _pulseController.stop();
        });
      }
    }
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
        title: const Text('Stop Agent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasPositions) ...[
              Text(
                '${positions.length} open position${positions.length > 1 ? 's' : ''} will be squared off at market price.',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              ...positions.map((p) {
                final isProfit = p.currentPnl >= 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: p.action == 'BUY' ? Colors.green[50] : Colors.red[50],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          p.action,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: p.action == 'BUY' ? Colors.green[700] : Colors.red[700],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(p.symbol,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Text(
                        '${isProfit ? '+' : ''}${_currency.format(p.currentPnl)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isProfit ? Colors.green[700] : Colors.red[600],
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
              Text('This action cannot be undone.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ] else
              const Text('The agent will stop. No open positions to close.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              hasPositions ? 'Stop & Square Off' : 'Stop',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await context.read<LiveTradingProvider>().stopAgent(auth.user!.userId);
    if (mounted) {
      _applySlidersFromSettings(context.read<LiveTradingProvider>().lastSettings);
    }
  }

  // ── Register position dialog ───────────────────────────────────────────────

  Future<void> _showRegisterDialog({Map<String, dynamic>? prefill}) async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    final symbolCtrl = TextEditingController(text: prefill?['symbol'] ?? '');
    final entryCtrl = TextEditingController(
        text: prefill != null ? '${prefill['entry_price'] ?? ''}' : '');
    final slCtrl = TextEditingController(
        text: prefill != null ? '${prefill['stop_loss'] ?? ''}' : '');
    final targetCtrl = TextEditingController(
        text: prefill != null ? '${prefill['target'] ?? ''}' : '');
    final qtyCtrl = TextEditingController(text: '1');
    final gttCtrl = TextEditingController();
    String action = prefill?['signal'] == 'SELL' ? 'SELL' : 'BUY';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(
            prefill != null
                ? 'Register Position: ${prefill['symbol']}'
                : 'Register Position',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter the details of the trade you have already placed on Zerodha.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),

                // Action toggle
                Row(
                  children: [
                    const Text('Direction: ', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    _actionChip('BUY', action, Colors.green[700]!, () => setDlgState(() => action = 'BUY')),
                    const SizedBox(width: 8),
                    _actionChip('SELL', action, Colors.red[700]!, () => setDlgState(() => action = 'SELL')),
                  ],
                ),
                const SizedBox(height: 12),

                if (prefill == null) ...[
                  _dlgField('Symbol (e.g. RELIANCE)', symbolCtrl,
                      textCapitalization: TextCapitalization.characters),
                  const SizedBox(height: 8),
                ],
                _dlgField('Entry Price (₹)', entryCtrl, isNum: true),
                const SizedBox(height: 8),
                _dlgField('Stop Loss (₹)', slCtrl, isNum: true),
                const SizedBox(height: 8),
                _dlgField('Target (₹)', targetCtrl, isNum: true),
                const SizedBox(height: 8),
                _dlgField('Quantity (shares)', qtyCtrl, isInt: true),
                const SizedBox(height: 8),
                _dlgField('GTT Order ID (optional)', gttCtrl),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo[700]),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Register', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result != true || !mounted) return;

    final sym = prefill?['symbol'] ?? symbolCtrl.text.trim().toUpperCase();
    final entry = double.tryParse(entryCtrl.text) ?? 0;
    final sl = double.tryParse(slCtrl.text) ?? 0;
    final tgt = double.tryParse(targetCtrl.text) ?? 0;
    final qty = int.tryParse(qtyCtrl.text) ?? 0;
    final rawAtr = prefill?['atr'];
    final atr = rawAtr != null ? (rawAtr as num).toDouble() : 0.0;
    final gttId = gttCtrl.text.trim().isEmpty ? null : gttCtrl.text.trim();

    if (sym.isEmpty || entry <= 0 || sl <= 0 || tgt <= 0 || qty <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill all required fields with valid values.')),
        );
      }
      return;
    }

    final ok = await context.read<LiveTradingProvider>().registerPosition(
      userId: auth.user!.userId,
      accessToken: auth.user!.accessToken,
      apiKey: auth.user!.apiKey,
      symbol: sym,
      action: action,
      quantity: qty,
      entryPrice: entry,
      stopLoss: sl,
      target: tgt,
      gttId: gttId,
      atr: atr,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? '✓ $sym registered — agent is now monitoring this position'
            : context.read<LiveTradingProvider>().error ?? 'Failed to register position'),
        backgroundColor: ok ? Colors.green[700] : Colors.red[700],
      ));
    }
  }

  Widget _actionChip(String label, String current, Color color, VoidCallback onTap) {
    final selected = label == current;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : Colors.grey[400]!, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : Colors.grey[600],
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _dlgField(String label, TextEditingController ctrl,
      {bool isNum = false,
      bool isInt = false,
      TextCapitalization textCapitalization = TextCapitalization.none}) {
    return TextField(
      controller: ctrl,
      textCapitalization: textCapitalization,
      keyboardType:
          isNum || isInt ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      inputFormatters: isInt ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
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
          backgroundColor: Colors.grey[50],
          appBar: AppBar(
            title: const Text('Live Trading', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.indigo[700],
            foregroundColor: Colors.white,
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Status card ───────────────────────────────────────────
                _buildStatusCard(status, live.isLoading, isRunning),
                const SizedBox(height: 16),

                // ── Error banner ──────────────────────────────────────────
                if (live.error != null)
                  _buildBanner(live.error!.replaceFirst('Exception: ', ''), Colors.red),

                // ── Open positions monitored ──────────────────────────────
                if (status.openPositions.isNotEmpty) ...[
                  _buildSectionHeader('Monitored Positions', Icons.track_changes, Colors.green[700]!),
                  const SizedBox(height: 8),
                  ...status.openPositions.map(_buildPositionCard),
                  const SizedBox(height: 16),
                ],

                // ── Agent stopped: Step 1 — Analyze ──────────────────────
                if (!isRunning) ...[
                  _buildSectionHeader('Step 1 — Analyze Market', Icons.search, Colors.orange[700]!),
                  const SizedBox(height: 8),
                  _buildAnalyzeSection(live),
                  const SizedBox(height: 24),
                  _buildSectionHeader('Step 2 — Start Monitor + Register Positions', Icons.play_circle_outline, Colors.indigo[600]!),
                  const SizedBox(height: 8),
                  _buildSettingsCard(),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo[700],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.monitor_heart_outlined, color: Colors.white),
                      label: const Text(
                        'Start Position Monitor',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      onPressed: live.isLoading ? null : _startMonitoringAgent,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Agent running: add position button ────────────────────
                if (isRunning) ...[
                  _buildSectionHeader('Active Settings', Icons.tune, Colors.indigo[400]!),
                  const SizedBox(height: 8),
                  _buildActiveSettingsBadges(status.settings),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.indigo[700],
                        side: BorderSide(color: Colors.indigo[300]!),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Register Another Position',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () => _showRegisterDialog(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Activity log ──────────────────────────────────────────
                _buildSectionHeader('Activity Log', Icons.receipt_long, Colors.blueGrey),
                const SizedBox(height: 8),
                _buildLogList(status.recentLogs),
              ],
            ),
          ),
        ),

        // ── Full-screen loading overlay ───────────────────────────────────
        if (_isInitializing) _buildLoadingOverlay('Starting monitor...'),
      ],
    );
  }

  // ── Analyze section ────────────────────────────────────────────────────────

  Widget _buildAnalyzeSection(LiveTradingProvider live) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[700],
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: live.isAnalyzing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.analytics_outlined, color: Colors.white),
            label: Text(
              live.isAnalyzing ? 'Analyzing...' : 'Analyze Market',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            onPressed: live.isAnalyzing ? null : _analyzeMarket,
          ),
        ),
        if (live.analyzeError != null)
          _buildBanner(live.analyzeError!, Colors.red),
        if (live.analysisResults.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildBanner(
            '✓ ${live.analysisResults.length} candidates found. '
            'Review them below, place trades manually on Zerodha, then start the monitor.',
            Colors.green,
          ),
          const SizedBox(height: 8),
          ...live.analysisResults.map((c) => _buildCandidateCard(c)),
        ],
      ],
    );
  }

  Widget _buildCandidateCard(Map<String, dynamic> c) {
    final signal = c['signal'] as String? ?? 'NEUTRAL';
    final strength = c['strength'] as int? ?? 0;
    final isBuy = signal == 'BUY';
    final isSell = signal == 'SELL';
    final signalColor = isBuy
        ? Colors.green[700]!
        : isSell
            ? Colors.red[700]!
            : Colors.grey[600]!;
    final ltp = (c['ltp'] as num?)?.toDouble() ?? 0;
    final sl = (c['stop_loss'] as num?)?.toDouble() ?? 0;
    final tgt = (c['target'] as num?)?.toDouble() ?? 0;
    final t1 = (c['t1'] as num?)?.toDouble() ?? 0;
    final rr = (c['rr_ratio'] as num?)?.toDouble() ?? 0;
    final rsi = (c['rsi'] as num?)?.toDouble();
    final macdHist = (c['macd_histogram'] as num?)?.toDouble();
    final reasons = List<String>.from(c['reasons'] as List? ?? []);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: signalColor.withValues(alpha: 0.4), width: 1.2)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: signalColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(signal,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold, color: signalColor)),
                ),
                const SizedBox(width: 8),
                Text(c['symbol'] as String? ?? '',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                // Strength dots
                Row(
                  children: List.generate(3, (i) => Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < strength ? signalColor : Colors.grey[300],
                    ),
                  )),
                ),
                const Spacer(),
                Text(_currency.format(ltp),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 10),

            // Price levels
            Row(
              children: [
                _priceBox('Entry', ltp, Colors.grey[700]!),
                const SizedBox(width: 6),
                _priceBox('Stop Loss', sl, Colors.red[700]!),
                const SizedBox(width: 6),
                _priceBox('T1', t1, Colors.orange[700]!),
                const SizedBox(width: 6),
                _priceBox('Target', tgt, Colors.green[700]!),
              ],
            ),
            const SizedBox(height: 8),

            // Indicators row
            Row(
              children: [
                _indicatorChip('R:R ${rr.toStringAsFixed(1)}:1', Colors.indigo),
                if (rsi != null) ...[
                  const SizedBox(width: 6),
                  _indicatorChip('RSI ${rsi.toStringAsFixed(0)}',
                      rsi > 60 ? Colors.orange : rsi < 40 ? Colors.blue : Colors.grey),
                ],
                if (macdHist != null) ...[
                  const SizedBox(width: 6),
                  _indicatorChip(
                    'MACD ${macdHist > 0 ? '+' : ''}${macdHist.toStringAsFixed(3)}',
                    macdHist > 0 ? Colors.green : Colors.red,
                  ),
                ],
              ],
            ),

            // Signal reasons (collapsed)
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(reasons.take(2).join(' · '),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],

            const SizedBox(height: 10),
            // CTA
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: signalColor,
                  side: BorderSide(color: signalColor),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add_task, size: 16),
                label: const Text(
                  'Traded this? Register for Monitoring',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                onPressed: () {
                  // If agent is not yet running, start it first then register
                  final isRunning = context.read<LiveTradingProvider>().status.isRunning;
                  if (!isRunning) {
                    _startMonitoringThenRegister(c);
                  } else {
                    _showRegisterDialog(prefill: c);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startMonitoringThenRegister(Map<String, dynamic> candidate) async {
    // Start agent first, then open register dialog
    await _startMonitoringAgent();
    if (!mounted) return;
    final isRunning = context.read<LiveTradingProvider>().status.isRunning;
    if (isRunning) {
      await _showRegisterDialog(prefill: candidate);
    }
  }

  Widget _priceBox(String label, double price, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          Text(
            _currency.format(price),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _indicatorChip(String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color[200]!),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color[800])),
    );
  }

  // ── Status card ────────────────────────────────────────────────────────────

  Widget _buildStatusCard(AgentStatusModel status, bool isLoading, bool isRunning) {
    final pnl = status.dailyPnl;
    final isProfit = pnl >= 0;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: isRunning
                ? [Colors.indigo[700]!, Colors.indigo[500]!]
                : [Colors.grey[600]!, Colors.grey[500]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: isRunning ? Colors.greenAccent : Colors.white38,
                    shape: BoxShape.circle,
                    boxShadow: isRunning
                        ? [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.6), blurRadius: 6)]
                        : [],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isRunning ? 'Agent Monitoring' : 'Agent Stopped',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                if (isRunning)
                  GestureDetector(
                    onTap: isLoading ? null : _stopAgent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.red[400],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.stop_rounded, color: Colors.white, size: 16),
                                SizedBox(width: 4),
                                Text('Stop', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildStatChip('Positions', '${status.openPositions.length}/${status.settings.maxPositions}', Icons.layers),
                const SizedBox(width: 10),
                _buildStatChip('Trades', '${status.tradeCountToday}', Icons.swap_horiz),
                const SizedBox(width: 10),
                _buildStatChip(
                  'Day P&L',
                  '${isProfit ? '+' : ''}${_currency.format(pnl)}',
                  isProfit ? Icons.trending_up : Icons.trending_down,
                  valueColor: isProfit ? Colors.greenAccent[100] : Colors.red[200],
                ),
              ],
            ),
            if (isRunning) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.greenAccent, width: 0.8),
                    ),
                    child: Text(
                      'Monitoring Only Mode',
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.bold, color: Colors.greenAccent[100]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: status.tickerConnected ? Colors.greenAccent : Colors.orange[300],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    status.tickerConnected ? 'Live feed' : 'Polling',
                    style: TextStyle(
                      color: status.tickerConnected ? Colors.greenAccent[100] : Colors.orange[200],
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
            if (status.dailyLossLimitHit) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[300]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red[200], size: 16),
                    const SizedBox(width: 6),
                    Text('Daily loss limit hit — no new trades',
                        style: TextStyle(color: Colors.red[200], fontSize: 12)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value, IconData icon, {Color? valueColor}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: Colors.white60),
                const SizedBox(width: 4),
                Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                  color: valueColor ?? Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── Position card ──────────────────────────────────────────────────────────

  Widget _buildPositionCard(AgentPositionModel pos) {
    final isBuy = pos.action == 'BUY';
    final isProfit = pos.currentPnl >= 0;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isBuy ? Colors.green[50] : Colors.red[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    pos.action,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isBuy ? Colors.green[700] : Colors.red[700]),
                  ),
                ),
                const SizedBox(width: 8),
                Text(pos.symbol,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                if (pos.trailActivated) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.orange[50], borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      pos.trailCount > 0 ? 'TRAIL ×${pos.trailCount}' : 'TRAIL',
                      style: TextStyle(
                          fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange[700]),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  '${isProfit ? '+' : ''}${_currency.format(pos.currentPnl)}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isProfit ? Colors.green[700] : Colors.red[600]),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildPriceLabel('Entry', pos.entryPrice),
                _buildPriceLabel('SL', pos.stopLoss, color: Colors.red[600]),
                _buildPriceLabel('Target', pos.target, color: Colors.green[700]),
                _buildPriceLabel('Qty', pos.quantity.toDouble(), isQty: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceLabel(String label, double value,
      {Color? color, bool isQty = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        Text(
          isQty ? value.toInt().toString() : _currency.format(value),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color ?? Colors.grey[800]),
        ),
      ],
    );
  }

  // ── Settings card ──────────────────────────────────────────────────────────

  Widget _buildSettingsCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSlider2(label: 'Max Positions', value: _maxPositions.toDouble(), min: 1, max: 10, divisions: 9, onChanged: (v) => setState(() { _maxPositions = v.round(); _persistCurrentSliders(); }), displayLabel: _maxPositions.toString()),
            _buildSlider2(label: 'Risk / Trade', value: _riskPercent, min: 0.5, max: 5.0, divisions: 9, onChanged: (v) => setState(() { _riskPercent = (v * 10).round() / 10; _persistCurrentSliders(); }), displayLabel: '${_riskPercent.toStringAsFixed(1)}%'),
            _buildSlider2(label: 'Max Trades/Day', value: _maxTradesPerDay.toDouble(), min: 1, max: 20, divisions: 19, onChanged: (v) => setState(() { _maxTradesPerDay = v.round(); _persistCurrentSliders(); }), displayLabel: _maxTradesPerDay.toString()),
            _buildSlider2(label: 'Daily Loss Cap', value: _maxDailyLossPct, min: 1.0, max: 10.0, divisions: 9, onChanged: (v) => setState(() { _maxDailyLossPct = (v * 10).round() / 10; _persistCurrentSliders(); }), displayLabel: '${_maxDailyLossPct.toStringAsFixed(1)}%'),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider2({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String displayLabel,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Text(displayLabel,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo[700])),
            ],
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            activeColor: Colors.indigo[600],
          ),
        ),
      ],
    );
  }

  Widget _buildActiveSettingsBadges(AgentSettingsModel s) {
    final badges = [
      '${s.maxPositions} positions',
      '${s.riskPercent}% risk',
      '${s.maxTradesPerDay} trades/day',
      '${s.leverage}x leverage',
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: badges
          .map((b) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.indigo[50],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.indigo[200]!),
                ),
                child: Text(b,
                    style: TextStyle(
                        fontSize: 12, color: Colors.indigo[700], fontWeight: FontWeight.w600)),
              ))
          .toList(),
    );
  }

  // ── Log list ───────────────────────────────────────────────────────────────

  Widget _buildLogList(List<AgentLogModel> logs) {
    if (logs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Text('No activity yet.', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: logs.length > 30 ? 30 : logs.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[100]),
        itemBuilder: (_, i) => _buildLogItem(logs[i]),
      ),
    );
  }

  Widget _buildLogItem(AgentLogModel log) {
    final color = _eventColor(log.event);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(log.timestamp,
              style: TextStyle(fontSize: 10, color: Colors.grey[500], fontFamily: 'monospace')),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration:
                BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
            child: Text(log.event,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(log.message,
                style: const TextStyle(fontSize: 11), maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Color _eventColor(String event) {
    switch (event) {
      case 'TRADE_OPEN':
      case 'POSITION_REGISTERED':
        return Colors.green[700]!;
      case 'TARGET_HIT':
        return Colors.teal[700]!;
      case 'SQUAREOFF':
      case 'TRADE_FAIL':
        return Colors.red[700]!;
      case 'WARN':
      case 'ERROR':
        return Colors.orange[700]!;
      case 'TRAIL':
      case 'GTT_UPDATED':
        return Colors.blue[700]!;
      case 'STARTED':
        return Colors.indigo[700]!;
      default:
        return Colors.grey[600]!;
    }
  }

  // ── Section header ─────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(title,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildBanner(String message, MaterialColor color) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color[200]!),
      ),
      child: Row(
        children: [
          Icon(
            color == Colors.red ? Icons.error_outline : Icons.info_outline,
            color: color[700],
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(color: color[700], fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ── Loading overlay ────────────────────────────────────────────────────────

  Widget _buildLoadingOverlay(String message) {
    return Container(
      color: Colors.indigo[900]!.withValues(alpha: 0.95),
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
                        color: Colors.indigo[400]!
                            .withValues(alpha: 0.3 * (1 - _pulseController.value)),
                      ),
                    ),
                  ),
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.indigo[600],
                      boxShadow: [
                        BoxShadow(
                            color: Colors.indigoAccent.withValues(alpha: 0.4),
                            blurRadius: 20),
                      ],
                    ),
                    child: const Icon(Icons.monitor_heart_outlined,
                        color: Colors.white, size: 36),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),
            Text(message,
                style: const TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}
