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
  final _capitalController = TextEditingController();

  bool _isInitializing = false;
  String _overlayMessage = 'Processing...';
  late AnimationController _pulseController;

  // Config state
  String _orderType = 'LIMIT';   // 'LIMIT' or 'MARKET'
  int _maxPositions = 3;
  double _riskPercent = 1.5;
  double _maxDailyLossPct = 3.0;
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
    _capitalController.dispose();
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

  double get _parsedCapital =>
      double.tryParse(_capitalController.text.replaceAll(',', '').trim()) ?? 0.0;

  // ── Execute & Monitor ──────────────────────────────────────────────────────

  Future<void> _executeAndMonitor() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    final capital = _parsedCapital;
    if (capital <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter a valid capital amount first.'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    // Confirm before executing
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.rocket_launch_rounded, color: Colors.indigo[700], size: 22),
          const SizedBox(width: 10),
          const Text('Execute & Monitor', style: TextStyle(fontSize: 17)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The agent will analyze the market, place orders automatically, '
              'then monitor them until stop-loss, target, or manual exit.',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            _confirmRow(Icons.currency_rupee, 'Capital', _currency.format(capital)),
            _confirmRow(Icons.swap_horiz, 'Order type', _orderType),
            _confirmRow(Icons.layers, 'Max stocks', '$_maxPositions'),
            _confirmRow(Icons.percent, 'Risk / trade', '${_riskPercent.toStringAsFixed(1)}%'),
            _confirmRow(Icons.trending_down, 'Daily loss cap', '${_maxDailyLossPct.toStringAsFixed(1)}%'),
            if (_leverage > 1)
              _confirmRow(Icons.speed, 'Leverage', '${_leverage}x'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo[700],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.bolt_rounded, color: Colors.white, size: 16),
            label: const Text('Execute', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final live = context.read<LiveTradingProvider>();
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
      // 1. Start the monitoring agent
      await live.startAgent(
        userId: auth.user!.userId,
        accessToken: auth.user!.accessToken,
        apiKey: auth.user!.apiKey,
        settings: settings,
      );
      if (!mounted) return;
      if (live.error != null) throw Exception(live.error);

      // 2. Analyze market
      setState(() => _overlayMessage = 'Analyzing market...');
      live.placedOrderSymbols.clear();
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
          .take(_maxPositions)
          .toList();

      if (qualifying.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text(
              'No qualifying signals found right now. '
              'Agent is running — you can register positions manually.',
            ),
            backgroundColor: Colors.orange[700],
            duration: const Duration(seconds: 6),
          ));
        }
        return;
      }

      // 3. Place orders for each qualifying candidate
      int placed = 0;
      int failed = 0;
      for (int i = 0; i < qualifying.length; i++) {
        if (!mounted) break;
        final c = qualifying[i];
        final symbol = c['symbol'] as String? ?? '';
        setState(() => _overlayMessage = 'Placing order ${i + 1}/${qualifying.length} — $symbol...');

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
          capitalToUse: capital,
          riskPercent: _riskPercent,
          leverage: _leverage,
          orderType: _orderType,
        );
        if (qty > 0) { placed++; } else { failed++; }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(placed > 0
            ? '✓ $placed $_orderType order${placed == 1 ? '' : 's'} placed. Agent is monitoring...'
                '${failed > 0 ? ' ($failed failed)' : ''}'
            : 'All orders failed. Check Zerodha. Agent is still running.'),
        backgroundColor: placed > 0 ? Colors.green[700] : Colors.red[700],
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red[700],
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

  Widget _confirmRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ]),
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
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: p.action == 'BUY' ? Colors.green[50] : Colors.red[50],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(p.action,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: p.action == 'BUY' ? Colors.green[700] : Colors.red[700])),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(p.symbol,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    Text(
                      '${isProfit ? '+' : ''}${_currency.format(p.currentPnl)}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isProfit ? Colors.green[700] : Colors.red[600]),
                    ),
                  ]),
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
      _applyFromSettings(context.read<LiveTradingProvider>().lastSettings);
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
            prefill != null ? 'Register Position: ${prefill['symbol']}' : 'Register Position',
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
                Row(children: [
                  const Text('Direction: ', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  _actionChip('BUY', action, Colors.green[700]!, () => setDlgState(() => action = 'BUY')),
                  const SizedBox(width: 8),
                  _actionChip('SELL', action, Colors.red[700]!, () => setDlgState(() => action = 'SELL')),
                ]),
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
            ? '✓ $sym registered — agent is monitoring this position'
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
        child: Text(label,
            style: TextStyle(
              color: selected ? color : Colors.grey[600],
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            )),
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
                // ── Agent status card ─────────────────────────────────
                _buildStatusCard(status, live.isLoading, isRunning),
                const SizedBox(height: 16),

                // ── Error banner ──────────────────────────────────────
                if (live.error != null)
                  _buildBanner(live.error!.replaceFirst('Exception: ', ''), Colors.red),

                // ── RUNNING STATE ─────────────────────────────────────
                if (isRunning) ...[
                  // Pending limit orders
                  if (status.pendingOrders.isNotEmpty) ...[
                    _buildSectionHeader(
                        'Pending Orders (${status.pendingOrders.length})',
                        Icons.pending_actions,
                        Colors.orange[700]!),
                    const SizedBox(height: 8),
                    ...status.pendingOrders.map(_buildPendingOrderCard),
                    const SizedBox(height: 16),
                  ],

                  // Monitored positions
                  if (status.openPositions.isNotEmpty) ...[
                    _buildSectionHeader(
                        'Monitored Positions (${status.openPositions.length})',
                        Icons.track_changes,
                        Colors.green[700]!),
                    const SizedBox(height: 8),
                    ...status.openPositions.map(_buildPositionCard),
                    const SizedBox(height: 16),
                  ],

                  // Active settings summary
                  _buildSectionHeader('Active Settings', Icons.tune, Colors.indigo[400]!),
                  const SizedBox(height: 8),
                  _buildActiveSettingsBadges(status.settings),
                  const SizedBox(height: 16),

                  // Manual register button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.indigo[700],
                        side: BorderSide(color: Colors.indigo[300]!),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Register Position Manually',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () => _showRegisterDialog(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── STOPPED STATE ─────────────────────────────────────
                if (!isRunning) ...[
                  _buildConfigCard(),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo[700],
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.rocket_launch_rounded, color: Colors.white),
                      label: const Text(
                        'Execute & Monitor',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                      onPressed: live.isLoading ? null : _executeAndMonitor,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Activity log (always) ─────────────────────────────
                _buildSectionHeader('Activity Log', Icons.receipt_long, Colors.blueGrey),
                const SizedBox(height: 8),
                _buildLogList(status.recentLogs),
              ],
            ),
          ),
        ),

        // ── Loading overlay ───────────────────────────────────────────
        if (_isInitializing) _buildLoadingOverlay(_overlayMessage),
      ],
    );
  }

  // ── Config card (stopped state) ───────────────────────────────────────────

  Widget _buildConfigCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Trading Configuration',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // Capital field
            TextField(
              controller: _capitalController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(
                labelText: 'Capital to Deploy (₹)',
                prefixIcon: const Icon(Icons.currency_rupee, size: 18),
                helperText: 'Total rupees to use for this session',
                helperStyle: const TextStyle(fontSize: 11),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 20),

            // Order type toggle
            Row(children: [
              Text('Order Type:',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800])),
              const SizedBox(width: 12),
              _typeChip('LIMIT'),
              const SizedBox(width: 8),
              _typeChip('MARKET'),
            ]),
            if (_orderType == 'MARKET') ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.orange[700]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Market orders execute immediately at the current market price.',
                      style: TextStyle(fontSize: 11, color: Colors.orange[800]),
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 20),

            // Sliders
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
            _buildSlider(
              label: 'Leverage',
              displayLabel: '${_leverage}x',
              value: _leverage.toDouble(),
              min: 1, max: 5, divisions: 4,
              onChanged: (v) => setState(() => _leverage = v.round()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(String type) {
    final selected = _orderType == type;
    return GestureDetector(
      onTap: () => setState(() => _orderType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.indigo[700] : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? Colors.indigo[700]! : Colors.grey[400]!),
        ),
        child: Text(
          type,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey[700],
            fontWeight: FontWeight.bold,
            fontSize: 13,
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
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        SizedBox(
          width: 110,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Text(displayLabel,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo[700])),
          ]),
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
      ]),
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
            Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isRunning ? Colors.greenAccent : Colors.white38,
                  shape: BoxShape.circle,
                  boxShadow: isRunning
                      ? [BoxShadow(
                          color: Colors.greenAccent.withValues(alpha: 0.6),
                          blurRadius: 6)]
                      : [],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isRunning ? 'Agent Running' : 'Agent Stopped',
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
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.stop_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text('Stop',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ]),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              _buildStatChip(
                  'Positions',
                  '${status.openPositions.length}/${status.settings.maxPositions}',
                  Icons.layers),
              const SizedBox(width: 10),
              _buildStatChip(
                  'Trades', '${status.tradeCountToday}', Icons.swap_horiz),
              const SizedBox(width: 10),
              _buildStatChip(
                'Day P&L',
                '${isProfit ? '+' : ''}${_currency.format(pnl)}',
                isProfit ? Icons.trending_up : Icons.trending_down,
                valueColor: isProfit ? Colors.greenAccent[100] : Colors.red[200],
              ),
            ]),
            if (isRunning) ...[
              const SizedBox(height: 10),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.greenAccent, width: 0.8),
                  ),
                  child: Text('Monitoring Active',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.greenAccent[100])),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: status.tickerConnected
                        ? Colors.greenAccent
                        : Colors.orange[300],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  status.tickerConnected ? 'Live feed' : 'Polling',
                  style: TextStyle(
                      color: status.tickerConnected
                          ? Colors.greenAccent[100]
                          : Colors.orange[200],
                      fontSize: 10),
                ),
              ]),
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
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red[200], size: 16),
                  const SizedBox(width: 6),
                  Text('Daily loss limit hit — no new trades',
                      style: TextStyle(color: Colors.red[200], fontSize: 12)),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value, IconData icon,
      {Color? valueColor}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 12, color: Colors.white60),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
          ]),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  // ── Active settings badges (running state) ─────────────────────────────────

  Widget _buildActiveSettingsBadges(AgentSettingsModel s) {
    final badges = [
      '${s.maxPositions} stocks',
      '${s.riskPercent}% risk/trade',
      '${s.maxDailyLossPct}% loss cap',
      if (s.leverage > 1) '${s.leverage}x leverage',
      if (s.capitalToUse > 0) '₹${(s.capitalToUse / 1000).toStringAsFixed(0)}k capital',
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
                        fontSize: 12,
                        color: Colors.indigo[700],
                        fontWeight: FontWeight.w600)),
              ))
          .toList(),
    );
  }

  // ── Pending order card ─────────────────────────────────────────────────────

  Widget _buildPendingOrderCard(PendingOrderModel order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[300]!),
        boxShadow: [
          BoxShadow(color: Colors.orange.withValues(alpha: 0.1), blurRadius: 6)
        ],
      ),
      child: Row(children: [
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Colors.orange[700]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(order.symbol,
                  style:
                      const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green[700]!.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(order.action,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700])),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              'Limit ₹${order.limitPrice.toStringAsFixed(2)} · '
              'SL ₹${order.stopLoss.toStringAsFixed(2)} · '
              'Tgt ₹${order.target.toStringAsFixed(2)} · '
              'qty ${order.quantity}',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.orange[200]!),
          ),
          child: Text('PENDING',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[800],
                  letterSpacing: 0.8)),
        ),
      ]),
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
        child: Column(children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isBuy ? Colors.green[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(pos.action,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isBuy ? Colors.green[700] : Colors.red[700])),
            ),
            const SizedBox(width: 8),
            Text(pos.symbol,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            if (pos.trailActivated) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(6)),
                child: Text(
                  pos.trailCount > 0 ? 'TRAIL ×${pos.trailCount}' : 'TRAIL',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[700]),
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
          ]),
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
        ]),
      ),
    );
  }

  Widget _buildPriceLabel(String label, double value,
      {Color? color, bool isQty = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
      Text(
        isQty ? value.toInt().toString() : _currency.format(value),
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color ?? Colors.grey[800]),
      ),
    ]);
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
        child: Text('No activity yet.',
            style: TextStyle(color: Colors.grey[500], fontSize: 13)),
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
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(log.timestamp,
            style: TextStyle(
                fontSize: 10,
                color: Colors.grey[500],
                fontFamily: 'monospace')),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4)),
          child: Text(log.event,
              style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.bold, color: color)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(log.message,
              style: const TextStyle(fontSize: 11),
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
    return Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 6),
      Text(title,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.bold, color: color)),
    ]);
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
      child: Row(children: [
        Icon(
          color == Colors.red ? Icons.error_outline : Icons.info_outline,
          color: color[700],
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
            child: Text(message,
                style: TextStyle(color: color[700], fontSize: 12))),
      ]),
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
                    child: const Icon(Icons.rocket_launch_rounded,
                        color: Colors.white, size: 34),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),
            Text(message,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}
