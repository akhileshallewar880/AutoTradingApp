import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinput/pinput.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../theme/vt_color_scheme.dart';
import '../widgets/vantrade_logo.dart';
import '../widgets/vt_button.dart';

enum _Phase { enterPhone, sendingCode, enterOtp, verifyingOtp }

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen>
    with SingleTickerProviderStateMixin {
  _Phase _phase = _Phase.enterPhone;
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _phoneFocus = FocusNode();
  final _otpFocus = FocusNode();

  // Resend countdown
  int _resendSeconds = 0;
  Timer? _resendTimer;

  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.06, end: 0.20)
        .animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _phoneFocus.dispose();
    _otpFocus.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  // ── Resend countdown ────────────────────────────────────────────────────────

  void _startResendTimer() {
    _resendSeconds = 30;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_resendSeconds <= 1) { t.cancel(); _resendSeconds = 0; }
        else { _resendSeconds--; }
      });
    });
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  void _sendOtp() {
    final phone = _phoneCtrl.text.trim();
    if (phone.length != 10) return;
    setState(() => _phase = _Phase.sendingCode);
    context.read<AuthProvider>().startPhoneVerification(
      phoneNumber: phone,
      onCodeSent: (_) {
        if (!mounted) return;
        setState(() => _phase = _Phase.enterOtp);
        _startResendTimer();
        Future.delayed(const Duration(milliseconds: 300),
            () => _otpFocus.requestFocus());
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() => _phase = _Phase.enterPhone);
        _showError(msg);
      },
    );
  }

  void _verifyOtp() {
    if (_otpCtrl.text.length < 6) return;
    setState(() => _phase = _Phase.verifyingOtp);
    context.read<AuthProvider>().verifyOtp(
      smsCode: _otpCtrl.text,
      onSuccess: () {
        if (!mounted) return;
        _navigateAfterAuth();
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() => _phase = _Phase.enterOtp);
        _showError(msg);
      },
    );
  }

  void _resendOtp() {
    if (_resendSeconds > 0) return;
    _otpCtrl.clear();
    setState(() => _phase = _Phase.enterPhone);
    // Small delay so the UI refreshes before re-firing
    Future.delayed(const Duration(milliseconds: 200), _sendOtp);
  }

  void _navigateAfterAuth() {
    context.read<AuthProvider>().getSavedApiCredentials().then((creds) {
      if (!mounted) return;
      if (creds != null) {
        Navigator.pushReplacementNamed(context, '/login');
      } else {
        Navigator.pushReplacementNamed(context, '/api-settings');
      }
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: context.vt.danger,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final vt = context.vt;

    return PopScope(
      canPop: _phase == _Phase.enterOtp,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase == _Phase.enterOtp) {
          setState(() { _phase = _Phase.enterPhone; _otpCtrl.clear(); });
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.xl),
                  child: Column(
                    children: [
                      const SizedBox(height: Sp.xxxl),
                      _buildLogo(vt),
                      const SizedBox(height: Sp.xl),
                      _buildHeading(),
                      const SizedBox(height: Sp.xxxl),
                      if (_phase == _Phase.enterPhone || _phase == _Phase.sendingCode)
                        _buildPhoneField(vt)
                      else if (_phase == _Phase.enterOtp || _phase == _Phase.verifyingOtp)
                        _buildOtpField(vt),
                    ],
                  ),
                ),
              ),
              _buildFooter(vt),
            ],
          ),
        ),
      ),
    );
  }

  // ── Logo ─────────────────────────────────────────────────────────────────────

  Widget _buildLogo(VtColorScheme vt) {
    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (_, child) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: vt.accentGreen.withValues(alpha: _glowAnim.value),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
          child!,
        ],
      ),
      child: const VanTradeLogoWidget(size: 72),
    );
  }

  // ── Heading ───────────────────────────────────────────────────────────────────

  Widget _buildHeading() {
    final isOtpPhase = _phase == _Phase.enterOtp || _phase == _Phase.verifyingOtp;
    return Column(
      children: [
        Text(
          isOtpPhase ? 'Enter OTP' : 'Verify your number',
          style: AppTextStyles.h1,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Sp.sm),
        Text(
          isOtpPhase
              ? 'A 6-digit OTP was sent to +91 ${_phoneCtrl.text}'
              : 'We\'ll send a 6-digit OTP to confirm your identity',
          style: AppTextStyles.bodySecondary,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── Phone input ───────────────────────────────────────────────────────────────

  Widget _buildPhoneField(VtColorScheme vt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mobile Number', style: AppTextStyles.caption),
        const SizedBox(height: Sp.sm),
        Row(
          children: [
            // Country code badge
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: Sp.md),
              decoration: BoxDecoration(
                color: vt.surface2,
                borderRadius: BorderRadius.circular(Rad.md),
                border: Border.all(color: vt.divider),
              ),
              alignment: Alignment.center,
              child: Text(
                '🇮🇳  +91',
                style: AppTextStyles.body.copyWith(color: vt.textPrimary),
              ),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: TextField(
                controller: _phoneCtrl,
                focusNode: _phoneFocus,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                style: AppTextStyles.body.copyWith(color: vt.textPrimary),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '10-digit number',
                  hintStyle: AppTextStyles.body.copyWith(color: vt.textTertiary),
                  filled: true,
                  fillColor: vt.surface2,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: Sp.md, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Rad.md),
                    borderSide: BorderSide(color: vt.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Rad.md),
                    borderSide: BorderSide(color: vt.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Rad.md),
                    borderSide:
                        BorderSide(color: vt.accentPurple, width: 1.5),
                  ),
                ),
                onSubmitted: (_) => _sendOtp(),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: Sp.xs),
        Text(
          'India (+91) only. Standard SMS rates apply.',
          style: AppTextStyles.caption.copyWith(
              color: vt.textTertiary, fontSize: 11),
        ),
      ],
    );
  }

  // ── OTP input ─────────────────────────────────────────────────────────────────

  Widget _buildOtpField(VtColorScheme vt) {
    final defaultTheme = PinTheme(
      width: 48,
      height: 52,
      textStyle: AppTextStyles.mono.copyWith(
          fontSize: 20, fontWeight: FontWeight.bold, color: vt.textPrimary),
      decoration: BoxDecoration(
        color: vt.surface2,
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: vt.divider),
      ),
    );
    final focusedTheme = defaultTheme.copyDecorationWith(
      decoration: BoxDecoration(
        color: vt.surface2,
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: vt.accentPurple, width: 2),
      ),
    );
    final filledTheme = defaultTheme.copyDecorationWith(
      decoration: BoxDecoration(
        color: vt.accentPurple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: vt.accentPurple.withValues(alpha: 0.4)),
      ),
    );

    return Column(
      children: [
        Pinput(
          controller: _otpCtrl,
          focusNode: _otpFocus,
          length: 6,
          defaultPinTheme: defaultTheme,
          focusedPinTheme: focusedTheme,
          submittedPinTheme: filledTheme,
          onCompleted: (_) => _verifyOtp(),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: Sp.base),
        // Back + resend row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _phase == _Phase.verifyingOtp
                  ? null
                  : () => setState(() {
                        _phase = _Phase.enterPhone;
                        _otpCtrl.clear();
                        _resendTimer?.cancel();
                      }),
              child: Text(
                '← Change number',
                style: AppTextStyles.caption.copyWith(
                    color: vt.textSecondary),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: (_resendSeconds > 0 || _phase == _Phase.verifyingOtp)
                  ? null
                  : _resendOtp,
              child: Text(
                _resendSeconds > 0
                    ? 'Resend in ${_resendSeconds}s'
                    : 'Resend OTP',
                style: AppTextStyles.caption.copyWith(
                  color: _resendSeconds > 0
                      ? vt.textTertiary
                      : vt.accentPurple,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Footer (action buttons) ───────────────────────────────────────────────────

  Widget _buildFooter(VtColorScheme vt) {
    final auth = context.watch<AuthProvider>();
    final isLoading = _phase == _Phase.sendingCode ||
        _phase == _Phase.verifyingOtp ||
        auth.isPhoneVerifying;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.base, Sp.xl, Sp.xl),
      child: isLoading
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: vt.accentPurple,
                  ),
                ),
                const SizedBox(height: Sp.sm),
                Text(
                  _phase == _Phase.sendingCode
                      ? 'Sending OTP…'
                      : 'Verifying…',
                  style: AppTextStyles.caption,
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_phase == _Phase.enterPhone)
                  VtButton(
                    label: 'Send OTP',
                    icon: const Icon(Icons.sms_outlined,
                        size: 18, color: Colors.white),
                    onPressed: _phoneCtrl.text.length == 10 ? _sendOtp : null,
                  )
                else if (_phase == _Phase.enterOtp)
                  VtButton(
                    label: 'Verify OTP',
                    icon: const Icon(Icons.verified_outlined,
                        size: 18, color: Colors.white),
                    onPressed:
                        _otpCtrl.text.length == 6 ? _verifyOtp : null,
                  ),
                const SizedBox(height: Sp.sm),
                VtButton(
                  label: 'Try Demo Mode',
                  icon: Icon(Icons.science_outlined,
                      size: 18, color: vt.textSecondary),
                  onPressed: () async {
                    await context
                        .read<AuthProvider>()
                        .loginWithDemoData();
                    if (mounted) {
                      Navigator.pushReplacementNamed(context, '/home');
                    }
                  },
                  variant: VtButtonVariant.ghost,
                ),
                const SizedBox(height: Sp.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline,
                        size: 11, color: vt.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      'Your number is only used to verify your identity',
                      style: AppTextStyles.caption.copyWith(
                          color: vt.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
