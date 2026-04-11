import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'opportunity_execute_sheet.dart';

/// Full-screen alarm that behaves like a native alarm app:
///   • Forces screen on (wakelock) — shows even when phone is sleeping
///   • Continuous vibration pattern (SOS: short-short-short-long)
///   • Looping audio
///   • Background pulses red every second
///   • 30-second countdown with slide-to-confirm UX
///   • Countdown ring turns red when < 10 s remain
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
    with TickerProviderStateMixin {

  // ── Audio ─────────────────────────────────────────────────────────────────
  final _audio = AudioPlayer();

  // ── Formatters ────────────────────────────────────────────────────────────
  final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  // ── Countdown ─────────────────────────────────────────────────────────────
  static const int _totalSeconds = 30;
  int _secondsLeft = _totalSeconds;
  Timer? _countdownTimer;

  // ── Background pulse (whole screen flashes) ───────────────────────────────
  late AnimationController _bgPulseCtrl;
  late Animation<double>   _bgPulseAnim;

  // ── Icon ring pulse ───────────────────────────────────────────────────────
  late AnimationController _iconPulseCtrl;
  late Animation<double>   _iconScaleAnim;

  // ── Slide-to-approve slider ───────────────────────────────────────────────
  double _slideValue = 0.0;          // 0.0 → 1.0
  bool   _slideTriggered = false;

  bool _dismissed = false;

  // ── Colour palette ────────────────────────────────────────────────────────
  Color get _accentColor {
    switch (widget.mode) {
      case 'NIFTY':     return const Color(0xFF4F46E5);
      case 'BANKNIFTY': return const Color(0xFF7C3AED);
      default:          return Colors.green[700]!;
    }
  }

  @override
  void initState() {
    super.initState();

    // Keep screen on (wakelock)
    WakelockPlus.enable();

    // Force full brightness + show on lock screen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Background pulse — slow breath (1 second per pulse = matches countdown)
    _bgPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _bgPulseAnim = Tween<double>(begin: 0.0, end: 0.07).animate(
      CurvedAnimation(parent: _bgPulseCtrl, curve: Curves.easeInOut),
    );

    // Icon scale pulse — faster, more urgent
    _iconPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    _iconScaleAnim = Tween<double>(begin: 0.88, end: 1.12).animate(
      CurvedAnimation(parent: _iconPulseCtrl, curve: Curves.easeInOut),
    );

    _startAlarm();
    _startVibration();
    _startCountdown();
  }

  // ── Alarm audio ────────────────────────────────────────────────────────────

  Future<void> _startAlarm() async {
    try {
      await _audio.setReleaseMode(ReleaseMode.loop);
      await _audio.play(AssetSource('sounds/opportunity_alarm.mp3'));
    } catch (_) {
      // Silent fallback — vibration still fires
    }
  }

  // ── Vibration ─────────────────────────────────────────────────────────────
  // Pattern: 200ms on, 100ms off × 3 (short bursts), then 600ms long, 400ms pause → repeat

  Future<void> _startVibration() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(
        pattern: [0, 200, 100, 200, 100, 200, 100, 600, 400],
        repeat: 0, // repeat from index 0 = infinite
        intensities: [0, 255, 0, 200, 0, 255, 0, 255, 0],
      );
    }
  }

  // ── Countdown ──────────────────────────────────────────────────────────────

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_secondsLeft <= 1) {
        t.cancel();
        _autoReject();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _bgPulseCtrl.dispose();
    _iconPulseCtrl.dispose();
    _audio.stop();
    _audio.dispose();
    Vibration.cancel();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _clearPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_opportunity');
  }

  Future<void> _autoReject() async {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    Vibration.cancel();
    await _clearPending();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _reject() async {
    if (_dismissed) return;
    _dismissed = true;
    _countdownTimer?.cancel();
    Vibration.cancel();
    await _clearPending();
    if (mounted) Navigator.of(context).pop();
  }

  void _approve() {
    if (_dismissed) return;
    _dismissed = true;
    _countdownTimer?.cancel();
    Vibration.cancel();
    _audio.stop();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => OpportunityExecuteSheet(
          mode:         widget.mode,
          stocks:       widget.stocks,
          optionsTrade: widget.optionsTrade,
          expiryDate:   widget.expiryDate,
          analysisId:   widget.analysisId,
          preAnalyzed:  true,
        ),
      ),
    ).then((_) async => await _clearPending());
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isUrgent = _secondsLeft <= 10;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _reject(); },
      child: AnimatedBuilder(
        animation: _bgPulseAnim,
        builder: (context, child) {
          final pulseAlpha = (_bgPulseAnim.value * 255).round();
          return Scaffold(
            backgroundColor: Color.fromARGB(255, 10, 10, 10),
            body: Stack(
              children: [
                // ── Pulsing red background overlay ─────────────────────────
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.topCenter,
                        radius: 1.5,
                        colors: [
                          Color.fromARGB(pulseAlpha, 220, 0, 0),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // ── Main content ───────────────────────────────────────────
                SafeArea(child: _buildContent(isUrgent)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(bool isUrgent) {
    return Column(
      children: [
        // ── Header: ring + icon + title ─────────────────────────────────
        _buildHeader(isUrgent),

        Divider(color: Colors.grey[850], height: 1),

        // ── Trade details ───────────────────────────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            children: [
              if (widget.mode == 'STOCKS')
                ...widget.stocks.map(_buildStockTile)
              else if (widget.optionsTrade != null)
                _buildOptionsTile(widget.optionsTrade!)
              else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Opportunity detected — slide to execute.',
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),

        // ── Bottom: slide-to-approve + reject ───────────────────────────
        _buildActions(),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(bool isUrgent) {
    final ringColor = isUrgent ? Colors.red[600]! : Colors.orange[400]!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
      child: Column(
        children: [
          // Countdown ring + pulsing icon
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer ring
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: _secondsLeft / _totalSeconds,
                    strokeWidth: 6,
                    backgroundColor: Colors.grey[850],
                    color: ringColor,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                // Pulsing icon
                ScaleTransition(
                  scale: _iconScaleAnim,
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1A0000),
                      border: Border.all(color: ringColor, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: ringColor.withValues(alpha: 0.6),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_active,
                              color: ringColor, size: 26),
                          Text(
                            '$_secondsLeft',
                            style: TextStyle(
                              color: ringColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),
          const Text(
            'TRADE ALERT',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 8),

          // Mode badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _accentColor, width: 1.5),
            ),
            child: Text(
              widget.mode,
              style: TextStyle(
                color: _accentColor,
                fontWeight: FontWeight.bold,
                fontSize: 15,
                letterSpacing: 2,
              ),
            ),
          ),

          const SizedBox(height: 8),
          Text(
            'High-confidence opportunity detected',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
          if (isUrgent)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Auto-dismisses in $_secondsLeft s',
                style: TextStyle(
                  color: Colors.red[400],
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Bottom actions ─────────────────────────────────────────────────────────

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        border: Border(top: BorderSide(color: Colors.grey[850]!)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Slide to approve ──────────────────────────────────────────
          _buildSlider(),
          const SizedBox(height: 12),

          // ── Reject text button ─────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _reject,
              icon: const Icon(Icons.close, size: 18),
              label: const Text(
                'Dismiss — Skip This Trade',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey[400],
                side: BorderSide(color: Colors.grey[700]!, width: 1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider() {
    return LayoutBuilder(builder: (ctx, constraints) {
      const thumbW = 64.0;
      final trackW = constraints.maxWidth;
      final maxSlide = trackW - thumbW - 8;

      return GestureDetector(
        onHorizontalDragUpdate: (d) {
          if (_slideTriggered || _dismissed) return;
          setState(() {
            _slideValue = ((_slideValue * maxSlide + d.delta.dx) / maxSlide)
                .clamp(0.0, 1.0);
          });
          if (_slideValue >= 0.95) {
            _slideTriggered = true;
            HapticFeedback.heavyImpact();
            _approve();
          }
        },
        onHorizontalDragEnd: (_) {
          if (_slideTriggered) return;
          setState(() => _slideValue = 0.0);
        },
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: Colors.green[900]!.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.green[700]!, width: 1.5),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Track label
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: thumbW / 2),
                    Text(
                      'Slide to Execute  →',
                      style: TextStyle(
                        color: Colors.green[300]!
                            .withValues(alpha: 1.0 - _slideValue),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              // Sliding thumb
              Positioned(
                left: 4 + _slideValue * maxSlide,
                child: Container(
                  width: thumbW,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.green[600],
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.double_arrow, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  // ── Trade tiles ────────────────────────────────────────────────────────────

  Widget _buildStockTile(Map<String, dynamic> s) {
    final symbol = s['stock_symbol']      as String? ?? '—';
    final action = s['action']            as String? ?? 'BUY';
    final entry  = (s['entry_price']      as num?)?.toDouble() ?? 0;
    final sl     = (s['stop_loss']        as num?)?.toDouble() ?? 0;
    final target = (s['target_price']     as num?)?.toDouble() ?? 0;
    final conf   = (s['confidence_score'] as num?)?.toDouble() ?? 0;
    final isBuy  = action == 'BUY';
    final accent = isBuy ? Colors.green[400]! : Colors.red[400]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _typeBadge(isBuy ? 'BUY' : 'SHORT', accent),
          const SizedBox(width: 10),
          Text(symbol,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
          const Spacer(),
          _confBadge(conf),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _priceCell('Entry',  _currency.format(entry),  Colors.white70)),
          Expanded(child: _priceCell('SL',     _currency.format(sl),     Colors.red[400]!)),
          Expanded(child: _priceCell('Target', _currency.format(target), Colors.green[400]!)),
        ]),
      ]),
    );
  }

  Widget _buildOptionsTile(Map<String, dynamic> t) {
    final signal    = t['signal']            as String? ?? '—';
    final optType   = t['option_type']       as String? ?? '—';
    final strike    = t['strike_price'];
    final entry     = (t['entry_premium']    as num?)?.toDouble() ?? 0;
    final sl        = (t['stop_loss']        as num?)?.toDouble() ?? 0;
    final target    = (t['target_price']     as num?)?.toDouble() ?? 0;
    final conf      = (t['confidence_score'] as num?)?.toDouble() ?? 0;
    final lots      = t['lots']?.toString() ?? '1';
    final expiry    = t['expiry_date']       as String? ?? widget.expiryDate;
    final maxLoss   = (t['max_loss']         as num?)?.toDouble();
    final maxProfit = (t['max_profit']       as num?)?.toDouble();
    final isCE      = optType == 'CE';
    final accent    = isCE ? Colors.green[400]! : Colors.red[400]!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _typeBadge(isCE ? 'BUY CALL (CE)' : 'BUY PUT (PE)', accent),
          const Spacer(),
          _confBadge(conf),
        ]),
        const SizedBox(height: 12),
        _darkRow('Signal',  signal.replaceAll('_', ' ')),
        _darkRow('Strike',  '₹${strike ?? '—'}'),
        _darkRow('Expiry',  expiry),
        _darkRow('Lots',    lots),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _priceCell('Entry',  '₹${entry.toStringAsFixed(1)}',  Colors.white70)),
          Expanded(child: _priceCell('SL',     '₹${sl.toStringAsFixed(1)}',     Colors.red[400]!)),
          Expanded(child: _priceCell('Target', '₹${target.toStringAsFixed(1)}', Colors.green[400]!)),
        ]),
        if (maxLoss != null || maxProfit != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            if (maxLoss   != null)
              Expanded(child: _priceCell('Max Loss',   '₹${maxLoss.toStringAsFixed(0)}',   Colors.red[400]!)),
            if (maxProfit != null)
              Expanded(child: _priceCell('Max Profit', '₹${maxProfit.toStringAsFixed(0)}', Colors.green[400]!)),
          ]),
        ],
      ]),
    );
  }

  // ── Reusable widgets ───────────────────────────────────────────────────────

  Widget _typeBadge(String label, Color accent) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: accent.withValues(alpha: 0.5)),
    ),
    child: Text(label,
        style: TextStyle(
            color: accent, fontWeight: FontWeight.bold, fontSize: 12)),
  );

  Widget _priceCell(String label, String value, Color valueColor) => Column(
    children: [
      Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
      const SizedBox(height: 4),
      Text(value,
          style: TextStyle(
              color: valueColor, fontSize: 13, fontWeight: FontWeight.bold)),
    ],
  );

  Widget _darkRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        Text(value,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ],
    ),
  );

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
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
