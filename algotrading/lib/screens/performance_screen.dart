import '../theme/vt_color_scheme.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
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

// ── Tab index constants ────────────────────────────────────────────────────
const int _kTabToday   = 0;
const int _kTabMonthly = 1;
const int _kTabAllTime = 2;

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen>
    with SingleTickerProviderStateMixin {
  final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  late TabController _tabController;

  // Today / Monthly state
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _data;
  bool _chargesExpanded = false;
  int _streakDays = 0;

  // Monthly picker
  int _selectedMonth = DateTime.now().month;
  int _selectedYear  = DateTime.now().year;

  // All-Time / History state
  bool _histLoading = false;
  String? _histError;
  Map<String, dynamic>? _histData;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _onTabChanged(_tabController.index);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchPeriodData(_kTabToday);
      StreakService.instance.currentStreak().then(
        (v) { if (mounted) setState(() => _streakDays = v); },
      );
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged(int index) {
    if (index == _kTabAllTime) {
      if (_histData == null && !_histLoading) _fetchHistory();
    } else {
      _fetchPeriodData(index);
    }
  }

  // ── Fetchers ───────────────────────────────────────────────────────────────

  Future<void> _fetchPeriodData(int tabIndex) async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    setState(() { _isLoading = true; _error = null; });

    try {
      final Map<String, String> params = {
        'access_token': auth.user!.accessToken,
        'api_key':      auth.user!.apiKey,
        'user_id':      auth.user!.userId,
      };

      if (tabIndex == _kTabToday) {
        params['period'] = 'today';
      } else {
        params['period'] = 'monthly';
        params['month']  = _selectedMonth.toString();
        params['year']   = _selectedYear.toString();
      }

      final uri = Uri.parse(ApiConfig.monthlyPerformanceUrl)
          .replace(queryParameters: params);
      final response = await http.get(uri).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        setState(() => _data = jsonDecode(response.body));
      } else {
        final body = jsonDecode(response.body);
        setState(() => _error = body['detail'] ?? 'Failed to load performance');
      }
    } catch (e) {
      setState(() => _error =
          'Network error: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchHistory() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    setState(() { _histLoading = true; _histError = null; });

    try {
      final uri = Uri.parse(ApiConfig.performanceHistoryUrl).replace(
        queryParameters: {
          'access_token': auth.user!.accessToken,
          'api_key':      auth.user!.apiKey,
          'months':       '12',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        setState(() => _histData = jsonDecode(response.body));
      } else {
        final body = jsonDecode(response.body);
        setState(() => _histError = body['detail'] ?? 'Failed to load history');
      }
    } catch (e) {
      setState(() => _histError =
          'Network error: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      setState(() => _histLoading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text('Performance', style: AppTextStyles.h2),
        bottom: TabBar(
          controller: _tabController,
          labelStyle: AppTextStyles.caption
              .copyWith(fontWeight: FontWeight.w700, fontSize: 12),
          unselectedLabelStyle:
              AppTextStyles.caption.copyWith(fontSize: 12),
          labelColor: context.vt.accentGreen,
          unselectedLabelColor: context.vt.textSecondary,
          indicatorColor: context.vt.accentGreen,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: 'Today'),
            Tab(text: 'Monthly'),
            Tab(text: 'All Time'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPeriodTab(_kTabToday),
          _buildPeriodTab(_kTabMonthly),
          _buildAllTimeTab(),
        ],
      ),
    );
  }

  // ── Today / Monthly tab ────────────────────────────────────────────────────

  Widget _buildPeriodTab(int tabIndex) {
    if (_isLoading) {
      return Center(
          child: CircularProgressIndicator(color: context.vt.accentGreen));
    }
    if (_error != null) return _buildError(_error!, () => _fetchPeriodData(tabIndex));
    if (_data == null) {
      return Center(child: Text('No data', style: AppTextStyles.bodySecondary));
    }

    return RefreshIndicator(
      color: context.vt.accentGreen,
      backgroundColor: context.vt.surface1,
      onRefresh: () => _fetchPeriodData(tabIndex),
      child: _buildPeriodContent(tabIndex),
    );
  }

  Widget _buildPeriodContent(int tabIndex) {
    final d = _data!;
    final totalPnl = (d['total_pnl'] as num).toDouble();
    final netPnl   = (d['net_pnl']   as num).toDouble();
    final isProfit = netPnl >= 0;
    final heroColor = isProfit ? context.vt.accentGreen : context.vt.danger;
    final winRate   = (d['win_rate']  as num).toDouble();

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Sp.base, Sp.sm, Sp.base, Sp.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Month picker (Monthly tab only) ──────────────────────────────
          if (tabIndex == _kTabMonthly) ...[
            _buildMonthPicker(),
            SizedBox(height: Sp.base),
          ],

          // ── Period label ─────────────────────────────────────────────────
          Center(
            child: Text(d['month'] ?? '',
                style: AppTextStyles.bodySecondary
                    .copyWith(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 2),
          Center(
            child: Text(
              tabIndex == _kTabToday
                  ? "Today's Trading Performance"
                  : 'Monthly Trading Performance',
              style: AppTextStyles.caption,
            ),
          ),
          SizedBox(height: Sp.base),

          // ── Net P&L hero ─────────────────────────────────────────────────
          _buildHeroCard(netPnl, totalPnl, d, heroColor, isProfit, winRate),
          SizedBox(height: Sp.base),

          // ── Win Rate Arc ─────────────────────────────────────────────────
          _buildWinRateCard(winRate, d),
          SizedBox(height: Sp.base),

          // ── Stat cards 2x2 ───────────────────────────────────────────────
          Row(children: [
            Expanded(child: _statTile(
              label: 'Gross Profit',
              value: _currency.format((d['gross_profit'] as num).toDouble()),
              color: context.vt.accentGreen,
              icon: Icons.trending_up_rounded,
            )),
            SizedBox(width: Sp.sm),
            Expanded(child: _statTile(
              label: 'Gross Loss',
              value: _currency.format((d['gross_loss'] as num).toDouble()),
              color: context.vt.danger,
              icon: Icons.trending_down_rounded,
            )),
          ]),
          SizedBox(height: Sp.sm),
          Row(children: [
            Expanded(child: _statTile(
              label: 'Unrealized P&L',
              value: _currency.format((d['unrealized_pnl'] as num).toDouble()),
              color: context.vt.accentPurple,
              icon: Icons.access_time_rounded,
            )),
            SizedBox(width: Sp.sm),
            Expanded(child: _statTile(
              label: 'Max Drawdown',
              value: _currency.format((d['max_drawdown'] as num).toDouble()),
              color: context.vt.warning,
              icon: Icons.waterfall_chart_rounded,
            )),
          ]),
          SizedBox(height: Sp.base),

          // ── Trade stats ──────────────────────────────────────────────────
          VtCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                    title: 'Trade Statistics',
                    paddingTop: 0,
                    paddingBottom: Sp.md),
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
                  _currency.format((d['realized_pnl'] as num).toDouble()),
                  (d['realized_pnl'] as num) >= 0
                      ? context.vt.accentGreen
                      : context.vt.danger,
                ),
              ],
            ),
          ),
          SizedBox(height: Sp.base),

          // ── Charges breakdown ────────────────────────────────────────────
          _buildChargesCard(),
          SizedBox(height: Sp.base),

          // ── Milestones ───────────────────────────────────────────────────
          _buildMilestonesSection(_data!),
        ],
      ),
    );
  }

  // ── Month picker widget ────────────────────────────────────────────────────

  Widget _buildMonthPicker() {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final now = DateTime.now();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.chevron_left_rounded,
              color: context.vt.textSecondary),
          onPressed: () {
            setState(() {
              if (_selectedMonth == 1) {
                _selectedMonth = 12;
                _selectedYear--;
              } else {
                _selectedMonth--;
              }
              _data = null;
            });
            _fetchPeriodData(_kTabMonthly);
          },
        ),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Sp.lg, vertical: Sp.sm),
          decoration: BoxDecoration(
            color: context.vt.surface1,
            borderRadius: BorderRadius.circular(Rad.pill),
            border: Border.all(color: context.vt.divider),
          ),
          child: Text(
            '${months[_selectedMonth - 1]} $_selectedYear',
            style: AppTextStyles.body
                .copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          icon: Icon(Icons.chevron_right_rounded,
              color: (_selectedYear == now.year &&
                      _selectedMonth == now.month)
                  ? context.vt.surface3
                  : context.vt.textSecondary),
          onPressed: (_selectedYear == now.year &&
                  _selectedMonth == now.month)
              ? null
              : () {
                  setState(() {
                    if (_selectedMonth == 12) {
                      _selectedMonth = 1;
                      _selectedYear++;
                    } else {
                      _selectedMonth++;
                    }
                    _data = null;
                  });
                  _fetchPeriodData(_kTabMonthly);
                },
        ),
      ],
    );
  }

  // ── All Time tab ───────────────────────────────────────────────────────────

  Widget _buildAllTimeTab() {
    if (_histLoading) {
      return Center(
          child: CircularProgressIndicator(color: context.vt.accentGreen));
    }
    if (_histError != null) return _buildError(_histError!, _fetchHistory);
    if (_histData == null) {
      return Center(child: Text('No data', style: AppTextStyles.bodySecondary));
    }

    return RefreshIndicator(
      color: context.vt.accentGreen,
      backgroundColor: context.vt.surface1,
      onRefresh: _fetchHistory,
      child: _buildAllTimeContent(),
    );
  }

  Widget _buildAllTimeContent() {
    final h = _histData!;
    final allTimePnl  = (h['all_time_pnl']    as num).toDouble();
    final allTrades   = (h['all_time_trades']  as num).toInt();
    final allWinRate  = (h['all_time_win_rate'] as num).toDouble();
    final isProfit    = allTimePnl >= 0;
    final heroColor   = isProfit ? context.vt.accentGreen : context.vt.danger;
    final months      = (h['months'] as List<dynamic>);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Sp.base, Sp.sm, Sp.base, Sp.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── All-time hero ────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Sp.xl),
            decoration: BoxDecoration(
              color: context.vt.surface1,
              borderRadius: BorderRadius.circular(Rad.lg),
              border: Border.all(color: heroColor.withValues(alpha: 0.3)),
              boxShadow:
                  isProfit ? AppColors.greenGlow : AppColors.dangerGlow,
            ),
            child: Column(
              children: [
                Text('Total Capital Growth',
                    style: AppTextStyles.caption),
                Text('Since you started using VanTrade',
                    style: AppTextStyles.caption
                        .copyWith(color: context.vt.textTertiary)),
                SizedBox(height: Sp.sm),
                Text(
                  '${isProfit ? '+' : ''}${_currency.format(allTimePnl)}',
                  style: AppTextStyles.display.copyWith(
                      color: heroColor, fontSize: 36),
                ),
                SizedBox(height: Sp.base),
                Divider(color: context.vt.divider, height: 1),
                SizedBox(height: Sp.base),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _heroStat('Total Trades', '$allTrades',
                        context.vt.textPrimary),
                    Container(
                        width: 1, height: 32, color: context.vt.divider),
                    _heroStat(
                      'Win Rate',
                      '${allWinRate.toStringAsFixed(0)}%',
                      allWinRate >= 60
                          ? context.vt.accentGreen
                          : allWinRate >= 40
                              ? context.vt.warning
                              : context.vt.danger,
                    ),
                    Container(
                        width: 1, height: 32, color: context.vt.divider),
                    _heroStat(
                      'Months Active',
                      '${months.length}',
                      context.vt.accentPurple,
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: Sp.base),

          // ── Capital Growth Bar Chart ──────────────────────────────────────
          if (months.isNotEmpty) ...[
            VtCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                      title: 'Monthly P&L',
                      paddingTop: 0,
                      paddingBottom: Sp.md),
                  SizedBox(
                    height: 180,
                    child: _PnlBarChart(
                      months: months,
                      profitColor: context.vt.accentGreen,
                      lossColor: context.vt.danger,
                      axisColor: context.vt.divider,
                      labelColor: context.vt.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: Sp.base),
          ],

          // ── Cumulative Growth Curve ───────────────────────────────────────
          if (months.length > 1) ...[
            VtCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                      title: 'Cumulative Growth',
                      paddingTop: 0,
                      paddingBottom: Sp.md),
                  SizedBox(
                    height: 150,
                    child: _CumulativeLineChart(
                      months: months,
                      lineColor: context.vt.accentGreen,
                      axisColor: context.vt.divider,
                      labelColor: context.vt.textTertiary,
                      zeroColor: context.vt.divider,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: Sp.base),
          ],

          // ── Monthly history list ──────────────────────────────────────────
          VtCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                    title: 'Month-by-Month',
                    paddingTop: 0,
                    paddingBottom: Sp.md),
                if (months.isEmpty)
                  Center(
                    child: Padding(
                      padding: EdgeInsets.all(Sp.xl),
                      child: Text('No closed trades yet',
                          style: AppTextStyles.bodySecondary),
                    ),
                  )
                else
                  ...months.reversed.map<Widget>((m) {
                    final pnl    = (m['total_pnl']  as num).toDouble();
                    final cumPnl = (m['cumulative_pnl'] as num).toDouble();
                    final trades = (m['total_trades'] as num).toInt();
                    final wr     = (m['win_rate']    as num).toDouble();
                    final col    = pnl >= 0
                        ? context.vt.accentGreen
                        : context.vt.danger;

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: Sp.sm),
                          child: Row(
                            children: [
                              // Month label
                              SizedBox(
                                width: 72,
                                child: Text(
                                  m['month_label'] as String,
                                  style: AppTextStyles.body.copyWith(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${pnl >= 0 ? '+' : ''}${_currency.format(pnl)}',
                                      style: AppTextStyles.mono.copyWith(
                                          color: col,
                                          fontWeight: FontWeight.w700),
                                    ),
                                    Text(
                                      '$trades trade${trades != 1 ? 's' : ''} · ${wr.toStringAsFixed(0)}% win',
                                      style: AppTextStyles.caption,
                                    ),
                                  ],
                                ),
                              ),
                              // Cumulative chip
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: Sp.sm, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (cumPnl >= 0
                                          ? context.vt.accentGreen
                                          : context.vt.danger)
                                      .withValues(alpha: 0.12),
                                  borderRadius:
                                      BorderRadius.circular(Rad.pill),
                                ),
                                child: Text(
                                  'Σ ${cumPnl >= 0 ? '+' : ''}${_currency.format(cumPnl)}',
                                  style: AppTextStyles.caption.copyWith(
                                    color: cumPnl >= 0
                                        ? context.vt.accentGreen
                                        : context.vt.danger,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(
                            height: 1, color: context.vt.divider),
                      ],
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared hero card ───────────────────────────────────────────────────────

  Widget _buildHeroCard(double netPnl, double totalPnl,
      Map<String, dynamic> d, Color heroColor, bool isProfit, double winRate) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Sp.xl),
      decoration: BoxDecoration(
        color: context.vt.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: heroColor.withValues(alpha: 0.3)),
        boxShadow: isProfit ? AppColors.greenGlow : AppColors.dangerGlow,
      ),
      child: Column(
        children: [
          Text('Net P&L (After Charges)', style: AppTextStyles.caption),
          SizedBox(height: Sp.sm),
          Text(
            '${isProfit ? '+' : ''}${_currency.format(netPnl)}',
            style: AppTextStyles.display
                .copyWith(color: heroColor, fontSize: 36),
          ),
          SizedBox(height: Sp.base),
          Divider(color: context.vt.divider, height: 1),
          SizedBox(height: Sp.base),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _heroStat('Gross P&L', _currency.format(totalPnl),
                  totalPnl >= 0 ? context.vt.accentGreen : context.vt.danger),
              Container(width: 1, height: 32, color: context.vt.divider),
              _heroStat(
                'Charges',
                '−${_currency.format((d['total_charges'] as num).toDouble())}',
                context.vt.warning,
              ),
              Container(width: 1, height: 32, color: context.vt.divider),
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
    );
  }

  // ── Milestones ─────────────────────────────────────────────────────────────

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
          padding: const EdgeInsets.only(bottom: Sp.md),
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
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(Sp.md),
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
            ? [BoxShadow(
                color: b.color.withValues(alpha: 0.15),
                blurRadius: 12,
                spreadRadius: -3)]
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
    final wins        = (d['winning_positions'] as num?)?.toInt() ?? 0;
    final losses      = (d['losing_positions']  as num?)?.toInt() ?? 0;
    final total       = wins + losses;
    final winFraction = total > 0 ? wins / total : 0.0;
    final winColor    = winRate >= 60
        ? context.vt.accentGreen
        : winRate >= 40
            ? context.vt.warning
            : context.vt.danger;

    return VtCard(
      child: Row(
        children: [
          SizedBox(
            width: 80, height: 80,
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
                Text('$wins wins · $losses losses · $total total',
                    style: AppTextStyles.caption),
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
                          flex: ((1 - winFraction) * 100).round(),
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

  // ── Charges breakdown ──────────────────────────────────────────────────────

  Widget _buildChargesCard() {
    return VtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () =>
                setState(() => _chargesExpanded = !_chargesExpanded),
            child: Row(
              children: [
                Expanded(
                  child: SectionHeader(
                      title: 'Charges Breakdown',
                      paddingTop: 0,
                      paddingBottom: 0),
                ),
                AnimatedRotation(
                  turns: _chargesExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      color: context.vt.textSecondary, size: 20),
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
                Divider(height: 1, color: context.vt.divider),
                SizedBox(height: Sp.md),
                Text('F&O Options Rate Card',
                    style: AppTextStyles.caption.copyWith(
                        color: context.vt.accentPurple,
                        fontWeight: FontWeight.w600)),
                SizedBox(height: Sp.sm),
                _chargeRow('Brokerage', '₹20 flat per executed order (Zerodha)'),
                _chargeRow('STT', '0.0125% on sell premium turnover'),
                _chargeRow('Exchange charges',
                    '0.053% of premium turnover (NSE options)'),
                _chargeRow('SEBI charges', '₹10 per crore of turnover'),
                _chargeRow('GST', '18% on brokerage + exchange charges'),
                _chargeRow('Stamp duty', '0.003% on buy premium turnover'),
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
    );
  }

  // ── Error state ────────────────────────────────────────────────────────────

  Widget _buildError(String message, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(Sp.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 44, color: context.vt.danger),
            SizedBox(height: Sp.md),
            Text(message,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySecondary
                    .copyWith(color: context.vt.danger)),
            SizedBox(height: Sp.xl),
            VtButton(
              label: 'Retry',
              onPressed: onRetry,
              variant: VtButtonVariant.secondary,
              icon: Icon(Icons.refresh_rounded,
                  size: 16, color: context.vt.textSecondary),
            ),
          ],
        ),
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
                color: color, fontWeight: FontWeight.w700, fontSize: 13)),
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
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: context.vt.surface1,
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: Sp.xs),
            Text(label,
                style: AppTextStyles.caption
                    .copyWith(color: color, fontSize: 10)),
          ]),
          const SizedBox(height: Sp.xs),
          Text(value,
              style: AppTextStyles.mono.copyWith(
                  color: color, fontWeight: FontWeight.w700, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _tradeRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.body),
        Text(value,
            style: AppTextStyles.mono
                .copyWith(color: valueColor, fontWeight: FontWeight.w700)),
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
                style:
                    AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(desc, style: AppTextStyles.caption)),
        ],
      ),
    );
  }
}

