import '../theme/vt_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/vt_button.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  List<_OnboardingPage> _getPages(BuildContext context) => [
    _OnboardingPage(
      icon: Icons.auto_awesome_rounded,
      iconColor: context.vt.accentPurple,
      title: 'AI Stock Picks',
      body: 'GPT-4o scans the entire NSE universe every morning to find the highest-probability setups — so you never miss a trade.',
    ),
    _OnboardingPage(
      icon: Icons.shield_outlined,
      iconColor: context.vt.accentGreen,
      title: 'Built-in Risk Control',
      body: 'Every recommendation includes stop-loss and target levels. GTT orders are placed automatically — your capital stays protected.',
    ),
    _OnboardingPage(
      icon: Icons.bolt_rounded,
      iconColor: context.vt.accentGold,
      title: 'One-tap Execution',
      body: 'Review AI picks, adjust quantities, and execute directly via your Zerodha account — all in under 30 seconds.',
    ),
    _OnboardingPage(
      icon: Icons.calendar_month_outlined,
      iconColor: const Color(0xFF60A5FA),
      title: 'Intraday & Swing',
      body: 'Choose same-day intraday trades or multi-week swing positions. The AI adapts its strategy to your time horizon.',
    ),
  ];

  Future<void> _markOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
  }

  void _next() {
    if (_currentPage < _getPages(context).length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _goToSetup();
    }
  }

  void _goToSetup() {
    _markOnboardingComplete();
    Navigator.pushReplacementNamed(context, '/api-settings');
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button top-right
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(
                    top: Sp.base, right: Sp.base),
                child: TextButton(
                  onPressed: _goToSetup,
                  child: Text(
                    'Skip',
                    style: AppTextStyles.bodySecondary.copyWith(
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),

            // Page content
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _getPages(context).length,
                itemBuilder: (context, i) {
                  final page = _getPages(context)[i];
                  final isActive = i == _currentPage;
                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: isActive ? 1.0 : 0.5,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Sp.xl),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Icon in glowing circle
                          _IconCircle(
                              icon: page.icon, color: page.iconColor),
                          const SizedBox(height: Sp.xxl),
                          Text(
                            page.title,
                            style: AppTextStyles.h1,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: Sp.base),
                          Text(
                            page.body,
                            style: AppTextStyles.bodySecondary.copyWith(
                              height: 1.6,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Dot indicators + CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Sp.xl, Sp.base, Sp.xl, Sp.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Page dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_getPages(context).length, (i) {
                      final isActive = i == _currentPage;
                      return AnimatedContainer(
                        duration: Duration(milliseconds: 250),
                        margin: EdgeInsets.symmetric(horizontal: 4),
                        width: isActive ? 24 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: isActive
                              ? context.vt.accentGreen
                              : context.vt.surface3,
                          borderRadius: BorderRadius.circular(Rad.pill),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: Sp.xl),
                  VtButton(
                    label: _currentPage == _getPages(context).length - 1
                        ? 'Get Started'
                        : 'Continue',
                    onPressed: _next,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 32,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Icon(icon, size: 52, color: color),
    );
  }
}
