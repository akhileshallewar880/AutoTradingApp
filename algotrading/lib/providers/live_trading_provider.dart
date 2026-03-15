import 'dart:async';
import 'package:flutter/material.dart';
import '../models/live_trading_model.dart';
import '../services/api_service.dart';

class LiveTradingProvider with ChangeNotifier {
  AgentStatusModel _status = AgentStatusModel.stopped();
  bool _isLoading = false;
  String? _error;
  Timer? _pollTimer;

  AgentStatusModel get status => _status;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isRunning => _status.isRunning;

  /// Start the autonomous agent on the backend.
  Future<void> startAgent({
    required String userId,
    required String accessToken,
    required String apiKey,
    required AgentSettingsModel settings,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.startLiveAgent(
        userId: userId,
        accessToken: accessToken,
        apiKey: apiKey,
        maxPositions: settings.maxPositions,
        riskPercent: settings.riskPercent,
        scanIntervalMinutes: settings.scanIntervalMinutes,
        maxTradesPerDay: settings.maxTradesPerDay,
        maxDailyLossPct: settings.maxDailyLossPct,
        capitalToUse: settings.capitalToUse,
      );
      // Begin polling for status updates
      _startPolling(userId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Stop the autonomous agent on the backend.
  Future<void> stopAgent(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.stopLiveAgent(userId: userId);
      _stopPolling();
      _status = AgentStatusModel.stopped();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch current agent status (called by polling or manually).
  Future<void> fetchStatus(String userId) async {
    try {
      final data = await ApiService.getLiveAgentStatus(userId: userId);
      _status = data;
      _error = null;
      // Start polling if agent is running but poll timer isn't active
      if (_status.isRunning && _pollTimer == null) {
        _startPolling(userId);
      } else if (!_status.isRunning) {
        _stopPolling();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      notifyListeners();
    }
  }

  void _startPolling(String userId) {
    _stopPolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      fetchStatus(userId);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}
