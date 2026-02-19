import 'package:flutter/material.dart';
import '../models/analysis_model.dart';
import '../services/api_service.dart';

class AnalysisProvider with ChangeNotifier {
  AnalysisResponseModel? _currentAnalysis;
  ExecutionStatusModel? _executionStatus;
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = false;
  String? _error;

  // Hold duration in days (0 = intraday)
  int _holdDurationDays = 0;
  // Selected sectors for stock universe
  List<String> _selectedSectors = ['ALL'];

  AnalysisResponseModel? get currentAnalysis => _currentAnalysis;
  ExecutionStatusModel? get executionStatus => _executionStatus;
  List<Map<String, dynamic>> get history => _history;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get holdDurationDays => _holdDurationDays;
  List<String> get selectedSectors => _selectedSectors;

  void setHoldDuration(int days) {
    _holdDurationDays = days;
    notifyListeners();
  }

  void setSelectedSectors(List<String> sectors) {
    _selectedSectors = sectors.isEmpty ? ['ALL'] : sectors;
    notifyListeners();
  }

  Future<void> generateAnalysis({
    required String analysisDate,
    required int numStocks,
    required double riskPercent,
    required String accessToken,
    List<String>? sectors,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final analysis = await ApiService.generateAnalysis(
        analysisDate: analysisDate,
        numStocks: numStocks,
        riskPercent: riskPercent,
        accessToken: accessToken,
        sectors: sectors ?? _selectedSectors,
        holdDurationDays: _holdDurationDays,
      );
      _currentAnalysis = analysis;
      _error = null;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> confirmAnalysis({
    required String analysisId,
    required bool confirmed,
    String? notes,
    required String accessToken,
    int? holdDurationDays,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Create overrides from current (potentially edited) stocks
      final overrides = _currentAnalysis?.stocks.map((s) => {
        'stock_symbol': s.stockSymbol,
        'quantity': s.quantity,
      }).toList();

      await ApiService.confirmAnalysis(
        analysisId: analysisId,
        confirmed: confirmed,
        notes: notes,
        accessToken: accessToken,
        holdDurationDays: holdDurationDays ?? _holdDurationDays,
        stockOverrides: overrides,
      );
      if (_currentAnalysis != null && confirmed) {
        await loadExecutionStatus(analysisId, accessToken);
      }
      _error = null;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadExecutionStatus(String analysisId, String accessToken) async {
    try {
      final status = await ApiService.getExecutionStatus(
        analysisId: analysisId,
        accessToken: accessToken,
      );
      _executionStatus = status;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadHistory(String accessToken) async {
    _isLoading = true;
    notifyListeners();

    try {
      final historyData = await ApiService.getAnalysisHistory(
        accessToken: accessToken,
      );
      _history = historyData;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void updateStockQuantity(int stockIndex, int newQuantity) {
    if (_currentAnalysis == null) return;
    if (newQuantity < 1) return;

    final stocks = List<StockAnalysisModel>.from(_currentAnalysis!.stocks);
    final stock = stocks[stockIndex];

    // 1. Recalculate individual stock metrics
    final riskPerShare = (stock.entryPrice - stock.stopLoss).abs();
    final profitPerShare = (stock.targetPrice - stock.entryPrice).abs();

    final newPotentialLoss = riskPerShare * newQuantity;
    final newPotentialProfit = profitPerShare * newQuantity;

    stocks[stockIndex] = stock.copyWith(
      quantity: newQuantity,
      potentialLoss: newPotentialLoss,
      potentialProfit: newPotentialProfit,
    );

    // 2. Recalculate portfolio metrics
    double totalInvestment = 0;
    double totalRisk = 0;
    double maxProfit = 0;
    double maxLoss = 0;

    for (final s in stocks) {
      totalInvestment += s.entryPrice * s.quantity;
      final sRisk = (s.entryPrice - s.stopLoss).abs() * s.quantity;
      final sProfit = (s.targetPrice - s.entryPrice).abs() * s.quantity;
      totalRisk += sRisk;
      maxProfit += sProfit;
      maxLoss += sRisk; // max_loss tracks total risk amount
    }

    final updatedMetrics = Map<String, dynamic>.from(_currentAnalysis!.portfolioMetrics);
    updatedMetrics['total_investment'] = totalInvestment;
    updatedMetrics['total_risk'] = totalRisk;
    updatedMetrics['max_profit'] = maxProfit;
    updatedMetrics['max_loss'] = maxLoss;

    _currentAnalysis = AnalysisResponseModel(
      analysisId: _currentAnalysis!.analysisId,
      analysisDate: _currentAnalysis!.analysisDate,
      stocks: stocks,
      portfolioMetrics: updatedMetrics,
    );
    notifyListeners();
  }

  void clearCurrentAnalysis() {
    _currentAnalysis = null;
    _executionStatus = null;
    notifyListeners();
  }
}
