import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the currently-active options monitoring session to
/// SharedPreferences so the user can navigate back to it after closing
/// and reopening the app.
///
/// Only one active trade is tracked at a time.
class ActiveTradeStore {
  static const _key = 'active_options_trade';

  /// Save session details when monitoring begins.
  static Future<void> save({
    required String analysisId,
    required String symbol,
    required String optionType,
    required double entryFillPrice,
    required double slTrigger,
    required double targetPrice,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'analysis_id':     analysisId,
        'symbol':          symbol,
        'option_type':     optionType,
        'entry_fill_price': entryFillPrice,
        'sl_trigger':      slTrigger,
        'target_price':    targetPrice,
        'saved_at':        DateTime.now().toIso8601String(),
      }),
    );
  }

  /// Load the persisted session. Returns null if nothing is saved.
  static Future<ActiveTrade?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return ActiveTrade.fromMap(map);
    } catch (_) {
      await clear();
      return null;
    }
  }

  /// Remove the persisted session (call when monitoring ends).
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

class ActiveTrade {
  final String analysisId;
  final String symbol;
  final String optionType;
  final double entryFillPrice;
  final double slTrigger;
  final double targetPrice;
  final DateTime savedAt;

  const ActiveTrade({
    required this.analysisId,
    required this.symbol,
    required this.optionType,
    required this.entryFillPrice,
    required this.slTrigger,
    required this.targetPrice,
    required this.savedAt,
  });

  factory ActiveTrade.fromMap(Map<String, dynamic> m) => ActiveTrade(
        analysisId:     m['analysis_id'] as String,
        symbol:         m['symbol'] as String,
        optionType:     m['option_type'] as String,
        entryFillPrice: (m['entry_fill_price'] as num).toDouble(),
        slTrigger:      (m['sl_trigger'] as num).toDouble(),
        targetPrice:    (m['target_price'] as num).toDouble(),
        savedAt:        DateTime.tryParse(m['saved_at'] as String? ?? '') ?? DateTime.now(),
      );
}
