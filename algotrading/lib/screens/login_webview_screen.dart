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
    
    try {
      await authProvider.createSession(requestToken);
      
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/home',
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: $e')),
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
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
