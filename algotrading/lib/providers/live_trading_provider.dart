import 'dart:async';
import 'package:flutter/material.dart';
import '../models/live_trading_model.dart';
import '../services/api_service.dart';

class LiveTradingProvider with ChangeNotifier {
  AgentStatusModel _status = AgentStatusModel.stopped();
  bool _isLoading = false;
  String? _error;
  Timer? _pollTimer;

  /// Last settings the user started the agent with.
  /// Persists across navigation so sliders restore correctly.
  AgentSettingsModel _lastSettings = AgentSettingsModel.defaults();

  AgentStatusModel get status => _status;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isRunning => _status.isRunning;
  AgentSettingsModel get lastSettings => _lastSettings;

  /// Start the autonomous agent on the backend.
  /// Saves settings locally, calls API, then immediately fetches status so
  /// the UI transitions to "running" without waiting for the first poll.
  Future<void> startAgent({
    required String userId,
    required String accessToken,
    required String apiKey,
    required AgentSettingsModel settings,
  }) async {
    _isLoading = true;
    _lastSettings = settings; // persist before API call
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
        leverage: settings.leverage,
      );

      // Immediately confirm running state — no 10-second wait
      await _fetchStatusSilent(userId);
      _startPolling(userId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Stop the autonomous agent. Squareoffs positions + cancels GTTs.
  /// Clears all local state immediately so UI resets without waiting for poll.
  Future<void> stopAgent(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.stopLiveAgent(userId: userId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _stopPolling();
      _status = AgentStatusModel.stopped();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch status and update UI — only notifies listeners if meaningful
  /// fields changed to prevent unnecessary screen rebuilds on each poll.
  Future<void> fetchStatus(String userId) async {
    try {
      final data = await ApiService.getLiveAgentStatus(userId: userId);

      final changed = _statusChanged(data);
      _status = data;
      _error = null;

      if (_status.isRunning && _pollTimer == null) {
        _startPolling(userId);
      } else if (!_status.isRunning) {
        _stopPolling();
      }

      if (changed) notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Same as fetchStatus but always notifies — used after start/stop actions
  /// where we need the UI to update regardless of diff.
  Future<void> _fetchStatusSilent(String userId) async {
    try {
      final data = await ApiService.getLiveAgentStatus(userId: userId);
      _status = data;
      _error = null;
    } catch (_) {}
  }

  /// Returns true if anything meaningful changed since last fetch.
  bool _statusChanged(AgentStatusModel next) {
    if (next.isRunning != _status.isRunning) return true;
    if (next.status != _status.status) return true;
    if (next.scanningDone != _status.scanningDone) return true;
    if (next.tradeCountToday != _status.tradeCountToday) return true;
    if (next.openPositions.length != _status.openPositions.length) return true;
    if (next.dailyLossLimitHit != _status.dailyLossLimitHit) return true;
    if (next.tickerConnected != _status.tickerConnected) return true;
    if (next.recentLogs.isNotEmpty &&
        (_status.recentLogs.isEmpty ||
            next.recentLogs.first.timestamp != _status.recentLogs.first.timestamp)) {
      return true;
    }
    // Check if any position P&L changed
    if (next.openPositions.length == _status.openPositions.length) {
      for (int i = 0; i < next.openPositions.length; i++) {
        if (next.openPositions[i].currentPnl != _status.openPositions[i].currentPnl ||
            next.openPositions[i].stopLoss != _status.openPositions[i].stopLoss ||
            next.openPositions[i].target != _status.openPositions[i].target) {
          return true;
        }
      }
    }
    return false;
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
