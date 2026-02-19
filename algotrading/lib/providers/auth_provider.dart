import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/session_manager.dart';

class AuthProvider with ChangeNotifier {
  UserModel? _user;
  bool _isLoading = false;
  String? _error;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;

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
      throw e;
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
      throw e;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      if (_user != null) {
        await ApiService.logout(_user!.accessToken);
      }
    } catch (e) {
      // Ignore logout errors
    }

    await SessionManager.clearSession();
    _user = null;
    _error = null;
    notifyListeners();
  }
}
