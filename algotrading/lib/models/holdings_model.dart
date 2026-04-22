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
