import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'opportunity_execute_sheet.dart';

/// Full-screen alarm that appears when the auto-scanner finds a trade.
/// Rings continuously (looping audio) until the user dismisses or executes.
class OpportunityAlarmScreen extends StatefulWidget {
  final String mode; // 'STOCKS' | 'NIFTY' | 'BANKNIFTY'
  final List<Map<String, dynamic>> stocks;
  final Map<String, dynamic>? optionsTrade;
  final String expiryDate;
  final String analysisId;

  const OpportunityAlarmScreen({
    super.key,
    required this.mode,
    this.stocks        = const [],
    this.optionsTrade,
    this.expiryDate    = '',
    this.analysisId    = '',
  });

  @override
  State<OpportunityAlarmScreen> createState() => _OpportunityAlarmScreenState();
}

class _OpportunityAlarmScreenState extends State<OpportunityAlarmScreen>
    with SingleTickerProviderStateMixin {
  final _audio    = AudioPlayer();
  final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  // Pulsing animation for the alarm icon
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;

  bool _executing = false;

  @override
  void initState() {
    super.initState();

    // Pulse animation
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _startAlarm();
  }

  Future<void> _startAlarm() async {
    try {
      await _audio.setReleaseMode(ReleaseMode.loop);
      await _audio.play(AssetSource('sounds/opportunity_alarm.mp3'));
    } catch (_) {
      // fallback — alarm screen still works silently
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _audio.stop();
    _audio.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    // Clear stored alarm so HomeScreen doesn't re-show it
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_opportunity');
    if (mounted) Navigator.of(context).pop();
  }

  void _executeNow() {
    setState(() => _executing = true);
    // Stop alarm while user is in execute sheet
    _audio.pause();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OpportunityExecuteSheet(
        mode:         widget.mode,
        stocks:       widget.stocks,
        optionsTrade: widget.optionsTrade,
        expiryDate:   widget.expiryDate,
        analysisId:   widget.analysisId,
      ),
    ).then((_) async {
      // When the execute sheet closes, clear prefs and dismiss alarm
      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('pending_opportunity');
        if (mounted) Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Intercept back button — treat as dismiss (stops alarm)
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SafeArea(
          child: Column(
            children: [
              // ── Alarm header ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  children: [
                    // Pulsing alarm icon
                    ScaleTransition(
                      scale: _pulseAnim,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.red[900],
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.5),
                              blurRadius: 24,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.notifications_active,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'TRADE ALERT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Mode badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: _modeColor(widget.mode),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.mode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Auto-scanner found a high-confidence opportunity',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              Divider(color: Colors.grey[800], height: 1),

              // ── Trade details (scrollable) ─────────────────────────────
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  children: [
                    if (widget.mode == 'STOCKS') ...[
                      ...widget.stocks.map(_buildStockTile),
                    ] else if (widget.optionsTrade != null) ...[
                      _buildOptionsTile(widget.optionsTrade!),
                    ] else ...[
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'Opportunity detected — tap Execute to see details.',
                            style: TextStyle(color: Colors.grey[500], fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),

              // ── Action buttons ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  border: Border(top: BorderSide(color: Colors.grey[800]!)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Execute button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _executing ? null : _executeNow,
                        icon: const Icon(Icons.flash_on, size: 22),
                        label: const Text(
                          'Review & Execute Trade',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.green[900],
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Dismiss button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _dismiss,
                        icon: const Icon(Icons.alarm_off, size: 18),
                        label: const Text(
                          'Dismiss Alarm',
                          style: TextStyle(fontSize: 15),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red[400],
                          side: BorderSide(color: Colors.red[800]!),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Per-stock tile ─────────────────────────────────────────────────────────

  Widget _buildStockTile(Map<String, dynamic> s) {
    final symbol   = s['stock_symbol']    as String? ?? '—';
    final action   = s['action']          as String? ?? 'BUY';
    final entry    = (s['entry_price']    as num?)?.toDouble() ?? 0;
    final sl       = (s['stop_loss']      as num?)?.toDouble() ?? 0;
    final target   = (s['target_price']   as num?)?.toDouble() ?? 0;
    final conf     = (s['confidence_score'] as num?)?.toDouble() ?? 0;
    final isBuy    = action == 'BUY';
    final accentColor = isBuy ? Colors.green[400]! : Colors.red[400]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accentColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  isBuy ? 'BUY' : 'SHORT',
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                symbol,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              const Spacer(),
              _confBadge(conf),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _priceCell('Entry', _currency.format(entry), Colors.white70)),
              Expanded(child: _priceCell('SL', _currency.format(sl), Colors.red[400]!)),
              Expanded(child: _priceCell('Target', _currency.format(target), Colors.green[400]!)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Options tile ───────────────────────────────────────────────────────────

  Widget _buildOptionsTile(Map<String, dynamic> t) {
    final signal   = t['signal']          as String? ?? '—';
    final optType  = t['option_type']     as String? ?? '—';
    final strike   = t['strike_price'];
    final entry    = (t['entry_premium']  as num?)?.toDouble() ?? 0;
    final sl       = (t['stop_loss']      as num?)?.toDouble() ?? 0;
    final target   = (t['target_price']   as num?)?.toDouble() ?? 0;
    final conf     = (t['confidence_score'] as num?)?.toDouble() ?? 0;
    final lots     = t['lots']?.toString() ?? '1';
    final expiry   = t['expiry_date']     as String? ?? widget.expiryDate;
    final maxLoss  = (t['max_loss']       as num?)?.toDouble();
    final maxProfit= (t['max_profit']     as num?)?.toDouble();
    final isCE     = optType == 'CE';
    final accentColor = isCE ? Colors.green[400]! : Colors.red[400]!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accentColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  isCE ? 'BUY CALL (CE)' : 'BUY PUT (PE)',
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              _confBadge(conf),
            ],
          ),
          const SizedBox(height: 12),
          _darkRow('Signal',  signal.replaceAll('_', ' ')),
          _darkRow('Strike',  '₹${strike ?? '—'}'),
          _darkRow('Expiry',  expiry),
          _darkRow('Lots',    lots),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _priceCell('Entry', '₹${entry.toStringAsFixed(1)}', Colors.white70)),
              Expanded(child: _priceCell('SL',    '₹${sl.toStringAsFixed(1)}',    Colors.red[400]!)),
              Expanded(child: _priceCell('Target','₹${target.toStringAsFixed(1)}',Colors.green[400]!)),
            ],
          ),
          if (maxLoss != null || maxProfit != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (maxLoss != null)
                  Expanded(child: _priceCell('Max Loss',   '₹${maxLoss.toStringAsFixed(0)}', Colors.red[400]!)),
                if (maxProfit != null)
                  Expanded(child: _priceCell('Max Profit', '₹${maxProfit.toStringAsFixed(0)}', Colors.green[400]!)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _priceCell(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _darkRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _confBadge(double conf) {
    final color = conf >= 0.80
        ? Colors.green[400]!
        : conf >= 0.68
            ? Colors.orange[400]!
            : Colors.red[400]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '${(conf * 100).toStringAsFixed(0)}% conf',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'NIFTY':     return const Color(0xFF4F46E5); // indigo
      case 'BANKNIFTY': return const Color(0xFF7C3AED); // purple
      default:          return Colors.green[700]!;
    }
  }
}
