import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/dashboard_model.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../theme/vt_color_scheme.dart';

class OpenOrdersScreen extends StatefulWidget {
  const OpenOrdersScreen({super.key});

  @override
  State<OpenOrdersScreen> createState() => _OpenOrdersScreenState();
}

class _OpenOrdersScreenState extends State<OpenOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vt = context.vt;
    final dash = context.watch<DashboardProvider>();
    final orders = dash.dashboard?.orders ?? [];

    final openOrders = orders.where((o) => o.isOpen && !o.isAmo).toList();
    final amoOrders  = orders.where((o) => o.isAmo).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: vt.textPrimary,
        elevation: 0,
        title: Text('Orders', style: AppTextStyles.h2),
        actions: [
          if (dash.isLoading)
            const Padding(
              padding: EdgeInsets.only(right: Sp.base),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                final auth = context.read<AuthProvider>();
                final token = auth.user?.accessToken ?? '';
                if (token.isNotEmpty) dash.fetchDashboard(token);
              },
              tooltip: 'Refresh',
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: vt.accentGreen,
          unselectedLabelColor: vt.textSecondary,
          indicatorColor: vt.accentGreen,
          labelStyle: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700),
          tabs: [
            Tab(text: 'Open Orders (${openOrders.length})'),
            Tab(text: 'AMO (${amoOrders.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OrderList(orders: openOrders, emptyLabel: 'No open orders'),
          _OrderList(orders: amoOrders, emptyLabel: 'No AMO orders placed today'),
        ],
      ),
    );
  }
}

// ── Order list ────────────────────────────────────────────────────────────────

class _OrderList extends StatelessWidget {
  final List<OrderModel> orders;
  final String emptyLabel;
  const _OrderList({required this.orders, required this.emptyLabel});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) return _Empty(label: emptyLabel);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(Sp.base, Sp.sm, Sp.base, Sp.xxl),
      itemCount: orders.length,
      itemBuilder: (_, i) => _OrderTile(order: orders[i]),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _Empty extends StatelessWidget {
  final String label;
  const _Empty({required this.label});

  @override
  Widget build(BuildContext context) {
    final vt = context.vt;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: vt.accentGreen.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(color: vt.accentGreen.withValues(alpha: 0.2)),
              ),
              child: Icon(Icons.receipt_long_outlined, size: 36, color: vt.accentGreen),
            ),
            const SizedBox(height: Sp.xl),
            Text(label, style: AppTextStyles.h3, textAlign: TextAlign.center),
            const SizedBox(height: Sp.sm),
            Text(
              'Orders placed during market hours will appear here.',
              style: AppTextStyles.bodySecondary.copyWith(height: 1.6),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Order tile ────────────────────────────────────────────────────────────────

class _OrderTile extends StatelessWidget {
  final OrderModel order;
  const _OrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final vt = context.vt;
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

    final isBuy = order.transactionType.toUpperCase() == 'BUY';
    final sideColor = isBuy ? vt.accentGreen : vt.danger;

    DateTime? placed;
    try {
      placed = DateTime.parse(order.placedAt).toLocal();
    } catch (_) {}

    final statusInfo = _statusInfo(order.status, vt);
    final isPartial = order.filledQuantity > 0 && order.filledQuantity < order.quantity;

    return Container(
      margin: const EdgeInsets.only(bottom: Sp.sm),
      decoration: BoxDecoration(
        color: vt.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: vt.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Sp.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ─────────────────────────────────────────────────
            Row(
              children: [
                // Side pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: sideColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Rad.sm),
                    border: Border.all(color: sideColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    order.transactionType.toUpperCase(),
                    style: AppTextStyles.label.copyWith(
                      color: sideColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(order.symbol, style: AppTextStyles.h3),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusInfo.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Rad.sm),
                  ),
                  child: Text(
                    statusInfo.label,
                    style: AppTextStyles.label.copyWith(
                      color: statusInfo.color,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: Sp.sm),
            Divider(height: 1, color: vt.divider),
            const SizedBox(height: Sp.sm),

            // ── Details row ────────────────────────────────────────────────
            Row(
              children: [
                _detail(context, 'Qty', '${order.quantity}'),
                _detail(context, 'Filled', '${order.filledQuantity}',
                    color: isPartial ? vt.warning : null),
                _detail(context, 'Price',
                    order.price > 0 ? currency.format(order.price) : 'MARKET'),
                _detail(context, 'Type', order.orderType),
              ],
            ),

            const SizedBox(height: Sp.sm),

            // ── Footer row ─────────────────────────────────────────────────
            Row(
              children: [
                _tag(vt, order.product),
                if (order.isAmo) ...[
                  const SizedBox(width: Sp.xs),
                  _tag(vt, 'AMO', color: vt.accentPurple),
                ],
                const Spacer(),
                if (placed != null)
                  Text(
                    DateFormat('hh:mm a').format(placed),
                    style: AppTextStyles.caption,
                  ),
              ],
            ),

            if (order.statusMessage.isNotEmpty) ...[
              const SizedBox(height: Sp.xs),
              Text(
                order.statusMessage,
                style: AppTextStyles.caption.copyWith(
                  color: vt.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detail(BuildContext context, String label, String value, {Color? color}) {
    final vt = context.vt;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption),
          Text(
            value,
            style: AppTextStyles.mono.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color ?? vt.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(VtColorScheme vt, String label, {Color? color}) {
    final c = color ?? vt.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Rad.sm),
        border: Border.all(color: c.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: AppTextStyles.label.copyWith(
          fontSize: 10,
          color: c,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  ({String label, Color color}) _statusInfo(String status, VtColorScheme vt) {
    final s = status.toUpperCase();
    if (s == 'OPEN' || s == 'OPEN PENDING' || s == 'PUT ORDER REQ RECEIVED') {
      return (label: 'OPEN', color: vt.accentGreen);
    }
    if (s == 'TRIGGER PENDING') return (label: 'TRIGGER', color: vt.warning);
    if (s.contains('PENDING')) return (label: 'PENDING', color: vt.warning);
    if (s == 'COMPLETE') return (label: 'FILLED', color: vt.accentGreen);
    if (s == 'CANCELLED') return (label: 'CANCELLED', color: vt.textSecondary);
    if (s == 'REJECTED') return (label: 'REJECTED', color: vt.danger);
    return (label: status, color: vt.textSecondary);
  }
}
