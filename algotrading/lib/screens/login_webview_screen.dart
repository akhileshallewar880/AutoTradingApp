import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../providers/auth_provider.dart';

class LoginWebViewScreen extends StatefulWidget {
  final String loginUrl;

  const LoginWebViewScreen({super.key, required this.loginUrl});

  @override
  State<LoginWebViewScreen> createState() => _LoginWebViewScreenState();
}

class _LoginWebViewScreenState extends State<LoginWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _sessionCreated = false;
  bool _isCreatingSession = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            _checkForRequestToken(url);
          },
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.loginUrl));
  }

  void _checkForRequestToken(String url) {
    if (_sessionCreated) return;
    final uri = Uri.parse(url);
    final requestToken = uri.queryParameters['request_token'];

    if (requestToken != null) {
      _sessionCreated = true;
      _handleRequestToken(requestToken);
    }
  }

  Future<void> _handleRequestToken(String requestToken) async {
    final authProvider = context.read<AuthProvider>();

    if (!mounted) return;

    // Show full-screen loading overlay
    setState(() => _isCreatingSession = true);

    try {
      await authProvider.createSession(requestToken);

      if (mounted) {
        // After successful Zerodha OAuth login, go to dashboard
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreatingSession = false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zerodha Login'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
      ),
      body: PopScope(
        canPop: !_isCreatingSession,
        child: Stack(
          children: [
            // WebView (hidden when creating session)
            if (!_isCreatingSession)
              WebViewWidget(controller: _controller),

            // Initial loading indicator while webview loads
            if (_isLoading && !_isCreatingSession)
              const Center(child: CircularProgressIndicator()),

            // Full-screen loading overlay during session creation
            if (_isCreatingSession)
              Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 60,
                              height: 60,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Completing Login',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Setting up your session...',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