// ── P&L Bar Chart ─────────────────────────────────────────────────────────────

class _PnlBarChart extends StatelessWidget {
  final List<dynamic> months;
  final Color profitColor;
  final Color lossColor;
  final Color axisColor;
  final Color labelColor;

  const _PnlBarChart({
    required this.months,
    required this.profitColor,
    required this.lossColor,
    required this.axisColor,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BarChartPainter(
        months: months,
        profitColor: profitColor,
        lossColor: lossColor,
        axisColor: axisColor,
        labelColor: labelColor,
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<dynamic> months;
  final Color profitColor;
  final Color lossColor;
  final Color axisColor;
  final Color labelColor;

  _BarChartPainter({
    required this.months,
    required this.profitColor,
    required this.lossColor,
    required this.axisColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty) return;

    const double labelH  = 18.0;
    const double padLeft = 8.0;
    const double padRight = 8.0;
    const double barGap  = 4.0;

    final chartH = size.height - labelH;
    final n      = months.length;
    final barW   = (size.width - padLeft - padRight - barGap * (n - 1)) / n;

    final values = months.map<double>((m) =>
        (m['total_pnl'] as num).toDouble()).toList();

    final maxAbs = values.fold<double>(
        0, (acc, v) => math.max(acc, v.abs()));

    if (maxAbs == 0) return;

    // Zero line Y
    final maxVal = values.fold<double>(0, (a, v) => math.max(a, v));
    final minVal = values.fold<double>(0, (a, v) => math.min(a, v));
    final range  = math.max(maxVal, 0) - math.min(minVal, 0);
    if (range == 0) return;

    double yForValue(double v) =>
        chartH * (1 - (v - math.min(minVal, 0)) / range);

    final zeroY = yForValue(0);

    // Draw zero axis
    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(padLeft, zeroY), Offset(size.width - padRight, zeroY), axisPaint);

    // Draw bars
    for (int i = 0; i < n; i++) {
      final v   = values[i];
      final col = v >= 0 ? profitColor : lossColor;
      final barX = padLeft + i * (barW + barGap);
      final top    = yForValue(math.max(v, 0));
      final bottom = yForValue(math.min(v, 0));

      final paint = Paint()
        ..color = col.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTRB(barX, top, barX + barW, bottom),
        const Radius.circular(2),
      );
      canvas.drawRRect(rrect, paint);

      // Month label
      final label = (months[i]['month_label'] as String).split(' ')[0];
      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: TextStyle(
                color: labelColor,
                fontSize: 9,
                fontWeight: FontWeight.w600)),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: barW + barGap);

      tp.paint(canvas,
          Offset(barX + (barW - tp.width) / 2, chartH + 2));
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) => false;
}

