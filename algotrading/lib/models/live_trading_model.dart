class AgentSettingsModel {
  final int maxPositions;
  final double riskPercent;
  final int scanIntervalMinutes;
  final int maxTradesPerDay;
  final double maxDailyLossPct;
  final double capitalToUse;
  final int leverage;

  const AgentSettingsModel({
    required this.maxPositions,
    required this.riskPercent,
    required this.scanIntervalMinutes,
    required this.maxTradesPerDay,
    required this.maxDailyLossPct,
    required this.capitalToUse,
    this.leverage = 1,
  });

  factory AgentSettingsModel.fromJson(Map<String, dynamic> json) {
    return AgentSettingsModel(
      maxPositions: json['max_positions'] as int? ?? 2,
      riskPercent: (json['risk_percent'] as num?)?.toDouble() ?? 1.0,
      scanIntervalMinutes: json['scan_interval_minutes'] as int? ?? 5,
      maxTradesPerDay: json['max_trades_per_day'] as int? ?? 6,
      maxDailyLossPct: (json['max_daily_loss_pct'] as num?)?.toDouble() ?? 2.0,
      capitalToUse: (json['capital_to_use'] as num?)?.toDouble() ?? 0.0,
      leverage: json['leverage'] as int? ?? 1,
    );
  }

  static AgentSettingsModel defaults() => const AgentSettingsModel(
        maxPositions: 2,
        riskPercent: 1.0,
        scanIntervalMinutes: 5,
        maxTradesPerDay: 6,
        maxDailyLossPct: 2.0,
        capitalToUse: 0.0,
        leverage: 1,
      );
}

class AgentPositionModel {
  final String symbol;
  final String action;
  final int quantity;
  final double entryPrice;
  final double stopLoss;
  final double target;
  final String? gttId;
  final String enteredAt;
  final bool trailActivated;
  final int trailCount;
  final bool targetAdjusted;
  final double originalTarget;
  final double currentPnl;

  const AgentPositionModel({
    required this.symbol,
    required this.action,
    required this.quantity,
    required this.entryPrice,
    required this.stopLoss,
    required this.target,
    this.gttId,
    required this.enteredAt,
    required this.trailActivated,
    this.trailCount = 0,
    this.targetAdjusted = false,
    double? originalTarget,
    required this.currentPnl,
  }) : originalTarget = originalTarget ?? target;

  factory AgentPositionModel.fromJson(Map<String, dynamic> json) {
    final target = (json['target'] as num?)?.toDouble() ?? 0.0;
    return AgentPositionModel(
      symbol: json['symbol'] as String? ?? '',
      action: json['action'] as String? ?? 'BUY',
      quantity: json['quantity'] as int? ?? 0,
      entryPrice: (json['entry_price'] as num?)?.toDouble() ?? 0.0,
      stopLoss: (json['stop_loss'] as num?)?.toDouble() ?? 0.0,
      target: target,
      gttId: json['gtt_id']?.toString(),
      enteredAt: json['entered_at'] as String? ?? '',
      trailActivated: json['trail_activated'] as bool? ?? false,
      trailCount: json['trail_count'] as int? ?? 0,
      targetAdjusted: json['target_adjusted'] as bool? ?? false,
      originalTarget: (json['original_target'] as num?)?.toDouble() ?? target,
      currentPnl: (json['current_pnl'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class AgentLogModel {
  final String event;
  final String message;
  final String? symbol;
  final String timestamp;

  const AgentLogModel({
    required this.event,
    required this.message,
    this.symbol,
    required this.timestamp,
  });

  factory AgentLogModel.fromJson(Map<String, dynamic> json) {
    return AgentLogModel(
      event: json['event'] as String? ?? '',
      message: json['message'] as String? ?? '',
      symbol: json['symbol'] as String?,
      timestamp: json['timestamp'] as String? ?? '',
    );
  }
}

class AgentStatusModel {
  final bool isRunning;
  final String status;
  final String? startedAt;
  final String? lastScanAt;
  final bool tickerConnected;
  final bool scanningDone;
  final List<AgentPositionModel> openPositions;
  final int tradeCountToday;
  final double dailyPnl;
  final bool dailyLossLimitHit;
  final AgentSettingsModel settings;
  final List<AgentLogModel> recentLogs;

  const AgentStatusModel({
    required this.isRunning,
    required this.status,
    this.startedAt,
    this.lastScanAt,
    this.tickerConnected = false,
    this.scanningDone = false,
    required this.openPositions,
    required this.tradeCountToday,
    required this.dailyPnl,
    required this.dailyLossLimitHit,
    required this.settings,
    required this.recentLogs,
  });

  factory AgentStatusModel.fromJson(Map<String, dynamic> json) {
    return AgentStatusModel(
      isRunning: json['is_running'] as bool? ?? false,
      status: json['status'] as String? ?? 'STOPPED',
      startedAt: json['started_at'] as String?,
      lastScanAt: json['last_scan_at'] as String?,
      tickerConnected: json['ticker_connected'] as bool? ?? false,
      scanningDone: json['scanning_done'] as bool? ?? false,
      openPositions: (json['open_positions'] as List<dynamic>?)
              ?.map((e) => AgentPositionModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tradeCountToday: json['trade_count_today'] as int? ?? 0,
      dailyPnl: (json['daily_pnl'] as num?)?.toDouble() ?? 0.0,
      dailyLossLimitHit: json['daily_loss_limit_hit'] as bool? ?? false,
      settings: json['settings'] != null
          ? AgentSettingsModel.fromJson(json['settings'] as Map<String, dynamic>)
          : AgentSettingsModel.defaults(),
      recentLogs: (json['recent_logs'] as List<dynamic>?)
              ?.map((e) => AgentLogModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  static AgentStatusModel stopped() => AgentStatusModel(
        isRunning: false,
        status: 'STOPPED',
        tickerConnected: false,
        scanningDone: false,
        openPositions: const [],
        tradeCountToday: 0,
        dailyPnl: 0.0,
        dailyLossLimitHit: false,
        settings: AgentSettingsModel.defaults(),
        recentLogs: const [],
      );
}
