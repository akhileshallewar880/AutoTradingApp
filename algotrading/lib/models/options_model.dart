class OptionsTrade {
  final String optionSymbol;
  final String index;
  final String optionType; // CE or PE
  final double strikePrice;
  final String expiryDate;
  final int lotSize;
  final int lots;
  final int quantity;
  final int instrumentToken;
  final double entryPremium;
  final double stopLossPremium;
  final double targetPremium;
  final double totalInvestment;
  final double maxLoss;
  final double maxProfit;
  final double riskRewardRatio;
  final double confidenceScore;
  final int suggestedHoldMinutes;
  final String holdReasoning;
  final String aiReasoning;
  final double currentIndexPrice;
  final String signal; // BUY_CE or BUY_PE

  OptionsTrade({
    required this.optionSymbol,
    required this.index,
    required this.optionType,
    required this.strikePrice,
    required this.expiryDate,
    required this.lotSize,
    required this.lots,
    required this.quantity,
    required this.instrumentToken,
    required this.entryPremium,
    required this.stopLossPremium,
    required this.targetPremium,
    required this.totalInvestment,
    required this.maxLoss,
    required this.maxProfit,
    required this.riskRewardRatio,
    required this.confidenceScore,
    required this.suggestedHoldMinutes,
    required this.holdReasoning,
    required this.aiReasoning,
    required this.currentIndexPrice,
    required this.signal,
  });

  factory OptionsTrade.fromJson(Map<String, dynamic> json) {
    return OptionsTrade(
      optionSymbol: json['option_symbol'] ?? '',
      index: json['index'] ?? '',
      optionType: json['option_type'] ?? '',
      strikePrice: (json['strike_price'] ?? 0).toDouble(),
      expiryDate: json['expiry_date'] ?? '',
      lotSize: json['lot_size'] ?? 75,
      lots: json['lots'] ?? 1,
      quantity: json['quantity'] ?? 0,
      instrumentToken: json['instrument_token'] ?? 0,
      entryPremium: (json['entry_premium'] ?? 0).toDouble(),
      stopLossPremium: (json['stop_loss_premium'] ?? 0).toDouble(),
      targetPremium: (json['target_premium'] ?? 0).toDouble(),
      totalInvestment: (json['total_investment'] ?? 0).toDouble(),
      maxLoss: (json['max_loss'] ?? 0).toDouble(),
      maxProfit: (json['max_profit'] ?? 0).toDouble(),
      riskRewardRatio: (json['risk_reward_ratio'] ?? 2.0).toDouble(),
      confidenceScore: (json['confidence_score'] ?? 0.5).toDouble(),
      suggestedHoldMinutes: (json['suggested_hold_minutes'] ?? 30) as int,
      holdReasoning: json['hold_reasoning'] ?? '',
      aiReasoning: json['ai_reasoning'] ?? '',
      currentIndexPrice: (json['current_index_price'] ?? 0).toDouble(),
      signal: json['signal'] ?? 'NEUTRAL',
    );
  }
}

class OptionsAnalysis {
  final String analysisId;
  final String index;
  final double currentIndexPrice;
  final String expiryDate;
  final OptionsTrade? trade;
  final Map<String, dynamic> indexIndicators;
  final String status;
  final DateTime createdAt;

  OptionsAnalysis({
    required this.analysisId,
    required this.index,
    required this.currentIndexPrice,
    required this.expiryDate,
    this.trade,
    required this.indexIndicators,
    required this.status,
    required this.createdAt,
  });

  factory OptionsAnalysis.fromJson(Map<String, dynamic> json) {
    return OptionsAnalysis(
      analysisId: json['analysis_id'] ?? '',
      index: json['index'] ?? '',
      currentIndexPrice: (json['current_index_price'] ?? 0).toDouble(),
      expiryDate: json['expiry_date'] ?? '',
      trade: json['trade'] != null ? OptionsTrade.fromJson(json['trade']) : null,
      indexIndicators: json['index_indicators'] ?? {},
      status: json['status'] ?? 'PENDING_CONFIRMATION',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at']) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
