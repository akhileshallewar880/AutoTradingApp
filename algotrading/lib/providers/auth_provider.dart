import 'package:flutter/material.dart';
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
      final url = await ApiService.getLoginUrl();
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
      final user = await ApiService.createSession(requestToken);
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
    _user = null;
    _error = null;
    notifyListeners();
  }
}
