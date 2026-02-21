import 'dart:async';
import 'package:flutter/material.dart';
import '../models/dashboard_model.dart';
import '../services/api_service.dart';
import 'auth_provider.dart' show kDemoAccessToken;

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
      _dashboard = accessToken == kDemoAccessToken
          ? _buildDemoDashboard()
          : await ApiService.getDashboard(accessToken);
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

  // ── Demo data ──────────────────────────────────────────────────────────────

  DashboardModel _buildDemoDashboard() {
    final now = DateTime.now();
    final fmt = _timeStr;
    return DashboardModel(
      availableBalance: 125000.0,
      todayPnl: 2345.50,
      todayPnlPct: 1.87,
      monthPnl: 18750.0,
      monthTrades: 23,
      monthWinRate: 69.57,
      monthWins: 16,
      monthLosses: 7,
      fetchedAt: now.toIso8601String(),
      orders: [
        OrderModel(
          orderId: 'ORD001',
          symbol: 'RELIANCE',
          transactionType: 'BUY',
          quantity: 10,
          filledQuantity: 10,
          price: 2875.50,
          status: 'COMPLETE',
          statusMessage: 'Order complete',
          orderType: 'MARKET',
          product: 'MIS',
          placedAt: fmt(now.subtract(const Duration(hours: 4, minutes: 39))),
        ),
        OrderModel(
          orderId: 'ORD002',
          symbol: 'INFY',
          transactionType: 'SELL',
          quantity: 25,
          filledQuantity: 25,
          price: 1890.75,
          status: 'COMPLETE',
          statusMessage: 'Order complete',
          orderType: 'LIMIT',
          product: 'MIS',
          placedAt: fmt(now.subtract(const Duration(hours: 3, minutes: 45))),
        ),
        OrderModel(
          orderId: 'ORD003',
          symbol: 'HDFCBANK',
          transactionType: 'BUY',
          quantity: 8,
          filledQuantity: 0,
          price: 1652.00,
          status: 'OPEN',
          statusMessage: 'Pending',
          orderType: 'LIMIT',
          product: 'CNC',
          placedAt: fmt(now.subtract(const Duration(hours: 2, minutes: 57))),
        ),
      ],
      positions: [
        const PositionModel(
          symbol: 'TCS',
          quantity: 5,
          avgPrice: 4250.0,
          ltp: 4389.75,
          pnl: 698.75,
          pnlPct: 3.29,
          product: 'CNC',
        ),
        const PositionModel(
          symbol: 'WIPRO',
          quantity: 20,
          avgPrice: 495.50,
          ltp: 472.30,
          pnl: -464.0,
          pnlPct: -4.68,
          product: 'MIS',
        ),
        const PositionModel(
          symbol: 'TATASTEEL',
          quantity: 15,
          avgPrice: 145.60,
          ltp: 151.80,
          pnl: 93.0,
          pnlPct: 4.26,
          product: 'CNC',
        ),
      ],
      gtts: [
        GttModel(
          gttId: 'GTT001',
          symbol: 'HDFC',
          exchange: 'NSE',
          status: 'ACTIVE',
          gttType: 'TWO_LEG',
          triggerValues: [1580.0, 1780.0],
          lastPrice: 1645.50,
          transactionType: 'SELL',
          quantity: 8,
          product: 'CNC',
          createdAt: '2025-01-15',
        ),
        GttModel(
          gttId: 'GTT002',
          symbol: 'ICICIBANK',
          exchange: 'NSE',
          status: 'ACTIVE',
          gttType: 'SINGLE',
          triggerValues: [1100.0],
          lastPrice: 1156.75,
          transactionType: 'SELL',
          quantity: 12,
          product: 'CNC',
          createdAt: '2025-01-18',
        ),
      ],
    );
  }

  String _timeStr(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';
}
