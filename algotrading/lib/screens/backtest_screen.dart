import '../theme/vt_color_scheme.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../utils/api_config.dart';
import '../widgets/vt_button.dart';

class BacktestScreen extends StatefulWidget {
  const BacktestScreen({super.key});

  @override
  State<BacktestScreen> createState() => _BacktestScreenState();
}

class _BacktestScreenState extends State<BacktestScreen> {
  // ── Config ────────────────────────────────────────────────────────
  DateTime _startDate    = DateTime(2024, 1, 1);
  DateTime _endDate      = DateTime.now().subtract(Duration(days: 1));
  double   _slMultiplier = 1.5;
  double   _targetRR     = 2.0;
  int      _minStrength  = 3;
  int      _maxHold      = 15;
  bool     _includeShort = true;
  bool     _noTimeout    = false;

  // ── UI ────────────────────────────────────────────────────────────
  bool                  _loading = false;
  String?               _error;
  Map<String, dynamic>? _report;

  // ── API call ──────────────────────────────────────────────────────
  Future<void> _run() async {
    setState(() { _loading = true; _error = null; _report = null; });
    try {
      final resp = await http.post(
        Uri.parse(ApiConfig.backtestRunUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'start_date':            _fmt(_startDate),
          'end_date':              _fmt(_endDate),
          'sl_atr_multiplier':     _slMultiplier,
          'target_rr':             _targetRR,
          'min_signal_strength':   _minStrength,
          'max_hold_bars':         _maxHold,
          'no_timeout':            _noTimeout,
          'include_short':         _includeShort,
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
    );
    if (picked != null && mounted) {
      setState(() => isStart ? _startDate = picked : _endDate = picked);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text('Strategy Backtest', style: AppTextStyles.h2),
      ),
      body: _loading
          ? _buildLoading()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(Sp.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildConfigCard(),
                  const SizedBox(height: Sp.md),
                  VtButton(
                    label: 'Run Backtest',
                    icon: const Icon(Icons.play_arrow_rounded,
                        size: 18, color: Colors.white),
                    onPressed: _run,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Sp.base),
                    _buildError(),
                  ],
                  if (_report != null) ...[
                    const SizedBox(height: Sp.lg),
                    _buildReport(),
                  ],
                ],
              ),
            ),
    );
  }

  // ── Loading ───────────────────────────────────────────────────────
  Widget _buildLoading() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(color: context.vt.accentGreen),
        const SizedBox(height: Sp.lg),
        Text('Running backtest on Nifty 50…', style: AppTextStyles.bodySecondary),
        const SizedBox(height: Sp.xs),
        Text('This may take up to 5 minutes', style: AppTextStyles.caption),
      ],
    ),
  );

  // ── Config card ───────────────────────────────────────────────────
  Widget _buildConfigCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Parameters', style: AppTextStyles.h3),
        const SizedBox(height: Sp.md),
        Row(
          children: [
            Expanded(child: _dateTile('Start', _startDate, () => _pickDate(true))),
            const SizedBox(width: Sp.sm),
            Expanded(child: _dateTile('End', _endDate, () => _pickDate(false))),
          ],
        ),
        const SizedBox(height: Sp.base),
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
        const SizedBox(height: Sp.xs),
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
          padding: const EdgeInsets.symmetric(
              horizontal: Sp.md, vertical: Sp.sm),
          decoration: BoxDecoration(
            color: context.vt.surface0,
            borderRadius: BorderRadius.circular(Rad.md),
            border: Border.all(color: context.vt.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.caption),
              const SizedBox(height: Sp.xs),
              Text(_fmt(date),
                  style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  Widget _sliderRow(
    String label, double value, double min, double max, int divisions,
    String display, ValueChanged<double> onChanged,
  ) =>
      Padding(
        padding: EdgeInsets.only(bottom: Sp.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: AppTextStyles.bodySecondary),
                Text(display,
                    style: AppTextStyles.mono.copyWith(
                        color: context.vt.accentGreen,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ],
        ),
      );

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTextStyles.bodySecondary),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      );

  // ── Error ─────────────────────────────────────────────────────────
  Widget _buildError() => Container(
    padding: EdgeInsets.all(Sp.md),
    decoration: BoxDecoration(
      color: context.vt.dangerDim,
      borderRadius: BorderRadius.circular(Rad.md),
      border: Border.all(color: context.vt.danger.withValues(alpha: 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline_rounded,
            color: context.vt.danger, size: 18),
        SizedBox(width: Sp.sm),
        Expanded(
          child: Text(_error!,
              style: AppTextStyles.caption.copyWith(color: context.vt.danger)),
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

    final winRate = (s['win_rate_pct']       as num?)?.toDouble() ?? 0.0;
    final pf      = (s['profit_factor']      as num?)?.toDouble() ?? 0.0;
    final ev      = (s['expected_value_pct'] as num?)?.toDouble() ?? 0.0;
    final maxDD   = (s['max_drawdown_pct']   as num?)?.toDouble() ?? 0.0;
    final total   = (s['total_trades']       as num?)?.toInt()    ?? 0;

    Color tiered(double val, double good, double ok) =>
        val >= good ? context.vt.accentGreen
        : val >= ok ? context.vt.warning
        : context.vt.danger;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Results — $total trades', style: AppTextStyles.h3),
        SizedBox(height: Sp.sm),

        Row(children: [
          _metricCard('Win Rate', '${winRate.toStringAsFixed(1)}%',
              tiered(winRate, 50, 35)),
          const SizedBox(width: Sp.sm),
          _metricCard('Profit Factor', pf >= 999 ? '∞' : pf.toStringAsFixed(2),
              tiered(pf, 1.5, 1.0)),
        ]),
        SizedBox(height: Sp.sm),
        Row(children: [
          _metricCard('EV / Trade',
              '${ev >= 0 ? '+' : ''}${ev.toStringAsFixed(3)}%',
              ev >= 0 ? context.vt.accentGreen : context.vt.danger),
          const SizedBox(width: Sp.sm),
          _metricCard('Max Drawdown', '${maxDD.toStringAsFixed(1)}%',
              tiered(100 - maxDD, 80, 60)),
        ]),
        SizedBox(height: Sp.md),

        _card(child: Column(children: [
          _metricRow('Wins / Losses / Timeouts',
              '${s['win_trades']} / ${s['loss_trades']} / ${s['timeout_trades']}'),
          _metricRow('Avg Win',
              '${(s['avg_win_pct'] as num?)?.toStringAsFixed(2) ?? '—'}%',
              color: context.vt.accentGreen),
          _metricRow('Avg Loss',
              '${(s['avg_loss_pct'] as num?)?.toStringAsFixed(2) ?? '—'}%',
              color: context.vt.danger),
          _metricRow('Win/Loss PF',
              (s['win_loss_profit_factor'] as num?)?.toStringAsFixed(2) ?? '—'),
          _metricRow('Sharpe Ratio',
              (s['sharpe_ratio'] as num?)?.toStringAsFixed(3) ?? '—'),
          _metricRow('Best Trade',
              '${(s['best_trade_pct'] as num?)?.toStringAsFixed(2) ?? '—'}%',
              color: context.vt.accentGreen),
          _metricRow('Worst Trade',
              '${(s['worst_trade_pct'] as num?)?.toStringAsFixed(2) ?? '—'}%',
              color: context.vt.danger),
          _metricRow('Symbols Tested', '${s['symbols_tested']}'),
        ])),

        if (bySignal.isNotEmpty) ...[
          SizedBox(height: Sp.md),
          Text('By Direction', style: AppTextStyles.h3),
          SizedBox(height: Sp.sm),
          _card(child: Column(
            children: bySignal.entries.map((e) {
              final g  = e.value as Map<String, dynamic>;
              final wr = (g['win_rate_pct'] as num?)?.toDouble() ?? 0.0;
              return _metricRow(
                e.key,
                '${g['trades']} trades | WR ${wr.toStringAsFixed(1)}%'
                ' | avg ${(g['avg_pnl_pct'] as num?)?.toStringAsFixed(2)}%',
                color: wr >= 50 ? context.vt.accentGreen : context.vt.textSecondary,
              );
            }).toList(),
          )),
        ],

        if (byStrength.isNotEmpty) ...[
          SizedBox(height: Sp.md),
          Text('By Signal Strength', style: AppTextStyles.h3),
          SizedBox(height: Sp.sm),
          _card(child: Column(children: _buildStrengthRows(byStrength))),
        ],

        if (bySymbol.isNotEmpty) ...[
          SizedBox(height: Sp.md),
          Text('Top Symbols (by P&L)', style: AppTextStyles.h3),
          SizedBox(height: Sp.sm),
          _symbolTable(bySymbol.take(8).toList()),
          SizedBox(height: Sp.md),
          Text('Bottom Symbols (by P&L)', style: AppTextStyles.h3),
          SizedBox(height: Sp.sm),
          _symbolTable(bySymbol.reversed.take(5).toList()),
        ],

        const SizedBox(height: Sp.xxxl),
      ],
    );
  }

  List<Widget> _buildStrengthRows(Map<String, dynamic> byStrength) {
    final entries = byStrength.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return entries.map((e) {
      final g      = e.value as Map<String, dynamic>;
      final wr     = (g['win_rate_pct'] as num?)?.toDouble() ?? 0.0;
      final trades = (g['trades']       as num?)?.toInt()    ?? 0;
      final color  = wr >= 50 ? context.vt.accentGreen
                   : wr >= 35 ? context.vt.warning
                   : context.vt.danger;

      return Padding(
        padding: EdgeInsets.symmetric(vertical: Sp.xs),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: context.vt.accentGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Rad.sm),
              ),
              child: Center(
                child: Text(e.key,
                    style: AppTextStyles.label.copyWith(
                        color: context.vt.accentGreen)),
              ),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('$trades trades', style: AppTextStyles.caption),
                      Text('WR ${wr.toStringAsFixed(1)}%',
                          style: AppTextStyles.caption.copyWith(
                              color: color, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  SizedBox(height: Sp.xs),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Rad.pill),
                    child: LinearProgressIndicator(
                      value: wr / 100,
                      backgroundColor: context.vt.divider,
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
        Row(children: [
          Expanded(flex: 3,
              child: Text('Symbol',
                  style: AppTextStyles.caption.copyWith(
                      color: context.vt.textTertiary,
                      fontWeight: FontWeight.w700))),
          Expanded(flex: 2,
              child: Text('Trades',
                  style: AppTextStyles.caption.copyWith(
                      color: context.vt.textTertiary),
                  textAlign: TextAlign.center)),
          Expanded(flex: 2,
              child: Text('WR %',
                  style: AppTextStyles.caption.copyWith(
                      color: context.vt.textTertiary),
                  textAlign: TextAlign.center)),
          Expanded(flex: 2,
              child: Text('P&L %',
                  style: AppTextStyles.caption.copyWith(
                      color: context.vt.textTertiary),
                  textAlign: TextAlign.right)),
        ]),
        Divider(color: context.vt.divider, height: Sp.sm),
        ...rows.map((r) {
          final row = r as Map<String, dynamic>;
          final pnl = (row['total_pnl_pct'] as num?)?.toDouble() ?? 0.0;
          final wr  = (row['win_rate_pct']  as num?)?.toDouble() ?? 0.0;
          final wrColor = wr >= 50 ? context.vt.accentGreen
                        : wr >= 35 ? context.vt.warning
                        : context.vt.danger;
          return Padding(
            padding: EdgeInsets.symmetric(vertical: Sp.xs),
            child: Row(children: [
              Expanded(flex: 3,
                  child: Text(row['symbol']?.toString() ?? '',
                      style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w600))),
              Expanded(flex: 2,
                  child: Text('${row['trades']}',
                      style: AppTextStyles.caption,
                      textAlign: TextAlign.center)),
              Expanded(flex: 2,
                  child: Text('${wr.toStringAsFixed(1)}%',
                      style: AppTextStyles.caption.copyWith(color: wrColor),
                      textAlign: TextAlign.center)),
              Expanded(flex: 2,
                  child: Text('${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(1)}%',
                      style: AppTextStyles.monoSm.copyWith(
                          color: pnl >= 0 ? context.vt.accentGreen : context.vt.danger,
                          fontWeight: FontWeight.w700),
                      textAlign: TextAlign.right)),
            ]),
          );
        }),
      ],
    ),
  );

  // ── Helpers ───────────────────────────────────────────────────────
  Widget _card({required Widget child}) => Container(
    padding: EdgeInsets.all(Sp.md),
    decoration: BoxDecoration(
      color: context.vt.surface1,
      borderRadius: BorderRadius.circular(Rad.lg),
      border: Border.all(color: context.vt.divider),
    ),
    child: child,
  );

  Widget _metricCard(String label, String value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Sp.md, vertical: Sp.md),
      decoration: BoxDecoration(
        color: context.vt.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: Sp.xs),
          Text(value,
              style: AppTextStyles.monoLg.copyWith(
                  color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    ),
  );

  Widget _metricRow(String label, String value, {Color? color}) {
    final c = color ?? context.vt.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: AppTextStyles.body),
          ),
          const SizedBox(width: Sp.sm),
          Text(value,
              style: AppTextStyles.mono.copyWith(
                  color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
