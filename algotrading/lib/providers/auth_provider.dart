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

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;

  /// True when the user is exploring the app with dummy data (no Zerodha login).
  bool get isDemoMode => _user?.accessToken == kDemoAccessToken;

  Future<void> checkSession() async {
    _isLoading = true;
    notifyListeners();

    try {
      final userData = await SessionManager.getUserData();
      if (userData != null) {
        _user = userData;
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
    await clearApiCredentials();
    _user = null;
    _error = null;
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
    } catch (e) {
      _error = 'Failed to clear API credentials: $e';
      notifyListeners();
    }
  }
}
