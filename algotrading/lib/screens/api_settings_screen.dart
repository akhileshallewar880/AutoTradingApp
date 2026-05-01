import '../theme/vt_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/vt_button.dart';

class ApiSettingsScreen extends StatefulWidget {
  const ApiSettingsScreen({super.key});

  @override
  State<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends State<ApiSettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _apiKeyController;
  late final TextEditingController _apiSecretController;
  late final TabController _tabController;
  bool _showPassword = false;
  bool _isValidating = false;
  bool _keyFilled = false;
  bool _secretFilled = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _apiKeyController = TextEditingController();
    _apiSecretController = TextEditingController();
    _apiKeyController.addListener(
        () => setState(() => _keyFilled = _apiKeyController.text.isNotEmpty));
    _apiSecretController.addListener(
        () => setState(() => _secretFilled = _apiSecretController.text.isNotEmpty));
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final saved =
        await context.read<AuthProvider>().getSavedApiCredentials();
    if (saved != null && mounted) {
      setState(() {
        _apiKeyController.text = saved['apiKey'] ?? '';
        _apiSecretController.text = saved['apiSecret'] ?? '';
        _keyFilled = _apiKeyController.text.isNotEmpty;
        _secretFilled = _apiSecretController.text.isNotEmpty;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    super.dispose();
  }

  Future<void> _validateAndSaveCredentials() async {
    final apiKey = _apiKeyController.text.trim();
    final apiSecret = _apiSecretController.text.trim();

    if (apiKey.isEmpty || apiSecret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter both API key and secret')),
      );
      return;
    }
    if (apiKey.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('API key looks too short. Please check and try again.'),
        ),
      );
      return;
    }

