import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

// Sensitive keys → encrypted platform keystore (Android Keystore / iOS Keychain)
// Non-sensitive keys → SharedPreferences (OK for non-secret UI state)
class SessionManager {
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ── Key names ────────────────────────────────────────────────────────────────
  static const _kAccessToken   = 'access_token';    // Zerodha access token  [SECURE]
  static const _kUserData      = 'user_data';       // Serialised UserModel   [SECURE]
  static const _kVtAccessToken = 'vt_access_token'; // VanTrade JWT           [SECURE]
  static const _kVtUserId      = 'vt_user_id';      // VT user UUID           [SECURE]
  static const _kPhoneNumber   = 'phone_number';    // E.164 phone            [PREFS]

  // ── Zerodha session ──────────────────────────────────────────────────────────

  static Future<void> saveSession(UserModel user) async {
    await Future.wait([
      _secure.write(key: _kAccessToken, value: user.accessToken),
      _secure.write(key: _kUserData,    value: jsonEncode(user.toJson())),
    ]);
  }

  static Future<String?> getAccessToken() =>
      _secure.read(key: _kAccessToken);

  static Future<UserModel?> getUserData() async {
    final raw = await _secure.read(key: _kUserData);
    if (raw == null) return null;
    try {
      return UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> clearSession() async {
    await Future.wait([
      _secure.delete(key: _kAccessToken),
      _secure.delete(key: _kUserData),
      _secure.delete(key: _kVtAccessToken),
      _secure.delete(key: _kVtUserId),
    ]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPhoneNumber);
  }

  static Future<void> clearZerodhaSession() async {
    await Future.wait([
      _secure.delete(key: _kAccessToken),
      _secure.delete(key: _kUserData),
    ]);
  }

  // ── Phone / VT session ───────────────────────────────────────────────────────

  static Future<void> saveVtSession({
    required String vtAccessToken,
    required String phoneNumber,
    String? vtUserId,
  }) async {
    await Future.wait([
      _secure.write(key: _kVtAccessToken, value: vtAccessToken),
      if (vtUserId != null) _secure.write(key: _kVtUserId, value: vtUserId),
    ]);
    // Phone number is not a secret — plain prefs is fine
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPhoneNumber, phoneNumber);
  }

  static Future<String?> getVtAccessToken() =>
      _secure.read(key: _kVtAccessToken);

  static Future<String?> getVtUserId() =>
      _secure.read(key: _kVtUserId);

  static Future<String?> getPhoneNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPhoneNumber);
  }

  static Future<bool> isPhoneVerified() async {
    final token = await getVtAccessToken();
    return token != null && token.isNotEmpty;
  }
}
