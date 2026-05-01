import '../theme/vt_color_scheme.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

class LoginWebViewScreen extends StatefulWidget {
  final String loginUrl;

  LoginWebViewScreen({super.key, required this.loginUrl});

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
    _setupWebView();
  }

  void _setupWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          // Layer 1: intercept JS / link navigations before they load
          onNavigationRequest: (NavigationRequest request) {
            if (_tryExtractToken(request.url)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          // Layer 2: server-side 302 redirects — fires before page loads
          onPageStarted: (String url) {
            _tryExtractToken(url);
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
          },
          // Layer 3: extract token from the URL even when loading fails
          onWebResourceError: (WebResourceError error) {
            if (error.url != null) _tryExtractToken(error.url!);
          },
          // Android: accept TLS certificate errors for api.vantrade.in
          // (WebView has its own SSL stack, HttpOverrides doesn't apply here)
          onSslAuthError: Platform.isAndroid
              ? (SslAuthError error) {
                  final url =
                      (error.platform as AndroidSslAuthError).url;
                  if (url.contains('vantrade.in')) {
                    error.proceed();
                  } else {
                    error.cancel();
                  }
                }
              : null,
        ),
      )
      ..loadRequest(Uri.parse(widget.loginUrl));
  }

  /// Returns true and starts the session if a request_token is in [url].
  bool _tryExtractToken(String url) {
    if (_sessionCreated) return false;
    try {
      final uri = Uri.parse(url);
      final token = uri.queryParameters['request_token'];
      final status = uri.queryParameters['status'];
      if (token != null && token.isNotEmpty) {
        _sessionCreated = true;
        if (status == null || status == 'success') {
          _handleRequestToken(token);
        } else {
          _showErrorAndPop('Zerodha login was cancelled. Please try again.');
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _handleRequestToken(String requestToken) async {
    final authProvider = context.read<AuthProvider>();
    if (!mounted) return;

    setState(() => _isCreatingSession = true);

    try {
      await authProvider.createSession(requestToken);
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isCreatingSession = false; _sessionCreated = false; });
        final msg = e.toString().contains('Invalid or expired')
            ? 'Request token expired. Please login again.'
            : 'Login failed: ${e.toString().replaceFirst('Exception: ', '')}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: context.vt.danger),
        );
        Navigator.of(context).pop();
      }
    }
  }

  void _showErrorAndPop(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: context.vt.warning),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Zerodha Login', style: AppTextStyles.h2),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: PopScope(
        canPop: !_isCreatingSession,
        child: Stack(
          children: [
            if (!_isCreatingSession)
              WebViewWidget(controller: _controller),

            if (_isLoading && !_isCreatingSession)
              Center(child: CircularProgressIndicator()),

            if (_isCreatingSession)
              Container(
                color: context.vt.overlayScrim,
                child: Center(
                  child: Container(
                    padding: EdgeInsets.all(Sp.xxxl),
                    decoration: BoxDecoration(
                      color: context.vt.surface1,
                      borderRadius: BorderRadius.circular(Rad.lg),
                      border: Border.all(color: context.vt.divider),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 52,
                          height: 52,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: context.vt.accentGreen,
                          ),
                        ),
                        const SizedBox(height: Sp.xl),
                        Text('Completing Login', style: AppTextStyles.h2),
                        const SizedBox(height: Sp.xs),
                        Text(
                          'Setting up your session...',
                          style: AppTextStyles.caption,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
