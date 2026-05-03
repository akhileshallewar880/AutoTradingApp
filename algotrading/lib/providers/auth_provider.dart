import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/session_manager.dart';

/// Sentinel token used for demo / guest mode. Never sent to any real API.
const String kDemoAccessToken = 'demo';

class AuthProvider with ChangeNotifier {
  UserModel? _user;
  bool _isLoading = false;
  String? _error;

  // ── Phone auth state ────────────────────────────────────────────────────────
  String? _vtAccessToken;
  String? _phoneNumber;
  bool _phoneVerifying = false;
  String? _phoneVerificationId;
  String? _phoneError;

  String? get vtAccessToken => _vtAccessToken;
  String? get phoneNumber => _phoneNumber;
  bool get isPhoneVerifying => _phoneVerifying;
  String? get phoneError => _phoneError;
  bool get isPhoneVerified => _vtAccessToken != null && _vtAccessToken!.isNotEmpty;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;

  /// True when the user is exploring the app with dummy data (no Zerodha login).
  bool get isDemoMode => _user?.accessToken == kDemoAccessToken;

  Future<void> checkSession() async {
    _isLoading = true;
    notifyListeners();
    // Restore VT / phone session regardless of Zerodha session state
    _vtAccessToken = await SessionManager.getVtAccessToken();
    _phoneNumber = await SessionManager.getPhoneNumber();

    try {
      final userData = await SessionManager.getUserData();
      if (userData != null) {
        // If api_key is missing from saved session (e.g. old session before fix),
        // supplement it from the separately stored zerodha_api_key credential.
        if (userData.apiKey.isEmpty) {
          final creds = await getSavedApiCredentials();
          if (creds != null && creds['apiKey']!.isNotEmpty) {
            final patched = UserModel(
              accessToken: userData.accessToken,
              apiKey: creds['apiKey']!,
              userId: userData.userId,
              userName: userData.userName,
              email: userData.email,
              userType: userData.userType,
              broker: userData.broker,
              exchanges: userData.exchanges,
              products: userData.products,
            );
            _user = patched;
            await SessionManager.saveSession(patched); // persist the fix
          } else {
            _user = userData;
          }
        } else {
          _user = userData;
        }
        _error = null;
      }
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<String> getLoginUrl() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Get user's saved API credentials
      final creds = await getSavedApiCredentials();
      if (creds == null) {
        throw Exception('API credentials not found. Please set them up first.');
      }

      final url = await ApiService.getLoginUrl(apiKey: creds['apiKey']!);
      _isLoading = false;
      notifyListeners();
      return url;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> createSession(String requestToken) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Get user's saved API credentials
      final creds = await getSavedApiCredentials();
      if (creds == null) {
        throw Exception('API credentials not found. Please set them up first.');
      }

      final user = await ApiService.createSession(
        requestToken,
        apiKey: creds['apiKey']!,
        apiSecret: creds['apiSecret']!,
      );
      _user = user;
      await SessionManager.saveSession(user);
      _error = null;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Signs in with pre-built dummy data — no Zerodha account required.
  Future<void> loginWithDemoData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // Brief delay so the loading indicator is visible
    await Future.delayed(const Duration(milliseconds: 600));

    _user = UserModel(
      accessToken: kDemoAccessToken,
      apiKey: 'demo',
      userId: 'demo_user_001',
      userName: 'Demo User',
      email: 'demo@vantrade.app',
      userType: 'individual',
      broker: 'Demo',
      exchanges: ['NSE', 'BSE'],
      products: ['MIS', 'CNC'],
    );

    // Persist so the demo session survives app restarts
    await SessionManager.saveSession(_user!);

    _isLoading = false;
    notifyListeners();
  }

  Future<void> logout() async {
    // Skip API call for demo mode — there is no real session to invalidate
    if (!isDemoMode) {
      try {
        if (_user != null) {
          await ApiService.logout(_user!.accessToken);
        }
      } catch (_) {
        // Ignore logout errors
      }
    }

    await SessionManager.clearSession();
    // Note: Do NOT clear API credentials on logout.
    _user = null;
    _error = null;
    _vtAccessToken = null;
    _phoneNumber = null;
    notifyListeners();
  }

  // ── Phone Authentication ───────────────────────────────────────────────────

  void clearPhoneError() {
    _phoneError = null;
    notifyListeners();
  }

  Future<void> startPhoneVerification({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onError,
  }) async {
    _phoneVerifying = true;
    _phoneError = null;
    notifyListeners();

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: '+91$phoneNumber',
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Android auto-retrieval — complete without OTP input
          await _completePhoneAuth(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          _phoneError = e.message ?? 'Verification failed. Check the number and try again.';
          _phoneVerifying = false;
          notifyListeners();
          onError(_phoneError!);
        },
        codeSent: (String verificationId, int? resendToken) {
          _phoneVerificationId = verificationId;
          _phoneVerifying = false;
          notifyListeners();
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (e) {
      _phoneError = 'Could not send OTP. Check your connection and try again.';
      _phoneVerifying = false;
      notifyListeners();
      onError(_phoneError!);
    }
  }

  Future<void> verifyOtp({
    required String smsCode,
    required void Function() onSuccess,
    required void Function(String error) onError,
  }) async {
    if (_phoneVerificationId == null) {
      onError('Verification session expired. Please request a new OTP.');
      return;
    }
    _phoneVerifying = true;
    _phoneError = null;
    notifyListeners();

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _phoneVerificationId!,
        smsCode: smsCode,
      );
      await _completePhoneAuth(credential);
      onSuccess();
    } on FirebaseAuthException catch (e) {
      _phoneError = e.message ?? 'Invalid OTP. Please try again.';
      _phoneVerifying = false;
      notifyListeners();
      onError(_phoneError!);
    } catch (e) {
      _phoneError = e.toString().replaceFirst('Exception: ', '');
      _phoneVerifying = false;
      notifyListeners();
      onError(_phoneError!);
    }
  }

