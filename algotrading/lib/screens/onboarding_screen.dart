import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/info_card.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  Future<void> _markOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 24.0,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 16),

                    // ── Logo ──────────────────────────────────────────────────
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(
                        Icons.trending_up,
                        size: 56,
                        color: Colors.green[700],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Title ─────────────────────────────────────────────────
                    const Text(
                      'Welcome to VanTrade',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 8),

                    // ── Subtitle ──────────────────────────────────────────────
                    Text(
                      'AI-Powered Stock Analysis & Automated Trading',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 32),

                    // ── Features ──────────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFeature(
                            icon: Icons.auto_awesome,
                            title: 'AI-Powered Analysis',
                            description:
                                'Get smart stock recommendations using advanced AI',
                          ),
                          const SizedBox(height: 16),
                          _buildFeature(
                            icon: Icons.bar_chart,
                            title: 'Real-Time Technical Indicators',
                            description: 'VWAP, RSI, MACD, Bollinger Bands & more',
                          ),
                          const SizedBox(height: 16),
                          _buildFeature(
                            icon: Icons.bolt,
                            title: 'Automated Trade Execution',
                            description: 'Execute trades directly via Zerodha',
                          ),
                          const SizedBox(height: 16),
                          _buildFeature(
                            icon: Icons.schedule,
                            title: 'Intraday & Swing Trading',
                            description:
                                'Support for both short-term and medium-term strategies',
                          ),
                          const SizedBox(height: 16),
                          _buildFeature(
                            icon: Icons.shield,
                            title: 'Risk Management',
                            description:
                                'Smart stop-loss and target placement with GTT orders',
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Info Box ──────────────────────────────────────────────
                    InfoCard(
                      type: InfoCardType.info,
                      title: '🔐 Secure Setup Ahead',
                      message:
                          'You\'ll set up your Zerodha API credentials on the next screen. Your credentials are encrypted and stored locally on your device only.',
                    ),
                  ],
                ),
              ),
            ),

            // Fixed bottom buttons
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Get Started Button ────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        _markOnboardingComplete();
                        Navigator.pushReplacementNamed(context, '/api-settings');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Get Started',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Skip Button ───────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        _markOnboardingComplete();
                        Navigator.pushReplacementNamed(context, '/api-settings');
                      },
                      child: Text(
                        'Skip to Setup',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeature({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.green[700], size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
