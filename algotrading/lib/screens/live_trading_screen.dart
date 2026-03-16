import 'package:flutter/material.dart';
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

  bool _isInitializing = false; // full-screen overlay
  bool _isStopping = false;
  late AnimationController _pulseController;

  // Settings (editable before starting)
  int _maxPositions = 2;
  double _riskPercent = 1.0;
  int _scanIntervalMinutes = 5;
  int _maxTradesPerDay = 6;
  double _maxDailyLossPct = 2.0;
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
    if (auth.user != null) {
      context.read<LiveTradingProvider>().fetchStatus(auth.user!.userId);
    }
  }

  Future<void> _startAgent() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start Autonomous Agent'),
        content: const Text(
          'The agent will scan markets every few minutes and place real trades '
          'on your Zerodha account automatically.\n\n'
          'Make sure you are comfortable with the risk settings before proceeding.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isInitializing = true;
      _pulseController.repeat();
    });
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
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
      // Dismiss overlay as soon as API call completes (success or error)
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _pulseController.stop();
        });
      }
    }
  }

  Future<void> _stopAgent() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    final provider = context.read<LiveTradingProvider>();
    final hasPositions = provider.status.openPositions.isNotEmpty;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop Agent'),
        content: Text(
          hasPositions
              ? 'The agent will stop and immediately square off all open positions at market price.\n\n'
                'All active GTTs will be cancelled.\n\n'
                'This action cannot be undone.'
              : 'The agent will stop scanning. No open positions to close.',
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

    setState(() => _isStopping = true);
    await Future.delayed(const Duration(milliseconds: 50)); // let Flutter paint loading state
    if (!mounted) return;
    try {
      await context.read<LiveTradingProvider>().stopAgent(auth.user!.userId);
    } finally {
      if (mounted) setState(() => _isStopping = false);
    }
  }

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
        title: const Text(
          'Live Trading',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status / control card ────────────────────────────────────
            _buildStatusCard(status, live.isLoading),
            const SizedBox(height: 16),

            // ── Error banner ─────────────────────────────────────────────
            if (live.error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red[700], size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        live.error!.replaceFirst('Exception: ', ''),
                        style: TextStyle(color: Colors.red[700], fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Open positions ───────────────────────────────────────────
            if (status.openPositions.isNotEmpty) ...[
              _buildSectionHeader('Open Positions', Icons.show_chart, Colors.green[700]!),
              const SizedBox(height: 8),
              ...status.openPositions.map(_buildPositionCard),
              const SizedBox(height: 16),
            ],

            // ── Settings (only editable when stopped) ────────────────────
            if (!isRunning) ...[
              _buildSectionHeader('Agent Settings', Icons.tune, Colors.indigo[700]!),
              const SizedBox(height: 8),
              _buildSettingsCard(),
              const SizedBox(height: 16),
            ] else ...[
              _buildSectionHeader('Active Settings', Icons.tune, Colors.indigo[400]!),
              const SizedBox(height: 8),
              _buildActiveSettingsBadges(status.settings),
              const SizedBox(height: 16),
            ],

            // ── Activity log ─────────────────────────────────────────────
            _buildSectionHeader('Activity Log', Icons.receipt_long, Colors.blueGrey),
            const SizedBox(height: 8),
            _buildLogList(status.recentLogs),
          ],
        ),
      ),
    ), // end Scaffold

    // ── Full-screen loading overlay ───────────────────────────────────────
    if (_isInitializing)
      _buildLoadingOverlay(
        live.error != null
            ? 'Something went wrong'
            : isRunning
                ? 'Connecting to live feed...'
                : 'Starting agent...',
      ),
  ], // end Stack children
); // end Stack
  }

  // ── Loading overlay ───────────────────────────────────────────────────────

  Widget _buildLoadingOverlay(String message) {
    return Container(
      color: Colors.indigo[900]!.withValues(alpha: 0.95),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (ctx, _) {
                return Stack(
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
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 38),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 36),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 10),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Please wait...',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── Status card ──────────────────────────────────────────────────────────

  Widget _buildStatusCard(AgentStatusModel status, bool isLoading) {
    final isRunning = status.isRunning;
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
            // Status row
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
                  isRunning ? _statusLabel(status.status) : 'Agent Stopped',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                _buildToggleButton(isRunning, isLoading: _isStopping),
              ],
            ),
            const SizedBox(height: 16),

            // Stats row
            Row(
              children: [
                _buildStatChip('Trades', '${status.tradeCountToday}', Icons.swap_horiz),
                const SizedBox(width: 10),
                _buildStatChip(
                  'Day P&L',
                  '${isProfit ? '+' : ''}${_currency.format(pnl)}',
                  isProfit ? Icons.trending_up : Icons.trending_down,
                  valueColor: isProfit ? Colors.greenAccent[100] : Colors.red[200],
                ),
                const SizedBox(width: 10),
                _buildStatChip(
                  'Positions',
                  '${status.openPositions.length}/${status.settings.maxPositions}',
                  Icons.layers,
                ),
              ],
            ),

            // Phase indicator + ticker feed status (only when running)
            if (isRunning) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  // Phase badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: status.scanningDone
                          ? Colors.green.withValues(alpha: 0.25)
                          : Colors.amber.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: status.scanningDone ? Colors.greenAccent : Colors.amber,
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      status.scanningDone ? 'Phase 2: Monitoring' : 'Phase 1: Scanning',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: status.scanningDone ? Colors.greenAccent[100] : Colors.amber[200],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Ticker dot
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
                    Text(
                      'Daily loss limit hit — no new trades',
                      style: TextStyle(color: Colors.red[200], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],

            if (status.lastScanAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last scan: ${status.lastScanAt}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToggleButton(bool isRunning, {bool isLoading = false}) {
    if (isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 6),
            Text(
              isRunning ? 'Stopping...' : 'Starting...',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: isRunning ? _stopAgent : _startAgent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isRunning ? Colors.red[400] : Colors.greenAccent[400],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 4),
            Text(
              isRunning ? 'Stop' : 'Start',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
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
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── Open positions ────────────────────────────────────────────────────────

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
                      color: isBuy ? Colors.green[700] : Colors.red[700],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  pos.symbol,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                if (pos.trailActivated) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      pos.trailCount > 0 ? 'TRAIL ×${pos.trailCount}' : 'TRAIL',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange[700]),
                    ),
                  ),
                ],
                if (pos.targetAdjusted) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purple[50],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'TGT ADJ',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.purple[700]),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  '${isProfit ? '+' : ''}${_currency.format(pos.currentPnl)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isProfit ? Colors.green[700] : Colors.red[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildPriceLabel('Entry', pos.entryPrice),
                _buildPriceLabel('SL', pos.stopLoss, color: Colors.red[600]),
                if (pos.targetAdjusted)
                  _buildAdjustedTargetLabel(pos)
                else
                  _buildPriceLabel('Target', pos.target, color: Colors.green[700]),
                _buildPriceLabel('Qty', pos.quantity.toDouble(), isQty: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdjustedTargetLabel(AgentPositionModel pos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Target', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        Text(
          _currency.format(pos.target),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.purple[700]),
        ),
        Text(
          _currency.format(pos.originalTarget),
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[400],
            decoration: TextDecoration.lineThrough,
          ),
        ),
      ],
    );
  }

  Widget _buildPriceLabel(String label, double value, {Color? color, bool isQty = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        Text(
          isQty ? value.toInt().toString() : _currency.format(value),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color ?? Colors.grey[800],
          ),
        ),
      ],
    );
  }

  // ── Settings card ─────────────────────────────────────────────────────────

  Widget _buildSettingsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSliderRow(
              label: 'Max Positions',
              value: _maxPositions.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              display: '$_maxPositions',
              onChanged: (v) => setState(() => _maxPositions = v.round()),
            ),
            const Divider(height: 20),
            _buildSliderRow(
              label: 'Risk per Trade',
              value: _riskPercent,
              min: 0.5,
              max: 3.0,
              divisions: 5,
              display: '${_riskPercent.toStringAsFixed(1)}%',
              onChanged: (v) => setState(() => _riskPercent = double.parse(v.toStringAsFixed(1))),
            ),
            const Divider(height: 20),
            _buildSliderRow(
              label: 'Scan Interval',
              value: _scanIntervalMinutes.toDouble(),
              min: 5,
              max: 30,
              divisions: 5,
              display: '$_scanIntervalMinutes min',
              onChanged: (v) => setState(() => _scanIntervalMinutes = v.round()),
            ),
            const Divider(height: 20),
            _buildSliderRow(
              label: 'Max Trades/Day',
              value: _maxTradesPerDay.toDouble(),
              min: 2,
              max: 10,
              divisions: 8,
              display: '$_maxTradesPerDay',
              onChanged: (v) => setState(() => _maxTradesPerDay = v.round()),
            ),
            const Divider(height: 20),
            _buildSliderRow(
              label: 'Max Daily Loss',
              value: _maxDailyLossPct,
              min: 1.0,
              max: 5.0,
              divisions: 4,
              display: '${_maxDailyLossPct.toStringAsFixed(1)}%',
              onChanged: (v) => setState(() => _maxDailyLossPct = double.parse(v.toStringAsFixed(1))),
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Capital to Use', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    Text(
                      _capitalToUse == 0 ? 'Full available balance' : _currency.format(_capitalToUse),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _showCapitalDialog,
                  child: Text('Set', style: TextStyle(color: Colors.indigo[700])),
                ),
              ],
            ),
            const Divider(height: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('MIS Leverage', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Text(
                        '${_leverage}x',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange[800]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Multiplies effective capital for MIS intraday orders',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [1, 2, 3, 4, 5].map((lev) {
                    final sel = _leverage == lev;
                    final isFirst = lev == 1;
                    final isLast = lev == 5;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _leverage = lev),
                        child: Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: sel ? Colors.orange[700] : Colors.grey[50],
                            borderRadius: BorderRadius.horizontal(
                              left: isFirst ? const Radius.circular(8) : Radius.zero,
                              right: isLast ? const Radius.circular(8) : Radius.zero,
                            ),
                            border: Border(
                              top: BorderSide(color: sel ? Colors.orange[700]! : Colors.grey[300]!),
                              bottom: BorderSide(color: sel ? Colors.orange[700]! : Colors.grey[300]!),
                              left: BorderSide(color: sel ? Colors.orange[700]! : Colors.grey[300]!),
                              right: isLast
                                  ? BorderSide(color: sel ? Colors.orange[700]! : Colors.grey[300]!)
                                  : BorderSide.none,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${lev}x',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: sel ? Colors.white : Colors.grey[600],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: Colors.indigo[700],
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            display,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo[700]),
          ),
        ),
      ],
    );
  }

  void _showCapitalDialog() {
    final controller = TextEditingController(
      text: _capitalToUse > 0 ? _capitalToUse.toStringAsFixed(0) : '',
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Capital to Use'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            prefixText: '₹ ',
            hintText: '0 = full available balance',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text) ?? 0.0;
              setState(() => _capitalToUse = val);
              Navigator.pop(ctx);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSettingsBadges(AgentSettingsModel s) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _badge('Max ${s.maxPositions} positions', Colors.indigo),
        _badge('Risk ${s.riskPercent.toStringAsFixed(1)}%/trade', Colors.blue),
        _badge('Scan every ${s.scanIntervalMinutes} min', Colors.teal),
        _badge('Max ${s.maxTradesPerDay} trades/day', Colors.purple),
        _badge('Stop at ${s.maxDailyLossPct.toStringAsFixed(1)}% loss', Colors.red),
        if (s.capitalToUse > 0) _badge('Capital: ${_currency.format(s.capitalToUse)}', Colors.orange),
        if (s.leverage > 1) _badge('${s.leverage}x leverage', Colors.orange),
      ],
    );
  }

  Widget _badge(String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color[200]!),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color[800], fontWeight: FontWeight.w500)),
    );
  }

  // ── Activity log ──────────────────────────────────────────────────────────

  Widget _buildLogList(List<AgentLogModel> logs) {
    if (logs.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('No activity yet', style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: logs.take(30).map(_buildLogTile).toList(),
      ),
    );
  }

  Widget _buildLogTile(AgentLogModel log) {
    final meta = _logMeta(log.event);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
      ),
      child: ListTile(
        dense: true,
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: meta.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(meta.icon, size: 14, color: meta.color),
        ),
        title: Text(
          log.message,
          style: const TextStyle(fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          log.timestamp,
          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey[800]),
        ),
      ],
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'SCANNING': return 'Scanning Markets...';
      case 'MONITORING': return 'Monitoring Positions';
      case 'SQUARING_OFF': return 'Squaring Off Positions...';
      case 'PAUSED': return 'Paused (daily limit)';
      default: return status;
    }
  }

  ({IconData icon, Color color}) _logMeta(String event) {
    switch (event) {
      case 'TRADE_OPEN': return (icon: Icons.add_circle, color: Colors.green[700]!);
      case 'POSITION_CLOSED': return (icon: Icons.check_circle, color: Colors.blue[700]!);
      case 'TRAIL_SL': return (icon: Icons.moving, color: Colors.orange[700]!);
      case 'SQUAREOFF': return (icon: Icons.alarm, color: Colors.red[700]!);
      case 'SIGNAL': return (icon: Icons.bolt, color: Colors.amber[700]!);
      case 'SCAN_START': return (icon: Icons.search, color: Colors.indigo[400]!);
      case 'SCAN_RESULT': return (icon: Icons.checklist, color: Colors.indigo[600]!);
      case 'SCAN_DONE': return (icon: Icons.done_all, color: Colors.green[600]!);
      case 'TARGET_ADJ': return (icon: Icons.adjust, color: Colors.purple[600]!);
      case 'ERROR': return (icon: Icons.error_outline, color: Colors.red[600]!);
      case 'DAILY_LIMIT': return (icon: Icons.block, color: Colors.red[700]!);
      case 'GTT_UPDATED': return (icon: Icons.update, color: Colors.teal[600]!);
      case 'GTT_CANCEL': return (icon: Icons.cancel, color: Colors.orange[600]!);
      case 'CAPITAL': return (icon: Icons.account_balance_wallet, color: Colors.green[600]!);
      case 'POS_UPDATE': return (icon: Icons.show_chart, color: Colors.blue[500]!);
      default: return (icon: Icons.info_outline, color: Colors.grey[600]!);
    }
  }
}
