import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import 'dart:convert';

class SessionManager {
  static const String _keyAccessToken = 'access_token';
  static const String _keyUserData = 'user_data';
  static const String _keyVtAccessToken = 'vt_access_token';
  static const String _keyPhoneNumber = 'phone_number';

  static Future<void> saveSession(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccessToken, user.accessToken);
    await prefs.setString(_keyUserData, jsonEncode(user.toJson()));
  }

  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAccessToken);
  }

  static Future<UserModel?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString(_keyUserData);
    if (userDataString != null) {
      return UserModel.fromJson(jsonDecode(userDataString));
    }
    return null;
  }

  static Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyUserData);
    await prefs.remove(_keyVtAccessToken);
    await prefs.remove(_keyPhoneNumber);
  }

  // ── Phone / VT auth ────────────────────────────────────────────────────────

  static Future<void> saveVtSession({
    required String vtAccessToken,
    required String phoneNumber,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVtAccessToken, vtAccessToken);
    await prefs.setString(_keyPhoneNumber, phoneNumber);
  }

  static Future<String?> getVtAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyVtAccessToken);
  }

  static Future<String?> getPhoneNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPhoneNumber);
  }

  static Future<bool> isPhoneVerified() async {
    final token = await getVtAccessToken();
    return token != null && token.isNotEmpty;
  }
}
