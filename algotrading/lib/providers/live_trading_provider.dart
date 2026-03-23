import 'dart:async';
import 'package:flutter/material.dart';
import '../models/live_trading_model.dart';
import '../services/api_service.dart';

class LiveTradingProvider with ChangeNotifier {
  AgentStatusModel _status = AgentStatusModel.stopped();
  bool _isLoading = false;
  String? _error;
  Timer? _pollTimer;

  // Analysis state
  bool _isAnalyzing = false;
  List<Map<String, dynamic>> _analysisResults = [];
  String? _analyzeError;

  /// Last settings the user started the agent with.
  /// Persists across navigation so sliders restore correctly.
  AgentSettingsModel _lastSettings = AgentSettingsModel.defaults();

  AgentStatusModel get status => _status;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isRunning => _status.isRunning;
  AgentSettingsModel get lastSettings => _lastSettings;

  bool get isAnalyzing => _isAnalyzing;
  List<Map<String, dynamic>> get analysisResults => _analysisResults;
  String? get analyzeError => _analyzeError;

  /// Run intraday analysis — populates analysisResults for the UI to display.
  Future<void> analyzeMarket({
    required String userId,
    required String accessToken,
    required String apiKey,
    int limit = 5,
  }) async {
    _isAnalyzing = true;
    _analyzeError = null;
    _analysisResults = [];
    notifyListeners();

    try {
      final results = await ApiService.analyzeIntraday(
        userId: userId,
        apiKey: apiKey,
        accessToken: accessToken,
        limit: limit,
      );
      _analysisResults = results;
    } catch (e) {
      _analyzeError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  /// Clear previous analysis results.
  void clearAnalysis() {
    _analysisResults = [];
    _analyzeError = null;
    notifyListeners();
  }

  /// Register a manually-executed position with the running monitoring agent.
  Future<bool> registerPosition({
    required String userId,
    required String accessToken,
    required String apiKey,
    required String symbol,
    required String action,
    required int quantity,
    required double entryPrice,
    required double stopLoss,
    required double target,
    String? gttId,
    double atr = 0.0,
  }) async {
    try {
      await ApiService.registerPosition(
        userId: userId,
        apiKey: apiKey,
        accessToken: accessToken,
        symbol: symbol,
        action: action,
        quantity: quantity,
        entryPrice: entryPrice,
        stopLoss: stopLoss,
        target: target,
        gttId: gttId,
        atr: atr,
      );
      // Refresh status to show the new position immediately
      await _fetchStatusSilent(userId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Start the autonomous agent on the backend (monitoring-only mode).
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
  /// Only marks UI as stopped once the backend confirms it stopped.
  /// If the API call fails, keeps the running state and shows an error.
  Future<void> stopAgent(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    bool apiSucceeded = false;
    try {
      await ApiService.stopLiveAgent(userId: userId);
      apiSucceeded = true;
    } catch (e) {
      _error = 'Stop failed: ${e.toString().replaceFirst('Exception: ', '')}';
    }

    if (apiSucceeded) {
      // Poll backend up to 5× (every 2s) to confirm the agent actually stopped.
      for (int i = 0; i < 5; i++) {
        await Future.delayed(const Duration(seconds: 2));
        try {
          final s = await ApiService.getLiveAgentStatus(userId: userId);
          if (!s.isRunning) {
            _status = AgentStatusModel.stopped();
            _lastSettings = _lastSettings; // keep last settings intact
            break;
          }
          if (i == 4) {
            // Backend still running after 10s — show warning but mark stopped
            // so the user can retry if needed.
            _error = 'Agent may still be stopping. Check status in a moment.';
            _status = AgentStatusModel.stopped();
          }
        } catch (_) {
          // Network error during confirmation — assume stopped
          _status = AgentStatusModel.stopped();
          break;
        }
      }
    }

    _stopPolling();
    _isLoading = false;
    notifyListeners();
  }

  /// Update last settings so they survive navigation without starting agent.
  void updateLastSettings(AgentSettingsModel settings) {
    _lastSettings = settings;
  }

  /// Fetch status and update UI — only notifies listeners if meaningful
  /// fields changed to prevent unnecessary screen rebuilds on each poll.
  Future<void> fetchStatus(String userId) async {
    try {
      final data = await ApiService.getLiveAgentStatus(userId: userId);

      final changed = _statusChanged(data);
      _status = data;
      _error = null;

      // Keep lastSettings in sync with whatever the backend says is running,
      // so that after a stop the sliders restore to the last-used values.
      if (data.isRunning && data.settings.maxPositions > 0) {
        _lastSettings = data.settings;
      }

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
