import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../theme/vt_color_scheme.dart';

const String _kKey = 'vantrade_trade_disclaimer_v1';
const int _kCountdown = 10;

/// Shows the full-screen risk disclaimer the first time the user executes
/// live trades. Returns [true] if the user accepted, [false] if cancelled.
/// After acceptance the key is persisted so it never shows again.
Future<bool> showTradeRiskDisclaimer(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kKey) == true) return true;
  if (!context.mounted) return false;

  final accepted = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.82),
    barrierLabel: 'Risk disclaimer',
    transitionDuration: const Duration(milliseconds: 280),
    transitionBuilder: (_, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1.0)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
    pageBuilder: (ctx, _, _) => const _DisclaimerOverlay(),
  );

  if (accepted == true) {
    await prefs.setBool(_kKey, true);
    return true;
  }
  return false;
}

// ─────────────────────────────────────────────────────────────────────────────

class _DisclaimerOverlay extends StatefulWidget {
  const _DisclaimerOverlay();

  @override
  State<_DisclaimerOverlay> createState() => _DisclaimerOverlayState();
}

class _DisclaimerOverlayState extends State<_DisclaimerOverlay> {
  int _secondsLeft = _kCountdown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vt = context.vt;
    final mq = MediaQuery.of(context);
    final okEnabled = _secondsLeft == 0;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              Sp.base, Sp.base, Sp.base,
              mq.viewInsets.bottom + Sp.base,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: vt.surface1,
                borderRadius: BorderRadius.circular(Rad.xl),
                border: Border.all(
                    color: vt.warning.withValues(alpha: 0.45), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 32,
                    spreadRadius: 0,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(vt),
                  Divider(height: 1, color: vt.divider),
                  _buildBody(vt, mq),
                  Divider(height: 1, color: vt.divider),
                  _buildFooter(vt, okEnabled),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader(VtColorScheme vt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.base, Sp.base, Sp.base, Sp.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: vt.warning.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border:
                  Border.all(color: vt.warning.withValues(alpha: 0.3), width: 1),
            ),
            child: Icon(Icons.warning_amber_rounded,
                color: vt.warning, size: 22),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Risk Disclosure', style: AppTextStyles.h2),
                const SizedBox(height: 2),
                Text(
                  'Read carefully before executing live trades',
                  style: AppTextStyles.caption
                      .copyWith(color: vt.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Scrollable body ──────────────────────────────────────────────────────────

  Widget _buildBody(VtColorScheme vt, MediaQueryData mq) {
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxHeight: mq.size.height * 0.50),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            Sp.base, Sp.md, Sp.base, Sp.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Intro statement
            Container(
              padding: const EdgeInsets.all(Sp.md),
              decoration: BoxDecoration(
                color: vt.warning.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(Rad.md),
                border:
                    Border.all(color: vt.warning.withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 14, color: vt.warning),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: Text(
                      'VanTrade provides AI-assisted trade ideas for '
                      'informational purposes only. This is not SEBI-registered '
                      'investment advice. All trading decisions and their '
                      'consequences remain solely with you.',
                      style: AppTextStyles.caption.copyWith(
                          color: vt.warning, height: 1.55),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Sp.md),

            // Section 1 — Market Risks
            _section(
              vt: vt,
              icon: Icons.show_chart_rounded,
              color: vt.warning,
              title: 'Market Risks',
              bullets: const [
                'Stock prices can move sharply against your position. You may '
                    'lose part or all of the capital you deploy.',
                'AI signals are generated from technical indicators and do not '
                    'guarantee any profit outcome.',
                'Intraday positions are highly sensitive to gap openings, '
                    'breaking news, and liquidity gaps at specific price levels.',
                'Past performance of any trade recommendation does not predict '
                    'future returns.',
              ],
            ),
            const SizedBox(height: Sp.md),

            // Section 2 — Our Responsibility
            _section(
              vt: vt,
              icon: Icons.business_center_outlined,
              color: vt.accentPurple,
              title: 'Our Responsibility (VanTrade)',
              bullets: const [
                'We provide AI-generated trade ideas based purely on technical '
                    'analysis. We are not a SEBI-registered investment advisor.',
                'We are not liable for any financial loss arising from trade '
                    'execution, broker-side errors, network failures, or slippage.',
                'We do not guarantee that orders will fill at the suggested '
                    'entry, stop-loss, or target prices.',
                'GTT orders placed automatically may not trigger if price gaps '
                    'past the trigger level — always monitor your positions.',
              ],
            ),
            const SizedBox(height: Sp.md),

            // Section 3 — Your Responsibility
            _section(
              vt: vt,
              icon: Icons.person_outline_rounded,
              color: vt.accentGreen,
              title: 'Your Responsibility',
              bullets: const [
                'You are solely responsible for every trade you execute '
                    'through this app. Verify each price, quantity, and action '
                    'before confirming.',
                'Ensure your Zerodha account has sufficient funds and margin '
                    'before placing any order.',
                'Monitor your open positions actively, especially intraday '
                    'positions near the 3:15 PM auto-squareoff window.',
                'Never invest money you cannot afford to lose. For personalised '
                    'financial guidance, consult a SEBI-registered investment advisor.',
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required VtColorScheme vt,
    required IconData icon,
    required Color color,
    required String title,
    required List<String> bullets,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Rad.sm),
            ),
            child: Icon(icon, size: 13, color: color),
          ),
          const SizedBox(width: Sp.sm),
          Text(
            title,
            style: AppTextStyles.body.copyWith(
                color: color, fontWeight: FontWeight.w700),
          ),
        ]),
        const SizedBox(height: Sp.sm),
        ...bullets.map(
          (b) => Padding(
            padding: const EdgeInsets.only(bottom: Sp.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(
                    b,
                    style: AppTextStyles.caption
                        .copyWith(color: vt.textSecondary, height: 1.55),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Footer ───────────────────────────────────────────────────────────────────

  Widget _buildFooter(VtColorScheme vt, bool okEnabled) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Sp.base, Sp.md, Sp.base, Sp.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'By tapping "I Accept", you acknowledge that you have read, '
            'understood, and agree to the risks and responsibilities '
            'outlined above.',
            style: AppTextStyles.caption.copyWith(
                color: vt.textTertiary,
                fontStyle: FontStyle.italic,
                height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Sp.md),
          Row(
            children: [
              // Cancel
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: vt.divider),
                    foregroundColor: vt.textSecondary,
                    padding:
                        const EdgeInsets.symmetric(vertical: Sp.md),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Rad.md)),
                  ),
                  child: Text('Cancel', style: AppTextStyles.body),
                ),
              ),
              const SizedBox(width: Sp.sm),

              // I Accept / countdown
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed:
                      okEnabled ? () => Navigator.of(context).pop(true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        okEnabled ? vt.accentGreen : vt.surface3,
                    disabledBackgroundColor: vt.surface3,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: vt.textTertiary,
                    elevation: okEnabled ? 2 : 0,
                    padding: const EdgeInsets.symmetric(vertical: Sp.md),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Rad.md)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: okEnabled
                        ? [
                            const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 16,
                                color: Colors.white),
                            const SizedBox(width: Sp.xs),
                            Text(
                              'I Accept',
                              style: AppTextStyles.body.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700),
                            ),
                          ]
                        : [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                value: (_kCountdown - _secondsLeft) /
                                    _kCountdown,
                                strokeWidth: 2,
                                color: vt.textTertiary,
                                backgroundColor: vt.divider,
                              ),
                            ),
                            const SizedBox(width: Sp.sm),
                            Text(
                              'I Accept  (${_secondsLeft}s)',
                              style: AppTextStyles.body
                                  .copyWith(color: vt.textTertiary),
                            ),
                          ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
