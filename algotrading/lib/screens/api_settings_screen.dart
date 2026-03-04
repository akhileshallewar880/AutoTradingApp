import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';

class ApiSettingsScreen extends StatefulWidget {
  const ApiSettingsScreen({super.key});

  @override
  State<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends State<ApiSettingsScreen> {
  late TextEditingController _apiKeyController;
  late TextEditingController _apiSecretController;
  bool _showPassword = false;
  bool _isValidating = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _apiSecretController = TextEditingController();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final authProvider = context.read<AuthProvider>();
    final saved = await authProvider.getSavedApiCredentials();
    if (saved != null) {
      setState(() {
        _apiKeyController.text = saved['apiKey'] ?? '';
        _apiSecretController.text = saved['apiSecret'] ?? '';
      });
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    super.dispose();
  }

  Future<void> _validateAndSaveCredentials() async {
    final apiKey = _apiKeyController.text.trim();
    final apiSecret = _apiSecretController.text.trim();

    if (apiKey.isEmpty || apiSecret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both API key and secret')),
      );
      return;
    }

    setState(() => _isValidating = true);

    try {
      final authProvider = context.read<AuthProvider>();

      // Validate credentials by making a test API call
      final isValid = await authProvider.validateApiCredentials(
        apiKey,
        apiSecret,
      );

      if (!mounted) return;

      if (isValid) {
        // Save credentials securely
        await authProvider.saveApiCredentials(apiKey, apiSecret);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ API credentials saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate to login screen
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '❌ Invalid API credentials. Please check and try again.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isValidating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: null,
          automaticallyImplyLeading: false,
          title: const Text(
            'Configure API',
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header Section ────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🔐 Secure API Setup',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Use your personal Zerodha API credentials for maximum security. Your credentials are encrypted and stored locally on your device only.',
                        style: TextStyle(fontSize: 14, color: Colors.blue[700]),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // ── API Key Field ────────────────────────────────────────────
                const Text(
                  'API Key',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _apiKeyController,
                  decoration: InputDecoration(
                    hintText: 'Enter your Zerodha API key',
                    prefixIcon: const Icon(Icons.vpn_key, color: Colors.green),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.green[700]!,
                        width: 2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── API Secret Field ──────────────────────────────────────────
                const Text(
                  'API Secret',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _apiSecretController,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    hintText: 'Enter your Zerodha API secret',
                    prefixIcon: const Icon(Icons.lock, color: Colors.green),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPassword ? Icons.visibility : Icons.visibility_off,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        setState(() => _showPassword = !_showPassword);
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.green[700]!,
                        width: 2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Help Section ──────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '📚 Step-by-step Guide',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _launchUrl('https://kite.trade/docs'),
                            child: Text(
                              '▶ Watch Tutorial',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[600],
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Step 1
                      _buildDetailedStep(
                        '1',
                        'Open Zerodha Developer Console',
                        'https://kite.trade',
                        isLink: true,
                      ),
                      const SizedBox(height: 12),
                      // Step 2
                      _buildDetailedStep(
                        '2',
                        'Sign up or Log in with your Zerodha account',
                        'If you don\'t have a Zerodha account, create one free at zerodha.com',
                      ),
                      const SizedBox(height: 12),
                      // Step 3
                      _buildDetailedStep(
                        '3',
                        'Click "Create a new app"',
                        'You\'ll see a form to set up your trading app',
                      ),
                      const SizedBox(height: 12),
                      // Step 4 - Create New App
                      _buildDetailedStep(
                        '4',
                        'Fill in the app details',
                        'See details below ↓',
                      ),
                      const SizedBox(height: 12),
                      // App Details Box
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber[100]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'App Creation Form:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildAppDetailField('App Name:', 'VanTrade'),
                            const SizedBox(height: 6),
                            _buildAppDetailField('Type:', 'Personal (Free)'),
                            const SizedBox(height: 6),
                            _buildAppDetailField(
                              'Redirect URL:',
                              'https://vantradeapp-h6axgng8hkd9aqba.centralindia-01.azurewebsites.net/api',
                              isCopyable: true,
                            ),
                            const SizedBox(height: 6),
                            _buildAppDetailField(
                              'Your Client ID:',
                              '(Enter your Zerodha Client ID)',
                            ),
                            const SizedBox(height: 6),
                            _buildAppDetailField(
                              'Description:',
                              'For automate trade',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Step 5
                      _buildDetailedStep(
                        '5',
                        'Copy your API Key & API Secret',
                        'You\'ll see them after app creation. Keep them private!',
                      ),
                      const SizedBox(height: 12),
                      // Warning Box
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.red[600],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Never share your API Secret with anyone',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // ── Save Button ───────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isValidating
                        ? null
                        : _validateAndSaveCredentials,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isValidating
                        ? SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                Colors.green[700],
                              ),
                            ),
                          )
                        : const Text(
                            'Validate & Save Credentials',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ), // Scaffold
    ); // PopScope
  }

  Future<void> _launchUrl(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open link. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening link: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildDetailedStep(
    String number,
    String title,
    String description, {
    bool isLink = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.amber[600],
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              if (isLink)
                GestureDetector(
                  onTap: () => _launchUrl(description),
                  child: Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[600],
                      decoration: TextDecoration.underline,
                    ),
                  ),
                )
              else
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAppDetailField(
    String label,
    String value, {
    bool isCopyable = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        Expanded(
          child: isCopyable
              ? GestureDetector(
                  onTap: () {
                    // Copy to clipboard
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Redirect URL copied to clipboard!',
                        ),
                        backgroundColor: Colors.green[600],
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            value,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue[600],
                              fontFamily: 'monospace',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.copy, size: 14, color: Colors.blue[600]),
                      ],
                    ),
                  ),
                )
              : Text(
                  value,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[700],
                    fontFamily: 'monospace',
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildHelpStep(String title, String description) {
    final isUrl =
        description.startsWith('http://') || description.startsWith('https://');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '→ ',
          style: TextStyle(
            color: Colors.amber[700],
            fontWeight: FontWeight.bold,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              if (isUrl)
                GestureDetector(
                  onTap: () => _launchUrl(description),
                  child: Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[600],
                      decoration: TextDecoration.underline,
                    ),
                  ),
                )
              else
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