  Future<void> _completePhoneAuth(PhoneAuthCredential credential) async {
    final userCredential =
        await FirebaseAuth.instance.signInWithCredential(credential);
    final idToken = await userCredential.user!.getIdToken();

    final response = await ApiService.verifyFirebaseToken(idToken!);
    _vtAccessToken = response['vt_access_token'] as String;
    _phoneNumber = response['phone_number'] as String;

    await SessionManager.saveVtSession(
      vtAccessToken: _vtAccessToken!,
      phoneNumber: _phoneNumber!,
    );
    _phoneVerifying = false;
    notifyListeners();
  }

  /// Retrieve saved API credentials from secure local storage
  Future<Map<String, String>?> getSavedApiCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = prefs.getString('zerodha_api_key');
      final apiSecret = prefs.getString('zerodha_api_secret');

      if (apiKey != null && apiSecret != null) {
        return {
          'apiKey': apiKey,
          'apiSecret': apiSecret,
        };
      }
      return null;
    } catch (e) {
      _error = 'Failed to load API credentials: $e';
      notifyListeners();
      return null;
    }
  }

  /// Validate that the currently stored Zerodha access token is still alive.
  /// Returns false if the session has expired (caller should logout + redirect to login).
  /// Returns true if valid OR if the check is inconclusive (network error).
  Future<bool> validateSession() async {
    if (_user == null || isDemoMode) return true; // nothing to validate
    try {
      return await ApiService.validateToken(
        accessToken: _user!.accessToken,
        apiKey: _user!.apiKey,
      );
    } catch (_) {
      return true; // network error — let the home screen handle it
    }
  }

  /// Validate API credentials by making a test Zerodha API call
  /// Returns true if credentials are valid, false otherwise
  Future<bool> validateApiCredentials(String apiKey, String apiSecret) async {
    try {
      // Test call to Zerodha API with provided credentials
      final isValid = await ApiService.validateZerodhaCredentials(apiKey, apiSecret);
      return isValid;
    } catch (e) {
      _error = 'API validation failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Save API credentials securely to local storage
  Future<void> saveApiCredentials(String apiKey, String apiSecret) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('zerodha_api_key', apiKey);
      await prefs.setString('zerodha_api_secret', apiSecret);

      _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to save API credentials: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Clear saved API credentials from local storage
  Future<void> clearApiCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('zerodha_api_key');
      await prefs.remove('zerodha_api_secret');
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to clear API credentials: $e';
      notifyListeners();
    }
  }

  /// Reset credentials and navigate back to API settings
  /// Call this when user wants to use different credentials (e.g., from settings)
  Future<void> resetCredentialsForNewSetup() async {
    await clearApiCredentials();
    // User will need to navigate to /api-settings manually or via deep link
  }
}
