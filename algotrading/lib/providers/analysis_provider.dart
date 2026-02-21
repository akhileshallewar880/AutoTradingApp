import 'package:flutter/material.dart';
import '../models/analysis_model.dart';
import '../services/api_service.dart';
import 'auth_provider.dart' show kDemoAccessToken;

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
    double capitalToUse = 0,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (accessToken == kDemoAccessToken) {
        // Simulate AI processing delay so the loading overlay feels real
        await Future.delayed(const Duration(seconds: 2));
        _currentAnalysis = _buildDemoAnalysis(numStocks, capitalToUse);
      } else {
        final analysis = await ApiService.generateAnalysis(
          analysisDate: analysisDate,
          numStocks: numStocks,
          riskPercent: riskPercent,
          accessToken: accessToken,
          sectors: sectors ?? _selectedSectors,
          holdDurationDays: _holdDurationDays,
          capitalToUse: capitalToUse,
        );
        _currentAnalysis = analysis;
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
      if (accessToken == kDemoAccessToken) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (confirmed && _currentAnalysis != null) {
          _executionStatus = _buildDemoExecutionStatus(analysisId);
        }
      } else {
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
      if (accessToken == kDemoAccessToken) {
        // Return the already-complete demo status; no API polling needed
        _executionStatus ??= _buildDemoExecutionStatus(analysisId);
        notifyListeners();
        return;
      }
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
      if (accessToken == kDemoAccessToken) {
        await Future.delayed(const Duration(milliseconds: 400));
        _history = _buildDemoHistory();
      } else {
        final historyData = await ApiService.getAnalysisHistory(
          accessToken: accessToken,
        );
        _history = historyData;
      }
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

    final riskPerShare = (stock.entryPrice - stock.stopLoss).abs();
    final profitPerShare = (stock.targetPrice - stock.entryPrice).abs();

    final newPotentialLoss = riskPerShare * newQuantity;
    final newPotentialProfit = profitPerShare * newQuantity;

    stocks[stockIndex] = stock.copyWith(
      quantity: newQuantity,
      potentialLoss: newPotentialLoss,
      potentialProfit: newPotentialProfit,
    );

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
      maxLoss += sRisk;
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

  // ── Demo data ──────────────────────────────────────────────────────────────

  static const _demoStockPool = [
    _DemoStock('RELIANCE', 'Reliance Industries Ltd.', 'BUY',
        2875.50, 2815.0, 3010.0, 5, 3, 0.84,
        'Strong bullish momentum on daily chart. RSI at 58 indicates room for '
        'further upside. Key resistance at ₹2,900 likely to break with surging '
        'volumes. O&G sector outperforming the broad market. Entry at current '
        'levels with a tight SL near the support zone.'),
    _DemoStock('INFY', 'Infosys Ltd.', 'BUY',
        1892.0, 1850.0, 1990.0, 8, 5, 0.79,
        'IT sector showing revival after recent correction. Infosys maintaining '
        'above 200-DMA support. MACD bullish crossover forming on 4H chart. '
        'Upcoming quarterly results expected to be positive. Risk-reward is '
        'favorable at the current entry.'),
    _DemoStock('HDFCBANK', 'HDFC Bank Ltd.', 'BUY',
        1652.0, 1615.0, 1745.0, 6, 4, 0.87,
        'Banking heavyweight showing accumulation pattern. FII buying visible '
        'over the last 3 sessions. Breakout above ₹1,640 resistance on high '
        'volumes. Credit growth remains strong. Fundamentally solid with low NPA '
        'levels supporting the upside move.'),
    _DemoStock('TATASTEEL', 'Tata Steel Ltd.', 'BUY',
        145.80, 140.50, 158.0, 50, 7, 0.71,
        'Metal sector recovering on positive China stimulus news. Steel demand '
        'pickup visible in Q3 data. Technical setup shows a W-pattern formation '
        'near support. Infrastructure spending boost expected in the upcoming '
        'budget to aid demand.'),
    _DemoStock('SUNPHARMA', 'Sun Pharmaceutical Industries', 'SELL',
        1745.0, 1790.0, 1650.0, 5, 6, 0.68,
        'Pharma sector facing headwinds from USFDA warnings. SUNPHARMA showing '
        'distribution pattern with decreasing volumes on up days. RSI divergence '
        'bearish signal. Short-sell opportunity with clear target and stop levels.'),
    _DemoStock('BAJFINANCE', 'Bajaj Finance Ltd.', 'BUY',
        7120.0, 6980.0, 7480.0, 2, 5, 0.82,
        'NBFC leader holding key support at ₹7,000. RBI policy outlook positive '
        'for credit growth. Strong results history. Breakout pattern on weekly '
        'chart with increasing institutional interest.'),
    _DemoStock('AXISBANK', 'Axis Bank Ltd.', 'BUY',
        1089.0, 1055.0, 1165.0, 10, 4, 0.76,
        'Private sector bank showing relative strength. NIM expansion expected '
        'in upcoming results. Technical breakout above ₹1,080 neckline. '
        'Consistent accumulation by DIIs over the past week signals confidence.'),
  ];

  AnalysisResponseModel _buildDemoAnalysis(int numStocks, double capitalToUse) {
    final count = numStocks.clamp(1, _demoStockPool.length);
    final stocks = _demoStockPool.take(count).map((d) {
      final riskPerShare = (d.entry - d.sl).abs();
      final profitPerShare = (d.target - d.entry).abs();
      return StockAnalysisModel(
        stockSymbol: d.symbol,
        companyName: d.name,
        action: d.action,
        entryPrice: d.entry,
        stopLoss: d.sl,
        targetPrice: d.target,
        quantity: d.qty,
        potentialProfit: profitPerShare * d.qty,
        potentialLoss: riskPerShare * d.qty,
        riskRewardRatio: profitPerShare / riskPerShare,
        confidenceScore: d.confidence,
        aiReasoning: d.reasoning,
        daysToTarget: d.days,
      );
    }).toList();

    double totalInvestment = 0, totalRisk = 0, maxProfit = 0, maxLoss = 0;
    for (final s in stocks) {
      totalInvestment += s.entryPrice * s.quantity;
      final risk = (s.entryPrice - s.stopLoss).abs() * s.quantity;
      final profit = (s.targetPrice - s.entryPrice).abs() * s.quantity;
      totalRisk += risk;
      maxProfit += profit;
      maxLoss += risk;
    }

    return AnalysisResponseModel(
      analysisId: 'DEMO_${DateTime.now().millisecondsSinceEpoch}',
      analysisDate: DateTime.now().toIso8601String(),
      stocks: stocks,
      portfolioMetrics: {
        'available_balance': capitalToUse > 0 ? capitalToUse : 125000.0,
        'total_investment': totalInvestment,
        'total_risk': totalRisk,
        'max_profit': maxProfit,
        'max_loss': maxLoss,
      },
    );
  }

  ExecutionStatusModel _buildDemoExecutionStatus(String analysisId) {
    final stocks = _currentAnalysis?.stocks ?? [];
    final now = DateTime.now();
    final updates = stocks.asMap().entries.map((e) {
      return ExecutionUpdateModel(
        timestamp: now.add(Duration(milliseconds: e.key * 350)),
        updateType: 'DEMO_MODE',
        stockSymbol: e.value.stockSymbol,
        message: 'Demo — ${e.value.stockSymbol} ${e.value.action} '
            '${e.value.quantity} qty @ ₹${e.value.entryPrice.toStringAsFixed(2)} '
            'would be placed here. Login with Zerodha credentials to execute real trades.',
      );
    }).toList();

    return ExecutionStatusModel(
      analysisId: analysisId,
      overallStatus: 'COMPLETED',
      totalStocks: stocks.length,
      completedStocks: stocks.length,
      failedStocks: 0,
      updates: updates,
    );
  }

  List<Map<String, dynamic>> _buildDemoHistory() => [
    {
      'analysis_id': 'DEMO_HIST_001',
      'created_at': DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String(),
      'num_stocks': 3,
      'status': 'COMPLETED',
      'total_pnl': 1245.50,
    },
    {
      'analysis_id': 'DEMO_HIST_002',
      'created_at': DateTime.now()
          .subtract(const Duration(days: 3))
          .toIso8601String(),
      'num_stocks': 5,
      'status': 'COMPLETED',
      'total_pnl': -320.0,
    },
  ];
}

// Private helper — holds demo stock seed data
class _DemoStock {
  final String symbol, name, action, reasoning;
  final double entry, sl, target, confidence;
  final int qty, days;

  const _DemoStock(this.symbol, this.name, this.action,
      this.entry, this.sl, this.target, this.qty, this.days,
      this.confidence, this.reasoning);
}