    setState(() => _isValidating = true);
    try {
      await context.read<AuthProvider>().saveApiCredentials(apiKey, apiSecret);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error saving credentials: $e'),
              backgroundColor: context.vt.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isValidating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bothFilled = _keyFilled && _secretFilled;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text('Configure API', style: AppTextStyles.h2),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Your Credentials'),
              Tab(text: 'Setup Guide'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildCredentialsTab(bothFilled),
            _buildGuideTab(),
          ],
        ),
      ),
    );
  }

  // ── Tab 1: Credentials ────────────────────────────────────────────────────
  Widget _buildCredentialsTab(bool bothFilled) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(Sp.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Security badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Sp.md, vertical: Sp.sm),
                  decoration: BoxDecoration(
                    color: context.vt.accentGreenDim,
                    borderRadius: BorderRadius.circular(Rad.md),
                    border: Border.all(
                        color: context.vt.accentGreen.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline,
                          size: 16, color: context.vt.accentGreen),
                      SizedBox(width: Sp.sm),
                      Text(
                        'End-to-end encrypted · Stored locally on your device only',
                        style: AppTextStyles.caption.copyWith(
                            color: context.vt.accentGreen),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: Sp.xl),

                // API Key
                Text('API Key', style: AppTextStyles.bodyLarge),
                SizedBox(height: Sp.sm),
                TextField(
                  controller: _apiKeyController,
                  style: AppTextStyles.mono.copyWith(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Enter your Zerodha API key',
                    prefixIcon: Icon(Icons.vpn_key_outlined,
                        color: context.vt.accentGreen, size: 18),
                    suffixIcon: _keyFilled
                        ? Icon(Icons.check_circle_outline,
                            color: context.vt.accentGreen, size: 18)
                        : null,
                  ),
                ),

                SizedBox(height: Sp.xl),

                // API Secret
                Text('API Secret', style: AppTextStyles.bodyLarge),
                SizedBox(height: Sp.sm),
                TextField(
                  controller: _apiSecretController,
                  obscureText: !_showPassword,
                  style: AppTextStyles.mono.copyWith(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Enter your Zerodha API secret',
                    prefixIcon: Icon(Icons.lock_outline,
                        color: context.vt.accentGreen, size: 18),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_secretFilled)
                          Icon(Icons.check_circle_outline,
                              color: context.vt.accentGreen, size: 18),
                        IconButton(
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: context.vt.textTertiary,
                            size: 18,
                          ),
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: Sp.base),

                // Guide hint
                GestureDetector(
                  onTap: () => _tabController.animateTo(1),
                  child: Text(
                    'Where do I find these? →',
                    style: AppTextStyles.caption.copyWith(
                        color: context.vt.accentGreen,
                        fontWeight: FontWeight.w600),
                  ),
                ),

                const SizedBox(height: Sp.xxl),
              ],
            ),
          ),
        ),

        // Fixed bottom CTA
        Container(
          padding: EdgeInsets.fromLTRB(Sp.xl, Sp.base, Sp.xl, Sp.xxl),
          decoration: BoxDecoration(
            color: context.vt.surface1,
            border: Border(top: BorderSide(color: context.vt.divider)),
          ),
          child: VtButton(
            label: 'Save & Continue',
            onPressed: bothFilled ? _validateAndSaveCredentials : null,
            loading: _isValidating,
          ),
        ),
      ],
    );
  }

  // ── Tab 2: Setup Guide ────────────────────────────────────────────────────
  Widget _buildGuideTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Sp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Get your API credentials from Zerodha:',
              style: AppTextStyles.bodySecondary),
          const SizedBox(height: Sp.xl),

          _GuideStep(
            number: '1',
            title: 'Open Zerodha Developer Console',
            child: GestureDetector(
              onTap: () => _launchUrl('https://kite.trade'),
              child: Text(
                'https://kite.trade',
                style: AppTextStyles.monoSm.copyWith(
                    color: const Color(0xFF60A5FA),
                    decoration: TextDecoration.underline),
              ),
            ),
          ),
          const SizedBox(height: Sp.base),

          const _GuideStep(
            number: '2',
            title: 'Sign in with your Zerodha account',
            child: Text(''),
          ),
          const SizedBox(height: Sp.base),

          const _GuideStep(
            number: '3',
            title: 'Click "Create a new app"',
            child: Text(''),
          ),
          const SizedBox(height: Sp.base),

          _GuideStep(
            number: '4',
            title: 'Fill in the app form',
            child: _AppFormBox(onCopy: () {
              Clipboard.setData(const ClipboardData(
                  text: 'https://api.vantrade.in/api/v1/auth/callback'));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Redirect URL copied!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            }),
          ),
          SizedBox(height: Sp.base),

          const _GuideStep(
            number: '5',
            title: 'Copy API Key & API Secret',
            child: Text(''),
          ),

          SizedBox(height: Sp.xl),

          // Warning
          Container(
            padding: EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              color: context.vt.dangerDim,
              borderRadius: BorderRadius.circular(Rad.md),
              border:
                  Border.all(color: context.vt.danger.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: context.vt.danger, size: 18),
                SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(
                    'Never share your API Secret with anyone.',
                    style: AppTextStyles.caption
                        .copyWith(color: context.vt.danger, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: Sp.xl),

          VtButton(
            label: 'Enter Credentials',
            onPressed: () => _tabController.animateTo(0),
            variant: VtButtonVariant.secondary,
          ),
          const SizedBox(height: Sp.xxl),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ── Guide step widget ─────────────────────────────────────────────────────────
class _GuideStep extends StatelessWidget {
  const _GuideStep(
      {required this.number, required this.title, required this.child});
  final String number;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: context.vt.accentGreen,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(number,
                style: AppTextStyles.label.copyWith(
                    color: Colors.white, letterSpacing: 0)),
          ),
        ),
        const SizedBox(width: Sp.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(title, style: AppTextStyles.bodyLarge),
              if (child is! Text || (child as Text).data!.isNotEmpty) ...[
                const SizedBox(height: 4),
                child,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── App form reference box ────────────────────────────────────────────────────
class _AppFormBox extends StatelessWidget {
  const _AppFormBox({required this.onCopy});
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: Sp.sm),
      padding: EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: context.vt.surface2,
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: context.vt.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(context, 'App Name', 'VanTrade'),
          const SizedBox(height: Sp.sm),
          _field(context, 'Type', 'Personal (Free)'),
          SizedBox(height: Sp.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Redirect URL',
                        style: AppTextStyles.label.copyWith(fontSize: 10)),
                    SizedBox(height: 2),
                    Text(
                      'https://api.vantrade.in/api/v1/auth/callback',
                      style: AppTextStyles.monoSm.copyWith(
                          color: context.vt.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onCopy,
                child: Container(
                  padding: EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: context.vt.accentGreenDim,
                    borderRadius: BorderRadius.circular(Rad.sm),
                  ),
                  child: Icon(Icons.copy_outlined,
                      size: 14, color: context.vt.accentGreen),
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          _field(context, 'Description', 'For automated trading'),
        ],
      ),
    );
  }

  Widget _field(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTextStyles.label.copyWith(fontSize: 10)),
        SizedBox(height: 2),
        Text(value,
            style:
                AppTextStyles.monoSm.copyWith(color: context.vt.textSecondary, fontSize: 12)),
      ],
    );
  }
}
