import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/vantrade_logo.dart';
import 'login_webview_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              // ── Scrollable content (logo, features, error) ──────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const VanTradeLogoWidget(size: 100),
                      const SizedBox(height: 24),
                      const Text(
                        'VanTrade',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Intelligent stock analysis powered by AI',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 48),
                      _buildFeatureItem(
                        icon: Icons.analytics,
                        title: 'AI Analysis',
                        description: 'Get AI-powered stock recommendations',
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureItem(
                        icon: Icons.auto_graph,
                        title: 'Automated Trading',
                        description: 'Automatic order placement and GTT',
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureItem(
                        icon: Icons.track_changes,
                        title: 'Real-time Tracking',
                        description: 'Monitor execution in real-time',
                      ),
                      const SizedBox(height: 32),
                      if (context.watch<AuthProvider>().error != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            border: Border.all(color: Colors.red[300]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            context.watch<AuthProvider>().error!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── Fixed buttons at bottom (always visible) ────────────────────
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Consumer<AuthProvider>(
                  builder: (context, authProvider, child) {
                    if (authProvider.isLoading) {
                      return const SizedBox(
                        height: 48,
                        child: CircularProgressIndicator(),
                      );
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Primary: Zerodha login ──────────────────────
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: () =>
                                _handleLogin(context, authProvider),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[700],
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Login with Zerodha',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // ── Secondary: Demo mode ────────────────────────
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _handleDemoLogin(context, authProvider),
                            icon: Icon(
                              Icons.science_outlined,
                              color: Colors.green[700],
                              size: 20,
                            ),
                            label: const Text(
                              'Test with Dummy Data',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.green[700],
                              side: BorderSide(
                                color: Colors.green[700]!,
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),
                        Text(
                          'No Zerodha account needed • Sample data only',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ), // Scaffold
    ); // PopScope
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.green[700], size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                description,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleDemoLogin(
    BuildContext context,
    AuthProvider authProvider,
  ) async {
    await authProvider.loginWithDemoData();
    if (context.mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  Future<void> _handleLogin(
    BuildContext context,
    AuthProvider authProvider,
  ) async {
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Login failed: $e')));
      }
    }
  }
}
