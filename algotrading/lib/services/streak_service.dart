import 'package:shared_preferences/shared_preferences.dart';

class StreakResult {
  final int streakDays;
  final bool isNewDay;

  const StreakResult({required this.streakDays, required this.isNewDay});
}

/// Tracks daily login streaks in SharedPreferences.
/// Call [checkAndUpdate] once per session after login completes.
class StreakService {
  static const _keyLastLogin = 'streak_last_login';
  static const _keyCount     = 'streak_count';

  static StreakService? _instance;
  static StreakService get instance => _instance ??= StreakService._();
  StreakService._();

  Future<StreakResult> checkAndUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final lastStr = prefs.getString(_keyLastLogin);
    final count   = prefs.getInt(_keyCount) ?? 0;

    if (lastStr == null) {
      await _save(prefs, today, 1);
      return const StreakResult(streakDays: 1, isNewDay: true);
    }

    final last = DateTime.parse(lastStr);
    final diff = today.difference(last).inDays;

    if (diff == 0) {
      return StreakResult(streakDays: count, isNewDay: false);
    }

    final newCount = diff == 1 ? count + 1 : 1;
    await _save(prefs, today, newCount);
    return StreakResult(streakDays: newCount, isNewDay: true);
  }

  Future<int> currentStreak() async {
    final prefs = await SharedPreferences.getInstance();
    final lastStr = prefs.getString(_keyLastLogin);
    if (lastStr == null) return 0;

    final now  = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last  = DateTime.parse(lastStr);
    final diff  = today.difference(last).inDays;

    if (diff > 1) return 0;
    return prefs.getInt(_keyCount) ?? 0;
  }

  Future<void> _save(SharedPreferences prefs, DateTime date, int count) async {
    await prefs.setString(_keyLastLogin, date.toIso8601String());
    await prefs.setInt(_keyCount, count);
  }
}
