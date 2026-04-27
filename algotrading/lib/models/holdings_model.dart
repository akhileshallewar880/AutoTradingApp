class Holding {
  final String symbol;
  final String exchange;
  final String isin;
  final int quantity;
  final int t1Quantity;
  final double averagePrice;
  final double lastPrice;
  final double closePrice;
  final double pnl;
  final double pnlPct;
  final double dayChange;
  final double dayChangePct;
  final double investedValue;
  final double currentValue;
  final String product;

  // GTT-based risk/reward (null when no active GTT)
  final double? stopLoss;
  final double? target;
  final double? maxProfit;
  final double? maxLoss;
  final bool hasGtt;
  final String? gttId;

  // Live / expiry fields
  final int? instrumentToken;
  final int? holdDurationDays;
  final int? daysLeft;
  final String? expiryDate;

  Holding({
    required this.symbol,
    required this.exchange,
    required this.isin,
    required this.quantity,
    required this.t1Quantity,
    required this.averagePrice,
    required this.lastPrice,
    required this.closePrice,
    required this.pnl,
    required this.pnlPct,
    required this.dayChange,
    required this.dayChangePct,
    required this.investedValue,
    required this.currentValue,
    required this.product,
    this.stopLoss,
    this.target,
    this.maxProfit,
    this.maxLoss,
    this.hasGtt = false,
    this.gttId,
    this.instrumentToken,
    this.holdDurationDays,
    this.daysLeft,
    this.expiryDate,
  });

  factory Holding.fromJson(Map<String, dynamic> json) {
    return Holding(
      symbol: json['symbol'] ?? '',
      exchange: json['exchange'] ?? 'NSE',
      isin: json['isin'] ?? '',
      quantity: json['quantity'] ?? 0,
      t1Quantity: json['t1_quantity'] ?? 0,
      averagePrice: (json['average_price'] ?? 0).toDouble(),
      lastPrice: (json['last_price'] ?? 0).toDouble(),
      closePrice: (json['close_price'] ?? 0).toDouble(),
      pnl: (json['pnl'] ?? 0).toDouble(),
      pnlPct: (json['pnl_pct'] ?? 0).toDouble(),
      dayChange: (json['day_change'] ?? 0).toDouble(),
      dayChangePct: (json['day_change_pct'] ?? 0).toDouble(),
      investedValue: (json['invested_value'] ?? 0).toDouble(),
      currentValue: (json['current_value'] ?? 0).toDouble(),
      product: json['product'] ?? 'CNC',
      stopLoss: json['stop_loss'] != null ? (json['stop_loss'] as num).toDouble() : null,
      target: json['target'] != null ? (json['target'] as num).toDouble() : null,
      maxProfit: json['max_profit'] != null ? (json['max_profit'] as num).toDouble() : null,
      maxLoss: json['max_loss'] != null ? (json['max_loss'] as num).toDouble() : null,
      hasGtt: json['has_gtt'] ?? false,
      gttId: json['gtt_id']?.toString(),
      instrumentToken: json['instrument_token'] != null ? (json['instrument_token'] as num).toInt() : null,
      holdDurationDays: json['hold_duration_days'] != null ? (json['hold_duration_days'] as num).toInt() : null,
      daysLeft: json['days_left'] != null ? (json['days_left'] as num).toInt() : null,
      expiryDate: json['expiry_date']?.toString(),
    );
  }

  Holding copyWith({
    double? lastPrice,
    double? pnl,
    double? pnlPct,
    double? currentValue,
    double? dayChange,
    double? dayChangePct,
  }) {
    return Holding(
      symbol: symbol, exchange: exchange, isin: isin,
      quantity: quantity, t1Quantity: t1Quantity,
      averagePrice: averagePrice,
      lastPrice: lastPrice ?? this.lastPrice,
      closePrice: closePrice,
      pnl: pnl ?? this.pnl,
      pnlPct: pnlPct ?? this.pnlPct,
      dayChange: dayChange ?? this.dayChange,
      dayChangePct: dayChangePct ?? this.dayChangePct,
      investedValue: investedValue,
      currentValue: currentValue ?? this.currentValue,
      product: product,
      stopLoss: stopLoss, target: target,
      maxProfit: maxProfit, maxLoss: maxLoss,
      hasGtt: hasGtt, gttId: gttId,
      instrumentToken: instrumentToken,
      holdDurationDays: holdDurationDays,
      daysLeft: daysLeft,
      expiryDate: expiryDate,
    );
  }
}

class HoldingsSummary {
  final double totalInvested;
  final double totalCurrentValue;
  final double totalPnl;
  final double overallPnlPct;

  HoldingsSummary({
    required this.totalInvested,
    required this.totalCurrentValue,
    required this.totalPnl,
    required this.overallPnlPct,
  });

  factory HoldingsSummary.fromJson(Map<String, dynamic> json) {
    return HoldingsSummary(
      totalInvested: (json['total_invested'] ?? 0).toDouble(),
      totalCurrentValue: (json['total_current_value'] ?? 0).toDouble(),
      totalPnl: (json['total_pnl'] ?? 0).toDouble(),
      overallPnlPct: (json['overall_pnl_pct'] ?? 0).toDouble(),
    );
  }
}
