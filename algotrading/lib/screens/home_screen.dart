import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/analysis_provider.dart';
import '../models/dashboard_model.dart';
import 'analysis_input_screen.dart';
import 'analysis_results_screen.dart';
import 'gtt_analysis_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDashboard());
  }

  void _initDashboard() {
    final auth = context.read<AuthProvider>();
    final dash = context.read<DashboardProvider>();
    if (auth.user != null) {
      dash.fetchDashboard(auth.user!.accessToken);
      dash.startAutoRefresh(auth.user!.accessToken);
    }
  }

  @override
  void dispose() {
    context.read<DashboardProvider>().stopAutoRefresh();
    super.dispose();
  }

  Future<void> _refresh() async {
    final auth = context.read<AuthProvider>();
    if (auth.user != null) {
      await context.read<DashboardProvider>().fetchDashboard(auth.user!.accessToken);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final dash = context.watch<DashboardProvider>();
    final user = auth.user;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'VanTrade',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (dash.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _refresh,
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => _handleLogout(context),
          ),
        ],
      ),
      // ── Fixed bottom bar ───────────────────────────────────────────────
      bottomNavigationBar: _buildFixedBottomBar(context),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: Colors.green[700],
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Welcome row ──────────────────────────────────────────
              _buildWelcomeRow(user?.userName ?? 'Trader'),
              const SizedBox(height: 16),

              // ── Dashboard content ────────────────────────────────────
              if (dash.error != null && dash.dashboard == null)
                _buildErrorCard(dash.error!)
              else ...[
                _buildBalancePnlCard(dash.dashboard),
                const SizedBox(height: 12),
                _buildMonthCard(dash.dashboard),
                const SizedBox(height: 12),
                if ((dash.dashboard?.positions.isNotEmpty ?? false)) ...[
                  _buildSectionHeader('Open Positions',
                      Icons.show_chart, Colors.indigo),
                  const SizedBox(height: 8),
                  _buildPositionsList(dash.dashboard!.positions),
                  const SizedBox(height: 12),
                ],
                _buildSectionHeader(
                    'Active GTTs', Icons.alarm_on, Colors.deepPurple),
                const SizedBox(height: 8),
                _buildGttList(dash.dashboard?.gtts ?? []),
                const SizedBox(height: 12),
                _buildSectionHeader(
                    'Today\'s Orders', Icons.receipt_long, Colors.blueGrey),
                const SizedBox(height: 8),
                _buildOrdersList(dash.dashboard?.orders ?? []),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Welcome ──────────────────────────────────────────────────────────────
  Widget _buildWelcomeRow(String name) {
    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.green[100],
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.person, color: Colors.green[700], size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              Text(name,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        // Market status badge
        _buildMarketStatusBadge(),
      ],
    );
  }

  Widget _buildMarketStatusBadge() {
    final now = DateTime.now();
    final isWeekend = now.weekday >= 6;
    final t = now.hour * 60 + now.minute;
    final isOpen = !isWeekend && t >= 555 && t <= 930; // 9:15–15:30
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isOpen ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isOpen ? Colors.green[300]! : Colors.red[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: isOpen ? Colors.green[600] : Colors.red[400],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            isOpen ? 'Market Open' : 'Market Closed',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isOpen ? Colors.green[700] : Colors.red[600],
            ),
          ),
        ],
      ),
    );
  }

  // ── Balance + Today P&L ──────────────────────────────────────────────────
  Widget _buildBalancePnlCard(DashboardModel? data) {
    final balance = data?.availableBalance ?? 0.0;
    final pnl = data?.todayPnl ?? 0.0;
    final pnlPct = data?.todayPnlPct ?? 0.0;
    final isPositive = pnl >= 0;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.green[700]!, Colors.green[500]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Available Balance',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                Icon(Icons.account_balance_wallet,
                    color: Colors.white54, size: 18),
              ],
            ),
            const SizedBox(height: 6),
            data == null
                ? const _ShimmerBox(width: 160, height: 32)
                : Text(
                    _currency.format(balance),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Today's P&L",
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  data == null
                      ? const _ShimmerBox(width: 100, height: 20)
                      : Row(
                          children: [
                            Icon(
                              isPositive
                                  ? Icons.trending_up
                                  : Icons.trending_down,
                              color: isPositive
                                  ? Colors.greenAccent[100]
                                  : Colors.red[200],
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${isPositive ? '+' : ''}${_currency.format(pnl)}',
                              style: TextStyle(
                                color: isPositive
                                    ? Colors.greenAccent[100]
                                    : Colors.red[200],
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '(${isPositive ? '+' : ''}${pnlPct.toStringAsFixed(2)}%)',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Month P&L ────────────────────────────────────────────────────────────
  Widget _buildMonthCard(DashboardModel? data) {
    final monthPnl = data?.monthPnl ?? 0.0;
    final trades = data?.monthTrades ?? 0;
    final winRate = data?.monthWinRate ?? 0.0;
    final wins = data?.monthWins ?? 0;
    final losses = data?.monthLosses ?? 0;
    final isPositive = monthPnl >= 0;
    final monthLabel = DateFormat('MMMM yyyy').format(DateTime.now());

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, color: Colors.blue[700], size: 18),
                const SizedBox(width: 8),
                Text('$monthLabel Performance',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _buildStatBox(
                    label: 'Month P&L',
                    value: data == null
                        ? '—'
                        : '${isPositive ? '+' : ''}${_currency.format(monthPnl)}',
                    color: isPositive ? Colors.green[700]! : Colors.red[600]!,
                    icon: isPositive
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatBox(
                    label: 'Trades',
                    value: data == null ? '—' : '$trades',
                    color: Colors.blue[700]!,
                    icon: Icons.swap_horiz,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatBox(
                    label: 'Win Rate',
                    value: data == null ? '—' : '${winRate.toStringAsFixed(1)}%',
                    color: winRate >= 50
                        ? Colors.green[700]!
                        : Colors.orange[700]!,
                    icon: Icons.emoji_events_outlined,
                  ),
                ),
              ],
            ),
            if (data != null && trades > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: trades > 0 ? wins / trades : 0,
                  backgroundColor: Colors.red[100],
                  color: Colors.green[600],
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$wins wins',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.green[700],
                          fontWeight: FontWeight.w600)),
                  Text('$losses losses',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.red[600],
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatBox({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            ],
          ),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }

  // ── Positions ────────────────────────────────────────────────────────────
  Widget _buildPositionsList(List<PositionModel> positions) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: positions.map((pos) {
          final isPos = pos.pnl >= 0;
          return ListTile(
            dense: true,
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isPos ? Colors.green[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isPos ? Icons.trending_up : Icons.trending_down,
                size: 18,
                color: isPos ? Colors.green[700] : Colors.red[600],
              ),
            ),
            title: Text(pos.symbol,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(
                'Qty: ${pos.quantity}  •  Avg: ${_currency.format(pos.avgPrice)}  •  LTP: ${_currency.format(pos.ltp)}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isPos ? '+' : ''}${_currency.format(pos.pnl)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isPos ? Colors.green[700] : Colors.red[600],
                  ),
                ),
                Text(
                  '${isPos ? '+' : ''}${pos.pnlPct.toStringAsFixed(2)}%',
                  style: TextStyle(
                      fontSize: 11,
                      color: isPos ? Colors.green[600] : Colors.red[500]),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── GTTs ─────────────────────────────────────────────────────────────────
  Widget _buildGttList(List<GttModel> gtts) {
    if (gtts.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.alarm_off_outlined, size: 40, color: Colors.grey[300]),
                const SizedBox(height: 8),
                Text('No active GTTs',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14)),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: gtts.map((g) => _buildGttTile(g)).toList(),
      ),
    );
  }

  Widget _buildGttTile(GttModel g) {
    final isTwoLeg = g.gttType.toLowerCase().contains('two');
    final isSell = g.transactionType.toUpperCase() == 'SELL';
    final isTriggered = g.status.toLowerCase() == 'triggered';

    // For two-leg: triggerValues[0]=stop-loss, triggerValues[1]=target
    // For single: triggerValues[0]=trigger
    final triggers = g.triggerValues;
    String triggerText;
    if (isTwoLeg && triggers.length >= 2) {
      triggerText =
          'SL: ${_currency.format(triggers[0])}  •  Target: ${_currency.format(triggers[1])}';
    } else if (triggers.isNotEmpty) {
      triggerText = 'Trigger: ${_currency.format(triggers[0])}';
    } else {
      triggerText = 'No trigger set';
    }

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GttAnalysisScreen(gtt: g),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
        ),
        child: ListTile(
          dense: true,
          leading: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.deepPurple[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isTwoLeg ? Icons.swap_vert : Icons.alarm_on,
              size: 18,
              color: Colors.deepPurple[700],
            ),
          ),
          title: Row(
            children: [
              Text(g.symbol,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (isTwoLeg ? Colors.deepPurple : Colors.orange)
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isTwoLeg ? 'TWO-LEG' : 'SINGLE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: isTwoLeg ? Colors.deepPurple[700] : Colors.orange[700],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (isTriggered)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('TRIGGERED',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber[800])),
                ),
            ],
          ),
          subtitle: Text(
            'Qty: ${g.quantity}  •  $triggerText  •  LTP: ${_currency.format(g.lastPrice)}',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isSell ? Colors.red[50] : Colors.green[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  g.transactionType,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSell ? Colors.red[700] : Colors.green[700],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 16, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  // ── Orders ───────────────────────────────────────────────────────────────
  Widget _buildOrdersList(List<OrderModel> orders) {
    if (orders.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 40, color: Colors.grey[300]),
                const SizedBox(height: 8),
                Text('No orders today',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14)),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: orders.take(15).map((o) => _buildOrderTile(o)).toList(),
      ),
    );
  }

  Widget _buildOrderTile(OrderModel o) {
    final isBuy = o.transactionType.toUpperCase() == 'BUY';
    final statusColor = _statusColor(o.status);
    String timeStr = '';
    if (o.placedAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(o.placedAt).toLocal();
        timeStr = DateFormat('HH:mm:ss').format(dt);
      } catch (_) {}
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
      ),
      child: ListTile(
        dense: true,
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isBuy ? Colors.green[50] : Colors.red[50],
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            o.transactionType,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isBuy ? Colors.green[700] : Colors.red[700],
            ),
          ),
        ),
        title: Row(
          children: [
            Text(o.symbol,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                o.status,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: statusColor),
              ),
            ),
          ],
        ),
        subtitle: Text(
          'Qty: ${o.filledQuantity}/${o.quantity}  •  ${o.price > 0 ? _currency.format(o.price) : 'MARKET'}  •  $timeStr',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
        trailing: o.statusMessage.isNotEmpty
            ? Tooltip(
                message: o.statusMessage,
                child: Icon(Icons.info_outline,
                    size: 16, color: Colors.grey[400]),
              )
            : null,
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'COMPLETE':
        return Colors.green[700]!;
      case 'REJECTED':
      case 'CANCELLED':
        return Colors.red[600]!;
      case 'OPEN':
      case 'PENDING':
        return Colors.orange[700]!;
      case 'TRIGGER PENDING':
        return Colors.blue[700]!;
      default:
        return Colors.grey[600]!;
    }
  }

  // ── Fixed bottom bar ──────────────────────────────────────────────────
  Widget _buildFixedBottomBar(BuildContext context) {
    final analysis = context.watch<AnalysisProvider>();
    final hasAnalysis = analysis.currentAnalysis != null;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Generate Analysis button
            Expanded(
              child: Material(
                color: Colors.green[700],
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AnalysisInputScreen()),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 13),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Generate Analysis',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // View Current Analysis button
            Expanded(
              child: Material(
                color: hasAnalysis ? Colors.blue[700] : Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: hasAnalysis
                      ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AnalysisResultsScreen(),
                            ),
                          )
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.analytics_outlined,
                            color: hasAnalysis
                                ? Colors.white
                                : Colors.grey[500],
                            size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'View Analysis',
                          style: TextStyle(
                            color: hasAnalysis
                                ? Colors.white
                                : Colors.grey[500],
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800])),
      ],
    );
  }

  Widget _buildErrorCard(String error) {
    final isMarketClosed = error.toLowerCase().contains('market') ||
        error.toLowerCase().contains('token') ||
        error.toLowerCase().contains('401');
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              isMarketClosed ? Icons.access_time : Icons.wifi_off,
              size: 40,
              color: Colors.orange[400],
            ),
            const SizedBox(height: 12),
            Text(
              isMarketClosed
                  ? 'Could not load live data'
                  : 'Dashboard unavailable',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              error.replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Logout')),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      context.read<DashboardProvider>().stopAutoRefresh();
      await context.read<AuthProvider>().logout();
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }
}

// ── Shimmer placeholder ───────────────────────────────────────────────────
class _ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  const _ShimmerBox({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.3),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
