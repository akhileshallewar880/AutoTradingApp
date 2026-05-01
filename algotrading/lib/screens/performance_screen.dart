import '../theme/vt_color_scheme.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../providers/auth_provider.dart';
import '../services/streak_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../utils/api_config.dart';
import '../widgets/section_header.dart';
import '../widgets/vt_button.dart';
import '../widgets/vt_card.dart';

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
  bool _chargesExpanded = false;
  int _streakDays = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchPerformance();
      StreakService.instance.currentStreak().then(
        (v) { if (mounted) setState(() => _streakDays = v); },
      );
    });
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
      final response =
          await http.get(uri).timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        setState(() => _data = jsonDecode(response.body));
      } else {
        final body = jsonDecode(response.body);
        setState(() =>
            _error = body['detail'] ?? 'Failed to load performance');
      }
    } catch (e) {
      setState(() => _error =
          'Network error: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text('Performance', style: AppTextStyles.h2),
      ),
      body: _isLoading
          ? Center(
              child:
                  CircularProgressIndicator(color: context.vt.accentGreen))
          : _error != null
              ? _buildError()
              : _data == null
                  ? Center(
                      child: Text('No data', style: AppTextStyles.bodySecondary))
                  : _buildContent(),
    );
  }

  // ── Error state ────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(Sp.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 44, color: context.vt.danger),
            SizedBox(height: Sp.md),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySecondary
                  .copyWith(color: context.vt.danger),
            ),
            SizedBox(height: Sp.xl),
            VtButton(
              label: 'Retry',
              onPressed: _fetchPerformance,
              variant: VtButtonVariant.secondary,
              icon: Icon(Icons.refresh_rounded,
                  size: 16, color: context.vt.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  // ── Main content ───────────────────────────────────────────────────────────

  Widget _buildContent() {
    final d = _data!;
    final totalPnl = (d['total_pnl'] as num).toDouble();
    final netPnl = (d['net_pnl'] as num).toDouble();
    final isProfit = netPnl >= 0;
    final heroColor = isProfit ? context.vt.accentGreen : context.vt.danger;
    final winRate = (d['win_rate'] as num).toDouble();

    return RefreshIndicator(
      color: context.vt.accentGreen,
      backgroundColor: context.vt.surface1,
      onRefresh: _fetchPerformance,
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            Sp.base, Sp.sm, Sp.base, Sp.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Month label ────────────────────────────────────────────────
            Center(
              child: Text(
                d['month'] ?? '',
                style: AppTextStyles.bodySecondary
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(height: 2),
            Center(
              child: Text('Monthly Trading Performance',
                  style: AppTextStyles.caption),
            ),
            SizedBox(height: Sp.base),

            // ── Net P&L hero ───────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(Sp.xl),
              decoration: BoxDecoration(
                color: context.vt.surface1,
                borderRadius: BorderRadius.circular(Rad.lg),
                border: Border.all(
                    color: heroColor.withValues(alpha: 0.3)),
                boxShadow: isProfit
                    ? AppColors.greenGlow
                    : AppColors.dangerGlow,
              ),
              child: Column(
                children: [
                  Text('Net P&L (After Charges)',
                      style: AppTextStyles.caption),
                  SizedBox(height: Sp.sm),
                  Text(
                    '${isProfit ? '+' : ''}${_currency.format(netPnl)}',
                    style: AppTextStyles.display.copyWith(
                        color: heroColor, fontSize: 36),
                  ),
                  SizedBox(height: Sp.base),
                  Divider(color: context.vt.divider, height: 1),
                  SizedBox(height: Sp.base),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _heroStat('Gross P&L', _currency.format(totalPnl),
                          totalPnl >= 0
                              ? context.vt.accentGreen
                              : context.vt.danger),
                      Container(
                          width: 1,
                          height: 32,
                          color: context.vt.divider),
                      _heroStat(
                        'Charges',
                        '−${_currency.format((d['total_charges'] as num).toDouble())}',
                        context.vt.warning,
                      ),
                      Container(
                          width: 1,
                          height: 32,
                          color: context.vt.divider),
                      _heroStat(
                        'Win Rate',
                        '${winRate.toStringAsFixed(0)}%',
                        winRate >= 60
                            ? context.vt.accentGreen
                            : winRate >= 40
                                ? context.vt.warning
                                : context.vt.danger,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: Sp.base),

            // ── Win Rate Arc ───────────────────────────────────────────────
            _buildWinRateCard(winRate, d),
            SizedBox(height: Sp.base),

            // ── Stat cards 2x2 ─────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _statTile(
                    label: 'Gross Profit',
                    value: _currency
                        .format((d['gross_profit'] as num).toDouble()),
                    color: context.vt.accentGreen,
                    icon: Icons.trending_up_rounded,
                  ),
                ),
                SizedBox(width: Sp.sm),
                Expanded(
                  child: _statTile(
                    label: 'Gross Loss',
                    value: _currency
                        .format((d['gross_loss'] as num).toDouble()),
                    color: context.vt.danger,
                    icon: Icons.trending_down_rounded,
                  ),
                ),
              ],
            ),
            SizedBox(height: Sp.sm),
            Row(
              children: [
                Expanded(
                  child: _statTile(
                    label: 'Unrealized P&L',
                    value: _currency
                        .format((d['unrealized_pnl'] as num).toDouble()),
                    color: context.vt.accentPurple,
                    icon: Icons.access_time_rounded,
                  ),
                ),
                SizedBox(width: Sp.sm),
                Expanded(
                  child: _statTile(
                    label: 'Max Drawdown',
                    value: _currency
                        .format((d['max_drawdown'] as num).toDouble()),
                    color: context.vt.warning,
                    icon: Icons.waterfall_chart_rounded,
                  ),
                ),
              ],
            ),
            SizedBox(height: Sp.base),

            // ── Trade stats ────────────────────────────────────────────────
            VtCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    title: 'Trade Statistics',
                    paddingTop: 0,
                    paddingBottom: Sp.md,
                  ),
                  _tradeRow('Total Trades Executed',
                      '${d['total_trades']}', context.vt.textPrimary),
                  Divider(height: Sp.base, color: context.vt.divider),
                  _tradeRow('Winning Positions',
                      '${d['winning_positions']}', context.vt.accentGreen),
                  Divider(height: Sp.base, color: context.vt.divider),
                  _tradeRow('Losing Positions',
                      '${d['losing_positions']}', context.vt.danger),
                  Divider(height: Sp.base, color: context.vt.divider),
                  _tradeRow(
                    'Realized P&L',
                    _currency
                        .format((d['realized_pnl'] as num).toDouble()),
                    (d['realized_pnl'] as num) >= 0
                        ? context.vt.accentGreen
                        : context.vt.danger,
                  ),
                ],
              ),
            ),
            const SizedBox(height: Sp.base),

            // ── Charges breakdown (collapsible) ────────────────────────────
            VtCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => setState(
                        () => _chargesExpanded = !_chargesExpanded),
                    child: Row(
                      children: [
                        Expanded(
                          child: SectionHeader(
                            title: 'Charges Breakdown',
                            paddingTop: 0,
                            paddingBottom: 0,
                          ),
                        ),
                        AnimatedRotation(
                          turns: _chargesExpanded ? 0.5 : 0,
                          duration: Duration(milliseconds: 250),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: context.vt.textSecondary,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: Sp.md),
                        Divider(
                            height: 1, color: context.vt.divider),
                        SizedBox(height: Sp.md),
                        Text('F&O Options Rate Card',
                            style: AppTextStyles.caption.copyWith(
                                color: context.vt.accentPurple,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: Sp.sm),
                        _chargeRow('Brokerage',
                            '₹20 flat per executed order (Zerodha)'),
                        _chargeRow('STT',
                            '0.0125% on sell premium turnover'),
                        _chargeRow('Exchange charges',
                            '0.053% of premium turnover (NSE options)'),
                        _chargeRow('SEBI charges',
                            '₹10 per crore of turnover'),
                        _chargeRow('GST',
                            '18% on brokerage + exchange charges'),
                        _chargeRow('Stamp duty',
                            '0.003% on buy premium turnover'),
                        SizedBox(height: Sp.sm),
                        Text(
                          '* Calculated using Zerodha published F&O rate card. '
                          'Actual charges deducted at source may vary by a few rupees.',
                          style: AppTextStyles.caption
                              .copyWith(color: context.vt.textTertiary),
                        ),
                      ],
                    ),
                    crossFadeState: _chargesExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 280),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Sp.base),

            // ── Milestones ─────────────────────────────────────────────────
            _buildMilestonesSection(_data!),
          ],
        ),
      ),
    );
  }

  Widget _buildMilestonesSection(Map<String, dynamic> d) {
    final totalTrades = (d['total_trades'] as num?)?.toInt() ?? 0;
    final winningPos  = (d['winning_positions'] as num?)?.toInt() ?? 0;

    final badges = [
      _MilestoneBadge(
        icon: Icons.rocket_launch_rounded,
        title: 'First Trade',
        subtitle: 'Execute your first live trade',
        unlocked: totalTrades > 0,
        color: context.vt.accentGreen,
      ),
      _MilestoneBadge(
        icon: Icons.local_fire_department_rounded,
        title: 'Streak Master',
        subtitle: '7 consecutive login days',
        unlocked: _streakDays >= 7,
        color: context.vt.accentGold,
      ),
      _MilestoneBadge(
        icon: Icons.shield_rounded,
        title: 'Risk Manager',
        subtitle: 'Place GTTs on every trade day',
        unlocked: false,
        color: context.vt.accentPurple,
      ),
      _MilestoneBadge(
        icon: Icons.trending_up_rounded,
        title: 'Profit Week',
        subtitle: '5 or more winning positions',
        unlocked: winningPos >= 5,
        color: context.vt.accentGreen,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: Sp.md),
          child: Text('Milestones',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.vt.textSecondary,
              )),
        ),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: Sp.sm,
          mainAxisSpacing: Sp.sm,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.6,
          children: badges.map(_buildBadgeTile).toList(),
        ),
      ],
    );
  }

  Widget _buildBadgeTile(_MilestoneBadge b) {
    final col = b.unlocked ? b.color : context.vt.textTertiary;
    return AnimatedContainer(
      duration: Duration(milliseconds: 400),
      padding: EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: b.unlocked
            ? b.color.withValues(alpha: 0.1)
            : context.vt.surface2,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(
          color: b.unlocked
              ? b.color.withValues(alpha: 0.35)
              : context.vt.divider,
        ),
        boxShadow: b.unlocked
            ? [BoxShadow(color: b.color.withValues(alpha: 0.15), blurRadius: 12, spreadRadius: -3)]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(b.unlocked ? b.icon : Icons.lock_outline_rounded,
              size: 20, color: col),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b.title,
                  style: AppTextStyles.caption.copyWith(
                      color: col, fontWeight: FontWeight.w700)),
              Text(b.subtitle,
                  style: AppTextStyles.caption.copyWith(
                      color: context.vt.textTertiary, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ],
      ),
    );
  }

  // ── Win Rate card ──────────────────────────────────────────────────────────

  Widget _buildWinRateCard(double winRate, Map<String, dynamic> d) {
    final wins = (d['winning_positions'] as num?)?.toInt() ?? 0;
    final losses = (d['losing_positions'] as num?)?.toInt() ?? 0;
    final total = wins + losses;
    final winFraction = total > 0 ? wins / total : 0.0;
    final winColor = winRate >= 60
        ? context.vt.accentGreen
        : winRate >= 40
            ? context.vt.warning
            : context.vt.danger;

    return VtCard(
      child: Row(
        children: [
          // Arc
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: winFraction,
                  backgroundColor: context.vt.surface3,
                  color: winColor,
                  strokeWidth: 8,
                  strokeCap: StrokeCap.round,
                ),
                Text(
                  '${winRate.toStringAsFixed(0)}%',
                  style: AppTextStyles.mono.copyWith(
                      color: winColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 16),
                ),
              ],
            ),
          ),
          const SizedBox(width: Sp.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Win Rate', style: AppTextStyles.bodyLarge),
                const SizedBox(height: Sp.xs),
                Text(
                  '$wins wins · $losses losses · $total total',
                  style: AppTextStyles.caption,
                ),
                SizedBox(height: Sp.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Rad.pill),
                  child: SizedBox(
                    height: 6,
                    child: Row(
                      children: [
                        Expanded(
                          flex: (winFraction * 100).round(),
                          child: Container(color: winColor),
                        ),
                        Expanded(
                          flex:
                              ((1 - winFraction) * 100).round(),
                          child: Container(color: context.vt.surface3),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Helper widgets ─────────────────────────────────────────────────────────

  Widget _heroStat(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTextStyles.caption),
        const SizedBox(height: 4),
        Text(value,
            style: AppTextStyles.mono.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13)),
      ],
    );
  }

  Widget _statTile({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: context.vt.surface1,
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: Sp.xs),
              Text(label,
                  style: AppTextStyles.caption
                      .copyWith(color: color, fontSize: 10)),
            ],
          ),
          const SizedBox(height: Sp.xs),
          Text(
            value,
            style: AppTextStyles.mono.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _tradeRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.body),
        Text(
          value,
          style: AppTextStyles.mono.copyWith(
              color: valueColor, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _chargeRow(String label, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: AppTextStyles.body
                    .copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(desc, style: AppTextStyles.caption),
          ),
        ],
      ),
    );
  }
}

class _MilestoneBadge {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool unlocked;
  final Color color;

  const _MilestoneBadge({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.unlocked,
    required this.color,
  });
}