// ── Cumulative Line Chart ──────────────────────────────────────────────────────

class _CumulativeLineChart extends StatelessWidget {
  final List<dynamic> months;
  final Color lineColor;
  final Color axisColor;
  final Color labelColor;
  final Color zeroColor;

  const _CumulativeLineChart({
    required this.months,
    required this.lineColor,
    required this.axisColor,
    required this.labelColor,
    required this.zeroColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LinePainter(
        months: months,
        lineColor: lineColor,
        axisColor: axisColor,
        labelColor: labelColor,
        zeroColor: zeroColor,
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<dynamic> months;
  final Color lineColor;
  final Color axisColor;
  final Color labelColor;
  final Color zeroColor;

  _LinePainter({
    required this.months,
    required this.lineColor,
    required this.axisColor,
    required this.labelColor,
    required this.zeroColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (months.length < 2) return;

    const double labelH  = 18.0;
    const double padLeft = 8.0;
    const double padRight = 8.0;

    final chartH = size.height - labelH;
    final n      = months.length;

    final cumulValues = months.map<double>((m) =>
        (m['cumulative_pnl'] as num).toDouble()).toList();

    final maxVal = cumulValues.fold<double>(0, (a, v) => math.max(a, v));
    final minVal = cumulValues.fold<double>(0, (a, v) => math.min(a, v));
    final range  = math.max(maxVal, 0) - math.min(minVal, 0);
    if (range == 0) return;

    double xForIndex(int i) =>
        padLeft + i * (size.width - padLeft - padRight) / (n - 1);

    double yForValue(double v) =>
        chartH * (1 - (v - math.min(minVal, 0)) / range);

    final zeroY = yForValue(0);

    // Zero reference line
    final zeroPaint = Paint()
      ..color = zeroColor
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(padLeft, zeroY), Offset(size.width - padRight, zeroY), zeroPaint);

    // Gradient fill under curve
    final path = Path()
      ..moveTo(xForIndex(0), yForValue(cumulValues[0]));
    for (int i = 1; i < n; i++) {
      path.lineTo(xForIndex(i), yForValue(cumulValues[i]));
    }
    path
      ..lineTo(xForIndex(n - 1), zeroY)
      ..lineTo(xForIndex(0), zeroY)
      ..close();

    final lastIsProfit = cumulValues.last >= 0;
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          (lastIsProfit ? lineColor : Colors.red)
              .withValues(alpha: 0.25),
          (lastIsProfit ? lineColor : Colors.red)
              .withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, chartH))
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Line stroke
    final linePaint = Paint()
      ..color = lastIsProfit ? lineColor : Colors.red
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final linePath = Path()
      ..moveTo(xForIndex(0), yForValue(cumulValues[0]));
    for (int i = 1; i < n; i++) {
      linePath.lineTo(xForIndex(i), yForValue(cumulValues[i]));
    }
    canvas.drawPath(linePath, linePaint);

    // Dot on last point
    canvas.drawCircle(
      Offset(xForIndex(n - 1), yForValue(cumulValues.last)),
      4,
      Paint()..color = lastIsProfit ? lineColor : Colors.red,
    );

    // Month labels
    for (int i = 0; i < n; i++) {
      if (i % math.max(1, (n / 4).round()) != 0 && i != n - 1) continue;
      final label = (months[i]['month_label'] as String).split(' ')[0];
      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: TextStyle(
                color: labelColor,
                fontSize: 9,
                fontWeight: FontWeight.w600)),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset(xForIndex(i) - tp.width / 2, chartH + 2));
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => false;
}

// ── Data model ─────────────────────────────────────────────────────────────────

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
