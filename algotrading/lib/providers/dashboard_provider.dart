import 'dart:async';
import 'package:flutter/material.dart';
import '../models/dashboard_model.dart';
import '../services/api_service.dart';

class DashboardProvider with ChangeNotifier {
  DashboardModel? _dashboard;
  bool _isLoading = false;
  String? _error;
  Timer? _refreshTimer;

  DashboardModel? get dashboard => _dashboard;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Fetch dashboard data. Call this when the home screen mounts.
  Future<void> fetchDashboard(String accessToken) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _dashboard = await ApiService.getDashboard(accessToken);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Start auto-refresh every [intervalSeconds] seconds.
  void startAutoRefresh(String accessToken, {int intervalSeconds = 30}) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => fetchDashboard(accessToken),
    );
  }

  /// Stop auto-refresh (call in dispose).
  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  void dispose() {
    stopAutoRefresh();
    super.dispose();
  }
}
