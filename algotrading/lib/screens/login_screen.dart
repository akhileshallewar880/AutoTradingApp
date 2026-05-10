import '../theme/vt_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/vantrade_logo.dart';
import '../widgets/vt_button.dart';
import '../widgets/vt_tour.dart';
import 'login_webview_screen.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;

  // Tour keys
  final _tourLogoKey      = GlobalKey();
  final _tourFeaturesKey  = GlobalKey();
  final _tourConnectKey   = GlobalKey();
  final _tourDemoKey      = GlobalKey();

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.08, end: 0.22).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _startTour());
  }

  Future<void> _startTour() async {
    if (!mounted) return;
    await VtTour.showIfNew(
      context: context,
      screenId: 'login',
      steps: [
        VtTourStep(
          targetKey: _tourLogoKey,
          title: 'Welcome to VanTrade!',
          body: 'Your AI-powered stock trading assistant. We use GPT-4o to analyse NSE markets and generate trade setups — so you trade smarter, not harder.',
          padding: const EdgeInsets.all(20),
          radius: 60,
        ),
        VtTourStep(
          targetKey: _tourFeaturesKey,
          title: 'Three Superpowers in One App',
          body: 'AI Picks: GPT-4o scans 100+ stocks and picks the best setups.\nAuto Trade: Place orders on Zerodha with one tap.\nReal-time: Live prices, P&L, and order tracking.',
        ),
        VtTourStep(
          targetKey: _tourConnectKey,
          title: 'Connect Your Zerodha Account',
          body: 'Tap here to log in via Zerodha\'s official OAuth. Your password is NEVER shared with VanTrade — we only receive a secure access token.',
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          radius: 10,
        ),
        VtTourStep(
          targetKey: _tourDemoKey,
          title: 'Not Ready Yet? Try Demo Mode',
          body: 'Explore all of VanTrade\'s features with realistic sample data — no Zerodha account needed. Perfect for getting familiar before going live.',
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          radius: 10,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              // ── Scrollable: logo + features + error ──────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.xl),
                  child: Column(
                    children: [
                      SizedBox(height: Sp.xxxl),

                      // Logo with pulsing glow ring
                      AnimatedBuilder(
                        key: _tourLogoKey,
                        animation: _glowAnim,
                        builder: (context, child) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              // Glow ring
                              Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: context.vt.accentGreen
                                          .withValues(alpha: _glowAnim.value),
                                      blurRadius: 40,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                              child!,
                            ],
                          );
                        },
                        child: const VanTradeLogoWidget(size: 88),
                      ),

                      const SizedBox(height: Sp.xl),

                      Text('VanTrade', style: AppTextStyles.h1),
                      const SizedBox(height: Sp.sm),
                      Text(
                        'Intelligent stock analysis powered by AI',
                        style: AppTextStyles.bodySecondary,
                        textAlign: TextAlign.center,
                      ),

                      SizedBox(height: Sp.xxxl),

                      // Feature pills row
                      Row(
                        key: _tourFeaturesKey,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _FeaturePill(
                              icon: Icons.auto_awesome_outlined,
                              label: 'AI Picks'),
                          const SizedBox(width: Sp.sm),
                          _FeaturePill(
                              icon: Icons.bolt_outlined,
                              label: 'Auto Trade'),
                          const SizedBox(width: Sp.sm),
                          _FeaturePill(
                              icon: Icons.show_chart,
                              label: 'Real-time'),
                        ],
                      ),

                      // Error banner
                      if (auth.error != null) ...[
                        SizedBox(height: Sp.base),
                        Container(
                          padding: EdgeInsets.all(Sp.md),
                          decoration: BoxDecoration(
                            color: context.vt.dangerDim,
                            borderRadius: BorderRadius.circular(Rad.md),
                            border: Border.all(
                                color: context.vt.danger.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            auth.error!,
                            style: AppTextStyles.caption
                                .copyWith(color: context.vt.danger),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],

                      const SizedBox(height: Sp.xxl),
                    ],
                  ),
                ),
              ),

              // ── Fixed bottom: CTAs + trust copy ──────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Sp.xl, Sp.base, Sp.xl, Sp.xl),
                child: auth.isLoading
                    ? Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.vt.accentGreen,
                          ),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          VtButton(
                            key: _tourConnectKey,
                            label: 'Connect Zerodha',
                            icon: const Icon(Icons.link_rounded,
                                size: 18, color: Colors.white),
                            onPressed: () => _handleLogin(context, auth),
                          ),
                          SizedBox(height: Sp.sm),
                          VtButton(
                            key: _tourDemoKey,
                            label: 'Try Demo Mode',
                            icon: Icon(Icons.science_outlined,
                                size: 18, color: context.vt.textSecondary),
                            onPressed: () => _handleDemoLogin(context, auth),
                            variant: VtButtonVariant.ghost,
                          ),
                          SizedBox(height: Sp.md),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 11, color: context.vt.textTertiary),
                              SizedBox(width: 4),
                              Text(
                                '256-bit encrypted · Your credentials never leave your device',
                                style: AppTextStyles.caption.copyWith(
                                    color: context.vt.textTertiary,
                                    fontSize: 11.sp),
                                textAlign: TextAlign.center,
                              ),
                            ],
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

  Future<void> _handleDemoLogin(
      BuildContext context, AuthProvider authProvider) async {
    await authProvider.loginWithDemoData();
    if (context.mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  Future<void> _handleLogin(
      BuildContext context, AuthProvider authProvider) async {
    try {
      final loginUrl = await authProvider.getLoginUrl();
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LoginWebViewScreen(loginUrl: loginUrl),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final errorMsg = e.toString();
        if (errorMsg.contains('API credentials not found')) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('API Credentials Required'),
              content: const Text(
                'Your Zerodha API credentials are missing. '
                'Please set them up to continue.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pushReplacementNamed(context, '/api-settings');
                  },
                  child: const Text('Set Up Credentials'),
                ),
              ],
            ),
          );
        } else {
          final msg = (e.toString().contains('TimeoutException') ||
                  e.toString().contains('Connection refused') ||
                  e.toString().contains('SocketException'))
              ? 'Could not reach the server. Check your connection and try again.'
              : 'Login failed: ${e.toString().replaceFirst('Exception: ', '')}';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: context.vt.danger,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }
}

// Compact feature pill chip
class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: context.vt.surface2,
        borderRadius: BorderRadius.circular(Rad.pill),
        border: Border.all(
            color: context.vt.accentGreen.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: context.vt.accentGreen),
          SizedBox(width: 5),
          Text(
            label,
            style: AppTextStyles.label.copyWith(
              color: context.vt.textPrimary,
              letterSpacing: 0.2,
              fontSize: 11.sp,
            ),
          ),
        ],
      ),
    );
  }
}
