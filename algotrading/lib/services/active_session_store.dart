import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the live trading session so the foreground service can keep
/// polling the backend even when the app UI is closed.
class ActiveSessionStore {
  static const _key = 'active_trading_session';

  static Future<void> save({
    required String sessionId,
    required String index,
    required String expiryDate,
    required double capital,
    required int lots,
    required String apiKey,
    required String accessToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'session_id':   sessionId,
        'index':        index,
        'expiry_date':  expiryDate,
        'capital':      capital,
        'lots':         lots,
        'api_key':      apiKey,
        'access_token': accessToken,
        'saved_at':     DateTime.now().toIso8601String(),
      }),
    );
  }

  static Future<ActiveSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return ActiveSession.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await clear();
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

class ActiveSession {
  final String sessionId;
  final String index;
  final String expiryDate;
  final double capital;
  final int lots;
  final String apiKey;
  final String accessToken;
  final DateTime savedAt;

  const ActiveSession({
    required this.sessionId,
    required this.index,
    required this.expiryDate,
    required this.capital,
    required this.lots,
    required this.apiKey,
    required this.accessToken,
    required this.savedAt,
  });

  factory ActiveSession.fromMap(Map<String, dynamic> m) => ActiveSession(
        sessionId:   m['session_id']   as String,
        index:       m['index']        as String,
        expiryDate:  m['expiry_date']  as String,
        capital:     (m['capital']     as num).toDouble(),
        lots:        (m['lots']        as num).toInt(),
        apiKey:      m['api_key']      as String,
        accessToken: m['access_token'] as String,
        savedAt:     DateTime.tryParse(m['saved_at'] as String? ?? '') ?? DateTime.now(),
      );
}
