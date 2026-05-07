import 'package:shared_preferences/shared_preferences.dart';

class TourService {
  static const _prefix = 'vt_tour_seen_';

  static Future<bool> hasSeenTour(String screenId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$screenId') ?? false;
  }

  static Future<void> markTourSeen(String screenId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$screenId', true);
  }

  // Call from Settings to replay all tours
  static Future<void> resetAllTours() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
