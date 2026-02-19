class OrderModel {
  final String orderId;
  final String symbol;
  final String transactionType;
  final int quantity;
  final int filledQuantity;
  final double price;
  final String status;
  final String statusMessage;
  final String orderType;
  final String product;
  final String placedAt;

  const OrderModel({
    required this.orderId,
    required this.symbol,
    required this.transactionType,
    required this.quantity,
    required this.filledQuantity,
    required this.price,
    required this.status,
    required this.statusMessage,
    required this.orderType,
    required this.product,
    required this.placedAt,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) => OrderModel(
        orderId: json['order_id']?.toString() ?? '',
        symbol: json['symbol']?.toString() ?? '',
        transactionType: json['transaction_type']?.toString() ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        filledQuantity: (json['filled_quantity'] as num?)?.toInt() ?? 0,
        price: (json['price'] as num?)?.toDouble() ?? 0.0,
        status: json['status']?.toString() ?? '',
        statusMessage: json['status_message']?.toString() ?? '',
        orderType: json['order_type']?.toString() ?? '',
        product: json['product']?.toString() ?? '',
        placedAt: json['placed_at']?.toString() ?? '',
      );
}

class PositionModel {
  final String symbol;
  final int quantity;
  final double avgPrice;
  final double ltp;
  final double pnl;
  final double pnlPct;
  final String product;

  const PositionModel({
    required this.symbol,
    required this.quantity,
    required this.avgPrice,
    required this.ltp,
    required this.pnl,
    required this.pnlPct,
    required this.product,
  });

  factory PositionModel.fromJson(Map<String, dynamic> json) => PositionModel(
        symbol: json['symbol']?.toString() ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        avgPrice: (json['avg_price'] as num?)?.toDouble() ?? 0.0,
        ltp: (json['ltp'] as num?)?.toDouble() ?? 0.0,
        pnl: (json['pnl'] as num?)?.toDouble() ?? 0.0,
        pnlPct: (json['pnl_pct'] as num?)?.toDouble() ?? 0.0,
        product: json['product']?.toString() ?? '',
      );
}

class GttModel {
  final String gttId;
  final String symbol;
  final String exchange;
  final String status;
  final String gttType;
  final List<double> triggerValues;
  final double lastPrice;
  final String transactionType;
  final int quantity;
  final String product;
  final String createdAt;

  const GttModel({
    required this.gttId,
    required this.symbol,
    required this.exchange,
    required this.status,
    required this.gttType,
    required this.triggerValues,
    required this.lastPrice,
    required this.transactionType,
    required this.quantity,
    required this.product,
    required this.createdAt,
  });

  factory GttModel.fromJson(Map<String, dynamic> json) => GttModel(
        gttId: json['gtt_id']?.toString() ?? '',
        symbol: json['symbol']?.toString() ?? '',
        exchange: json['exchange']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        gttType: json['gtt_type']?.toString() ?? '',
        triggerValues: (json['trigger_values'] as List<dynamic>? ?? [])
            .map((v) => (v as num).toDouble())
            .toList(),
        lastPrice: (json['last_price'] as num?)?.toDouble() ?? 0.0,
        transactionType: json['transaction_type']?.toString() ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        product: json['product']?.toString() ?? '',
        createdAt: json['created_at']?.toString() ?? '',
      );
}

class DashboardModel {
  final double availableBalance;
  final double todayPnl;
  final double todayPnlPct;
  final double monthPnl;
  final int monthTrades;
  final double monthWinRate;
  final int monthWins;
  final int monthLosses;
  final List<OrderModel> orders;
  final List<PositionModel> positions;
  final List<GttModel> gtts;
  final String fetchedAt;

  const DashboardModel({
    required this.availableBalance,
    required this.todayPnl,
    required this.todayPnlPct,
    required this.monthPnl,
    required this.monthTrades,
    required this.monthWinRate,
    required this.monthWins,
    required this.monthLosses,
    required this.orders,
    required this.positions,
    required this.gtts,
    required this.fetchedAt,
  });

  factory DashboardModel.fromJson(Map<String, dynamic> json) => DashboardModel(
        availableBalance: (json['available_balance'] as num?)?.toDouble() ?? 0.0,
        todayPnl: (json['today_pnl'] as num?)?.toDouble() ?? 0.0,
        todayPnlPct: (json['today_pnl_pct'] as num?)?.toDouble() ?? 0.0,
        monthPnl: (json['month_pnl'] as num?)?.toDouble() ?? 0.0,
        monthTrades: (json['month_trades'] as num?)?.toInt() ?? 0,
        monthWinRate: (json['month_win_rate'] as num?)?.toDouble() ?? 0.0,
        monthWins: (json['month_wins'] as num?)?.toInt() ?? 0,
        monthLosses: (json['month_losses'] as num?)?.toInt() ?? 0,
        orders: (json['orders'] as List<dynamic>? ?? [])
            .map((o) => OrderModel.fromJson(o as Map<String, dynamic>))
            .toList(),
        positions: (json['positions'] as List<dynamic>? ?? [])
            .map((p) => PositionModel.fromJson(p as Map<String, dynamic>))
            .toList(),
        gtts: (json['gtts'] as List<dynamic>? ?? [])
            .map((g) => GttModel.fromJson(g as Map<String, dynamic>))
            .toList(),
        fetchedAt: json['fetched_at']?.toString() ?? '',
      );
}
