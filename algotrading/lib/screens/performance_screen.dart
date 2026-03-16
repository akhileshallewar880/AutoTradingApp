import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../providers/auth_provider.dart';
import '../utils/api_config.dart';

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchPerformance());
  }

  Future<void> _fetchPerformance() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(ApiConfig.monthlyPerformanceUrl).replace(
        queryParameters: {
          'access_token': auth.user!.accessToken,
          'api_key': auth.user!.apiKey,
          'user_id': auth.user!.userId,
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        setState(() => _data = jsonDecode(response.body));
      } else {
        final body = jsonDecode(response.body);
        setState(() => _error = body['detail'] ?? 'Failed to load performance');
      }
    } catch (e) {
      setState(() => _error = 'Network error: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Performance', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPerformance,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _data == null
                  ? const Center(child: Text('No data'))
                  : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red[700], fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _fetchPerformance,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final d = _data!;
    final totalPnl = (d['total_pnl'] as num).toDouble();
    final netPnl = (d['net_pnl'] as num).toDouble();
    final isProfit = netPnl >= 0;

    return RefreshIndicator(
      onRefresh: _fetchPerformance,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Date label ────────────────────────────────────────────────
            Center(
              child: Text(
                d['month'] ?? '',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Today\'s Trading Performance',
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            ),
            const SizedBox(height: 16),

            // ── Net P&L hero card ─────────────────────────────────────────
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: isProfit
                        ? [Colors.green[700]!, Colors.green[500]!]
                        : [Colors.red[700]!, Colors.red[500]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      'Net P&L (After Charges)',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${isProfit ? '+' : ''}${_currency.format(netPnl)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _heroStat('Gross P&L', _currency.format(totalPnl)),
                        _heroDivider(),
                        _heroStat('Charges', '- ${_currency.format((d['total_charges'] as num).toDouble())}'),
                        _heroDivider(),
                        _heroStat('Win Rate', '${d['win_rate']}%'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Profit / Loss / Charges row ──────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _statCard(
                    label: 'Gross Profit',
                    value: _currency.format((d['gross_profit'] as num).toDouble()),
                    icon: Icons.trending_up,
                    color: Colors.green[700]!,
                    bg: Colors.green[50]!,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statCard(
                    label: 'Gross Loss',
                    value: _currency.format((d['gross_loss'] as num).toDouble()),
                    icon: Icons.trending_down,
                    color: Colors.red[700]!,
                    bg: Colors.red[50]!,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _statCard(
                    label: 'Total Charges',
                    value: _currency.format((d['total_charges'] as num).toDouble()),
                    icon: Icons.receipt_long,
                    color: Colors.orange[700]!,
                    bg: Colors.orange[50]!,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statCard(
                    label: 'Unrealized P&L',
                    value: _currency.format((d['unrealized_pnl'] as num).toDouble()),
                    icon: Icons.access_time,
                    color: Colors.blue[700]!,
                    bg: Colors.blue[50]!,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Trade stats ───────────────────────────────────────────────
            _sectionHeader('Trade Statistics', Icons.bar_chart),
            const SizedBox(height: 10),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _tradeRow('Total Trades Executed', '${d['total_trades']}'),
                    const Divider(height: 20),
                    _tradeRow('Winning Positions', '${d['winning_positions']}',
                        valueColor: Colors.green[700]),
                    const Divider(height: 20),
                    _tradeRow('Losing Positions', '${d['losing_positions']}',
                        valueColor: Colors.red[600]),
                    const Divider(height: 20),
                    _tradeRow('Realized P&L',
                        _currency.format((d['realized_pnl'] as num).toDouble()),
                        valueColor: (d['realized_pnl'] as num) >= 0
                            ? Colors.green[700]
                            : Colors.red[600]),
                    const Divider(height: 20),
                    _tradeRow('Max Drawdown',
                        _currency.format((d['max_drawdown'] as num).toDouble()),
                        valueColor: Colors.red[600]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Charges breakdown info ────────────────────────────────────
            _sectionHeader('Charges Breakdown (Est.)', Icons.info_outline),
            const SizedBox(height: 10),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _chargeInfoRow('Brokerage', 'Min(₹20, 0.03% of turnover) per order'),
                    _chargeInfoRow('STT', '0.025% on sell turnover (intraday)'),
                    _chargeInfoRow('Exchange charges', '0.00345% of turnover (NSE)'),
                    _chargeInfoRow('SEBI charges', '₹10 per crore of turnover'),
                    _chargeInfoRow('GST', '18% on brokerage + exchange charges'),
                    _chargeInfoRow('Stamp duty', '0.003% on buy turnover'),
                    const SizedBox(height: 8),
                    Text(
                      '* Charges are estimated. Actual amounts may vary slightly.',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helper widgets ─────────────────────────────────────────────────────────

  Widget _heroStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  Widget _heroDivider() {
    return Container(width: 1, height: 32, color: Colors.white24);
  }

  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required Color bg,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 11, color: color)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tradeRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: valueColor ?? Colors.grey[900],
          ),
        ),
      ],
    );
  }

  Widget _chargeInfoRow(String label, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[800])),
          ),
          Expanded(
            child: Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[700]),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[800]),
        ),
      ],
    );
  }
}
