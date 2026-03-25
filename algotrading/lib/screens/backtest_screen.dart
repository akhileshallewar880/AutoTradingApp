import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../utils/api_config.dart';

class BacktestScreen extends StatefulWidget {
  const BacktestScreen({super.key});

  @override
  State<BacktestScreen> createState() => _BacktestScreenState();
}

class _BacktestScreenState extends State<BacktestScreen> {
  static const _bg      = Color(0xFF0D1117);
  static const _surface = Color(0xFF161B22);
  static const _border  = Color(0xFF30363D);
  static const _accent  = Color(0xFF58A6FF);
  static const _green   = Color(0xFF3FB950);
  static const _red     = Color(0xFFF85149);

  // ── Config ────────────────────────────────────────────────────────
  DateTime _startDate = DateTime(2024, 1, 1);
  DateTime _endDate   = DateTime.now().subtract(const Duration(days: 1));
  double   _slMultiplier = 1.5;
  double   _targetRR     = 2.0;
  int      _minStrength  = 3;
  int      _maxHold      = 15;
  bool     _includeShort = true;
  bool     _noTimeout    = false;

  // ── UI ────────────────────────────────────────────────────────────
  bool                   _loading = false;
  String?                _error;
  Map<String, dynamic>?  _report;

  // ── API call ──────────────────────────────────────────────────────
  Future<void> _run() async {
    setState(() { _loading = true; _error = null; _report = null; });
    try {
      final resp = await http.post(
        Uri.parse(ApiConfig.backtestRunUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'start_date':          _fmt(_startDate),
          'end_date':            _fmt(_endDate),
          'sl_atr_multiplier':   _slMultiplier,
          'target_rr':           _targetRR,
          'min_signal_strength': _minStrength,
          'max_hold_bars':       _maxHold,
          'no_timeout':          _noTimeout,
          'include_short':       _includeShort,
          'include_trades_detail': false,
        }),
      ).timeout(ApiConfig.backtestTimeout);

      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() => _report = jsonDecode(resp.body) as Map<String, dynamic>);
      } else {
        setState(() => _error = _extractDetail(resp.body));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _extractDetail(String body) {
    try {
      final d = jsonDecode(body);
      return (d as Map)['detail']?.toString() ?? 'Server error';
    } catch (_) {
      return body.length > 200 ? body.substring(0, 200) : body;
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: _accent),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => isStart ? _startDate = picked : _endDate = picked);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Strategy Backtest',
            style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: _loading
          ? _buildLoading()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildConfigCard(),
                  const SizedBox(height: 12),
                  _buildRunButton(),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _buildError(),
                  ],
                  if (_report != null) ...[
                    const SizedBox(height: 20),
                    _buildReport(),
                  ],
                ],
              ),
            ),
    );
  }

  // ── Loading ───────────────────────────────────────────────────────
  Widget _buildLoading() => const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(color: _accent),
        SizedBox(height: 20),
        Text('Running backtest on Nifty 50…',
            style: TextStyle(color: Colors.white70)),
        SizedBox(height: 8),
        Text('This may take up to 5 minutes',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
      ],
    ),
  );

  // ── Config card ───────────────────────────────────────────────────
  Widget _buildConfigCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Parameters'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _dateTile('Start', _startDate, () => _pickDate(true))),
            const SizedBox(width: 10),
            Expanded(child: _dateTile('End', _endDate, () => _pickDate(false))),
          ],
        ),
        const SizedBox(height: 16),
        _sliderRow('SL ATR Multiplier', _slMultiplier, 0.5, 4.0, 7,
            '${_slMultiplier.toStringAsFixed(1)}×',
            (v) => setState(() => _slMultiplier = v)),
        _sliderRow('Target RR', _targetRR, 0.5, 5.0, 9,
            '${_targetRR.toStringAsFixed(1)}:1',
            (v) => setState(() => _targetRR = v)),
        _sliderRow('Min Signal Strength', _minStrength.toDouble(), 1, 5, 4,
            '$_minStrength / 5',
            (v) => setState(() => _minStrength = v.round())),
        _sliderRow('Max Hold Days', _maxHold.toDouble(), 1, 60, 59,
            '$_maxHold d',
            (v) => setState(() => _maxHold = v.round())),
        const SizedBox(height: 8),
        _switchRow('Include SHORT signals', _includeShort,
            (v) => setState(() => _includeShort = v)),
        _switchRow('No timeout exits (SL/target only)', _noTimeout,
            (v) => setState(() => _noTimeout = v)),
      ],
    ),
  );

  Widget _dateTile(String label, DateTime date, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
              const SizedBox(height: 4),
              Text(_fmt(date),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );

  Widget _sliderRow(
    String label, double value, double min, double max, int divisions,
    String display, ValueChanged<double> onChanged,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label,
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                Text(display,
                    style: const TextStyle(
                        color: _accent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: _accent,
                inactiveTrackColor: _border,
                thumbColor: _accent,
                overlayColor: _accent.withAlpha(30),
                trackHeight: 3,
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      );

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: _green,
              inactiveTrackColor: _border,
            ),
          ],
        ),
      );

  // ── Run button ────────────────────────────────────────────────────
  Widget _buildRunButton() => ElevatedButton.icon(
    icon: const Icon(Icons.play_arrow_rounded),
    label: const Text('Run Backtest',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    style: ElevatedButton.styleFrom(
      backgroundColor: _accent,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    onPressed: _run,
  );

  // ── Error ─────────────────────────────────────────────────────────
  Widget _buildError() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _red.withAlpha(25),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _red.withAlpha(100)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: _red, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(_error!,
              style: const TextStyle(color: _red, fontSize: 13)),
        ),
      ],
    ),
  );

  // ── Full report ───────────────────────────────────────────────────
  Widget _buildReport() {
    final s          = _report!['summary']    as Map<String, dynamic>;
    final bySignal   = (_report!['by_signal']   as Map<String, dynamic>?) ?? {};
    final byStrength = (_report!['by_strength'] as Map<String, dynamic>?) ?? {};
    final bySymbol   = (_report!['by_symbol']   as List<dynamic>?) ?? [];

    final winRate = (s['win_rate_pct']        as num?)?.toDouble() ?? 0.0;
    final pf      = (s['profit_factor']       as num?)?.toDouble() ?? 0.0;
    final ev      = (s['expected_value_pct']  as num?)?.toDouble() ?? 0.0;
    final maxDD   = (s['max_drawdown_pct']    as num?)?.toDouble() ?? 0.0;
    final total   = (s['total_trades']        as num?)?.toInt()    ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('Results — $total trades'),
        const SizedBox(height: 10),

        // Big 4 cards
        Row(children: [
          _metricCard('Win Rate', '${winRate.toStringAsFixed(1)}%',
              winRate >= 50 ? _green : winRate >= 35 ? Colors.orange : _red),
          const SizedBox(width: 8),
          _metricCard('Profit Factor', pf >= 999 ? '∞' : pf.toStringAsFixed(2),
              pf >= 1.5 ? _green : pf >= 1.0 ? Colors.orange : _red),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _metricCard('EV / Trade',
              '${ev >= 0 ? '+' : ''}${ev.toStringAsFixed(3)}%',
              ev >= 0 ? _green : _red),
          const SizedBox(width: 8),
          _metricCard('Max Drawdown', '${maxDD.toStringAsFixed(1)}%',
              maxDD < 20 ? _green : maxDD < 40 ? Colors.orange : _red),
        ]),
        const SizedBox(height: 12),

        // Detail metrics
        _card(child: Column(children: [
          _metricRow('Wins / Losses / Timeouts',
              '${s['win_trades']} / ${s['loss_trades']} / ${s['timeout_trades']}'),
          _metricRow('Avg Win',
              '${(s['avg_win_pct'] as num?)?.toStringAsFixed(2) ?? '—'}%',
              color: _green),
          _metricRow('Avg Loss',
              '${(s['avg_loss_pct'] as num?)?.toStringAsFixed(2) ?? '—'}%',
              color: _red),
          _metricRow('Win/Loss PF',
              (s['win_loss_profit_factor'] as num?)?.toStringAsFixed(2) ?? '—'),
          _metricRow('Sharpe Ratio',
              (s['sharpe_ratio'] as num?)?.toStringAsFixed(3) ?? '—'),
          _metricRow('Best Trade',
              '${(s['best_trade_pct'] as num?)?.toStringAsFixed(2) ?? '—'}%',
              color: _green),
          _metricRow('Worst Trade',
              '${(s['worst_trade_pct'] as num?)?.toStringAsFixed(2) ?? '—'}%',
              color: _red),
          _metricRow('Symbols Tested', '${s['symbols_tested']}'),
        ])),

        // By signal direction
        if (bySignal.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionLabel('By Direction'),
          const SizedBox(height: 8),
          _card(child: Column(
            children: bySignal.entries.map((e) {
              final g  = e.value as Map<String, dynamic>;
              final wr = (g['win_rate_pct'] as num?)?.toDouble() ?? 0.0;
              return _metricRow(
                e.key,
                '${g['trades']} trades | WR ${wr.toStringAsFixed(1)}%'
                ' | avg ${(g['avg_pnl_pct'] as num?)?.toStringAsFixed(2)}%',
                color: wr >= 50 ? _green : Colors.white70,
              );
            }).toList(),
          )),
        ],

        // By signal strength
        if (byStrength.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionLabel('By Signal Strength'),
          const SizedBox(height: 8),
          _card(child: Column(
            children: _buildStrengthRows(byStrength),
          )),
        ],

        // Top symbols
        if (bySymbol.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionLabel('Top Symbols (by P&L)'),
          const SizedBox(height: 8),
          _symbolTable(bySymbol.take(8).toList()),
          const SizedBox(height: 12),
          _sectionLabel('Bottom Symbols (by P&L)'),
          const SizedBox(height: 8),
          _symbolTable(bySymbol.reversed.take(5).toList()),
        ],

        const SizedBox(height: 32),
      ],
    );
  }

  List<Widget> _buildStrengthRows(Map<String, dynamic> byStrength) {
    final entries = byStrength.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return entries.map((e) {
      final g      = e.value as Map<String, dynamic>;
      final wr     = (g['win_rate_pct'] as num?)?.toDouble() ?? 0.0;
      final trades = (g['trades'] as num?)?.toInt() ?? 0;
      final color  = wr >= 50 ? _green : wr >= 35 ? Colors.orange : _red;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: _accent.withAlpha(30),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(e.key,
                    style: const TextStyle(
                        color: _accent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('$trades trades',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                      Text('WR ${wr.toStringAsFixed(1)}%',
                          style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: wr / 100,
                      backgroundColor: _border,
                      color: color,
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _symbolTable(List<dynamic> rows) => _card(
    child: Column(
      children: [
        Row(children: const [
          Expanded(flex: 3, child: Text('Symbol',
              style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold))),
          Expanded(flex: 2, child: Text('Trades',
              style: TextStyle(color: Colors.white38, fontSize: 11),
              textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text('WR %',
              style: TextStyle(color: Colors.white38, fontSize: 11),
              textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text('P&L %',
              style: TextStyle(color: Colors.white38, fontSize: 11),
              textAlign: TextAlign.right)),
        ]),
        const Divider(color: _border, height: 10),
        ...rows.map((r) {
          final row = r as Map<String, dynamic>;
          final pnl = (row['total_pnl_pct'] as num?)?.toDouble() ?? 0.0;
          final wr  = (row['win_rate_pct']  as num?)?.toDouble() ?? 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(flex: 3,
                  child: Text(row['symbol']?.toString() ?? '',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500))),
              Expanded(flex: 2,
                  child: Text('${row['trades']}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      textAlign: TextAlign.center)),
              Expanded(flex: 2,
                  child: Text('${wr.toStringAsFixed(1)}%',
                      style: TextStyle(
                          color: wr >= 50
                              ? _green
                              : wr >= 35
                                  ? Colors.orange
                                  : _red,
                          fontSize: 12),
                      textAlign: TextAlign.center)),
              Expanded(flex: 2,
                  child: Text('${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(1)}%',
                      style: TextStyle(
                          color: pnl >= 0 ? _green : _red,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.right)),
            ]),
          );
        }),
      ],
    ),
  );

  // ── Helpers ───────────────────────────────────────────────────────
  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _border),
    ),
    child: child,
  );

  Widget _metricCard(String label, String value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      ),
    ),
  );

  Widget _metricRow(String label, String value,
      {Color color = Colors.white}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold));
}
