class StockAnalysisModel {
  final String stockSymbol;
  final String? companyName;
  final String action;
  final double entryPrice;
  final double stopLoss;
  final double targetPrice;
  final int quantity;
  final double potentialProfit;
  final double potentialLoss;
  final double riskRewardRatio;
  final double confidenceScore;
  final String aiReasoning;
  final int? daysToTarget; // LLM-estimated trading days to reach target

  StockAnalysisModel({
    required this.stockSymbol,
    this.companyName,
    required this.action,
    required this.entryPrice,
    required this.stopLoss,
    required this.targetPrice,
    required this.quantity,
    required this.potentialProfit,
    required this.potentialLoss,
    required this.riskRewardRatio,
    required this.confidenceScore,
    required this.aiReasoning,
    this.daysToTarget,
  });

  StockAnalysisModel copyWith({
    String? stockSymbol,
    String? companyName,
    String? action,
    double? entryPrice,
    double? stopLoss,
    double? targetPrice,
    int? quantity,
    double? potentialProfit,
    double? potentialLoss,
    double? riskRewardRatio,
    double? confidenceScore,
    String? aiReasoning,
    int? daysToTarget,
  }) {
    return StockAnalysisModel(
      stockSymbol: stockSymbol ?? this.stockSymbol,
      companyName: companyName ?? this.companyName,
      action: action ?? this.action,
      entryPrice: entryPrice ?? this.entryPrice,
      stopLoss: stopLoss ?? this.stopLoss,
      targetPrice: targetPrice ?? this.targetPrice,
      quantity: quantity ?? this.quantity,
      potentialProfit: potentialProfit ?? this.potentialProfit,
      potentialLoss: potentialLoss ?? this.potentialLoss,
      riskRewardRatio: riskRewardRatio ?? this.riskRewardRatio,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      aiReasoning: aiReasoning ?? this.aiReasoning,
      daysToTarget: daysToTarget ?? this.daysToTarget,
    );
  }

  factory StockAnalysisModel.fromJson(Map<String, dynamic> json) {
    return StockAnalysisModel(
      stockSymbol: json['stock_symbol'] as String,
      companyName: json['company_name'] as String?,
      action: json['action'] as String,
      entryPrice: (json['entry_price'] as num).toDouble(),
      stopLoss: (json['stop_loss'] as num).toDouble(),
      targetPrice: (json['target_price'] as num).toDouble(),
      quantity: json['quantity'] as int,
      potentialProfit: (json['potential_profit'] as num).toDouble(),
      potentialLoss: (json['potential_loss'] as num).toDouble(),
      riskRewardRatio: (json['risk_reward_ratio'] as num).toDouble(),
      confidenceScore: (json['confidence_score'] as num).toDouble(),
      aiReasoning: json['ai_reasoning'] as String,
      daysToTarget: json['days_to_target'] as int?,
    );
  }
}

class AnalysisResponseModel {
  final String analysisId;
  final String analysisDate;
  final List<StockAnalysisModel> stocks;
  final Map<String, dynamic> portfolioMetrics;

  AnalysisResponseModel({
    required this.analysisId,
    required this.analysisDate,
    required this.stocks,
    required this.portfolioMetrics,
  });

  factory AnalysisResponseModel.fromJson(Map<String, dynamic> json) {
    return AnalysisResponseModel(
      analysisId: json['analysis_id'] as String,
      analysisDate: json['created_at'] as String,
      stocks: (json['stocks'] as List)
          .map((stock) => StockAnalysisModel.fromJson(stock as Map<String, dynamic>))
          .toList(),
      portfolioMetrics: json['portfolio_metrics'] as Map<String, dynamic>,
    );
  }
}

class ExecutionUpdateModel {
  final DateTime timestamp;
  final String updateType;
  final String stockSymbol;
  final String message;
  final String? orderId;

  ExecutionUpdateModel({
    required this.timestamp,
    required this.updateType,
    required this.stockSymbol,
    required this.message,
    this.orderId,
  });

  factory ExecutionUpdateModel.fromJson(Map<String, dynamic> json) {
    return ExecutionUpdateModel(
      timestamp: DateTime.parse(json['timestamp'] as String),
      updateType: json['update_type'] as String,
      stockSymbol: json['stock_symbol'] as String,
      message: json['message'] as String,
      orderId: json['order_id'] as String?,
    );
  }
}

class ExecutionStatusModel {
  final String analysisId;
  final String overallStatus;
  final int totalStocks;
  final int completedStocks;
  final int failedStocks;
  final List<ExecutionUpdateModel> updates;

  ExecutionStatusModel({
    required this.analysisId,
    required this.overallStatus,
    required this.totalStocks,
    required this.completedStocks,
    required this.failedStocks,
    required this.updates,
  });

  factory ExecutionStatusModel.fromJson(Map<String, dynamic> json) {
    return ExecutionStatusModel(
      analysisId: json['analysis_id'] as String,
      overallStatus: json['overall_status'] as String,
      totalStocks: json['total_stocks'] as int,
      completedStocks: json['completed_stocks'] as int,
      failedStocks: json['failed_stocks'] as int,
      updates: (json['updates'] as List)
          .map((update) => ExecutionUpdateModel.fromJson(update as Map<String, dynamic>))
          .toList(),
    );
  }
}
