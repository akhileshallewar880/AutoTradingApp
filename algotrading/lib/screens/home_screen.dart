import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../services/streak_service.dart';
import '../providers/dashboard_provider.dart';
import '../models/dashboard_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../theme/vt_color_scheme.dart';
import '../providers/theme_provider.dart';
import '../utils/api_config.dart';
import '../widgets/vt_card.dart';
import '../widgets/vt_button.dart';
import '../widgets/price_text.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/status_badge.dart';
import '../widgets/section_header.dart';
import 'analysis_input_screen.dart';
import 'backtest_screen.dart';
import 'gtt_analysis_screen.dart';
import 'holdings_screen.dart';
import '../main.dart' show routeObserver;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware, WidgetsBindingObserver {
  final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  Map<String, dynamic> _indexPrices = {};
  Timer? _indexRefreshTimer;
  int _streakDays = 0;
  bool _insightDismissed = false;

  static const _insights = [
    'NIFTY above its 50-day EMA — historically bullish over a 3-week horizon.',
    'Banking stocks tend to outperform in rising rate environments.',
    'High VIX (>20) often precedes sharp reversals — size positions carefully.',
    'Stocks near 52-week highs on strong volume tend to break out further.',
    'RSI > 70 in an uptrend is strength, not exhaustion — wait for divergence.',
    'The first 30 minutes of NSE trading often set the day\'s directional bias.',
    'Earnings week volatility is highest in IT and pharma — widen stop-losses.',
    'BANKNIFTY often leads NIFTY by 15–20 minutes on trend days.',
    'Always check open interest data before entering options positions.',
    'Mid-caps typically outperform large-caps in bull market second legs.',
    'Consecutive wide-range candles on volume signal institutional accumulation.',
    'MACD crossover above the zero line carries more weight than below.',
    'Delivery percentage > 60% on a breakout suggests genuine demand.',
    'Avoid trading the first 5 minutes — let the market find its footing.',
    'Swing trades with R:R above 2 statistically outperform even with a 40% win rate.',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initDashboard();
      routeObserver.subscribe(this, ModalRoute.of(context)!);
    });
  }

  @override
  void didPopNext() {
    final auth = context.read<AuthProvider>();
    if (auth.user != null) {
      context.read<DashboardProvider>().fetchDashboard(
        auth.user!.accessToken,
        apiKey: auth.user!.apiKey,
      );
      _fetchIndexPrices();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final auth = context.read<AuthProvider>();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _indexRefreshTimer?.cancel();
      _indexRefreshTimer = null;
      context.read<DashboardProvider>().stopAutoRefresh();
    } else if (state == AppLifecycleState.resumed) {
      if (auth.user != null) {
        _fetchIndexPrices();
        _indexRefreshTimer = Timer.periodic(
          const Duration(seconds: 60),
          (_) => _fetchIndexPrices(),
        );
        context.read<DashboardProvider>()
          ..fetchDashboard(auth.user!.accessToken, apiKey: auth.user!.apiKey)
          ..startAutoRefresh(auth.user!.accessToken,
              apiKey: auth.user!.apiKey, intervalSeconds: 60);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    _indexRefreshTimer?.cancel();
    context.read<DashboardProvider>().stopAutoRefresh();
    super.dispose();
  }

  void _initDashboard() {
    final auth = context.read<AuthProvider>();
    final dash = context.read<DashboardProvider>();
    if (auth.user != null) {
      dash.fetchDashboard(auth.user!.accessToken, apiKey: auth.user!.apiKey)
          .then((_) => _checkSessionExpired());
      dash.startAutoRefresh(auth.user!.accessToken, apiKey: auth.user!.apiKey);
      _fetchIndexPrices();
      _indexRefreshTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => _fetchIndexPrices(),
      );
      _checkStreak();
    }
  }

  Future<void> _checkStreak() async {
    final result = await StreakService.instance.checkAndUpdate();
    if (!mounted) return;
    setState(() => _streakDays = result.streakDays);
    if (!result.isNewDay) return;
    final days = result.streakDays;
    final msg = days == 1
        ? '🔥 Welcome back! Streak started.'
        : '🔥 Day $days streak! Keep it up.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: AppTextStyles.bodyLarge.copyWith(color: context.vt.textPrimary)),
        backgroundColor: context.vt.surface2,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          side: BorderSide(color: context.vt.accentGold),
        ),
      ),
    );
  }

  Future<void> _fetchIndexPrices() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null || auth.isDemoMode) return;
    try {
      final uri = Uri.parse(ApiConfig.tickerSnapshotUrl).replace(
        queryParameters: {
          'api_key': auth.user!.apiKey,
          'access_token': auth.user!.accessToken,
          'tokens': '256265,260105',
        },
      );
      final resp = await http.get(uri).timeout(Duration(seconds: 10));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() => _indexPrices = data['snapshot'] ?? {});
      }
    } catch (_) {}
  }

  void _checkSessionExpired() {
    if (!mounted) return;
    final dash = context.read<DashboardProvider>();
    if (dash.sessionExpired) _handleSessionExpired();
  }

  Future<void> _handleSessionExpired() async {
    if (!mounted) return;
    context.read<DashboardProvider>().stopAutoRefresh();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Session Expired'),
        content: const Text(
          'Your Zerodha session has expired. Please login again to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _refresh() async {
    final auth = context.read<AuthProvider>();
    if (auth.user != null) {
      await context.read<DashboardProvider>().fetchDashboard(
        auth.user!.accessToken,
        apiKey: auth.user!.apiKey,
      );
      _checkSessionExpired();
    }
  }

  // ── Market open check ──────────────────────────────────────────────────────
  bool get _isMarketOpen {
    final now = DateTime.now();
    if (now.weekday >= 6) return false;
    final t = now.hour * 60 + now.minute;
    return t >= 555 && t <= 930;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final dash = context.watch<DashboardProvider>();
    final user = auth.user;

    final vt = context.vt;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: vt.surface0,
        appBar: _buildAppBar(auth, dash),
        bottomNavigationBar: _buildBottomBar(context),
        body: Column(
          children: [
            if (auth.isDemoMode) _buildDemoBanner(context),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: vt.accentGreen,
                backgroundColor: vt.surface2,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    Sp.base, Sp.base, Sp.base, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Welcome row
                      _buildWelcomeRow(user?.userName ?? 'Trader')
                          .animate().fadeIn(duration: 300.ms)
                          .slideY(begin: 0.04, end: 0, duration: 300.ms),
                      const SizedBox(height: Sp.md),

                      // Index prices strip
                      if (!auth.isDemoMode && _indexPrices.isNotEmpty) ...[
                        _buildIndexStrip()
                            .animate(delay: 60.ms).fadeIn(duration: 280.ms)
                            .slideY(begin: 0.04, end: 0, duration: 280.ms),
                        const SizedBox(height: Sp.md),
                      ],

                      // Balance / P&L hero card
                      if (dash.error != null && dash.dashboard == null)
                        _buildErrorCard(dash.error!).animate(delay: 80.ms).fadeIn()
                      else ...[
                        _buildBalanceCard(dash.dashboard)
                            .animate(delay: 80.ms).fadeIn(duration: 300.ms)
                            .slideY(begin: 0.04, end: 0, duration: 300.ms),
                        const SizedBox(height: Sp.md),

                        // Add funds nudge
                        if ((dash.dashboard?.availableBalance ?? 0) == 0)
                          _buildAddFundsCard()
                              .animate(delay: 120.ms).fadeIn().slideY(begin: 0.04, end: 0),
                      ],

                      // Daily market insight
                      _buildInsightCard(),
                      const SizedBox(height: Sp.md),

                      // Positions
                      if (dash.dashboard?.positions.isNotEmpty ?? false) ...[
                        SectionHeader(
                          title: 'Open Positions',
                          trailing: StatusBadge(
                            label: '${dash.dashboard!.positions.length}',
                            type: BadgeType.success,
                          ),
                        ),
                        _buildPositionsList(dash.dashboard!.positions)
                            .animate(delay: 140.ms).fadeIn().slideY(begin: 0.04, end: 0),
                        const SizedBox(height: Sp.md),
                      ],

                      // GTTs
                      SectionHeader(
                        title: 'Protected Orders',
                        trailing: StatusBadge(
                          label: '${dash.dashboard?.gtts.length ?? 0} GTTs',
                          type: BadgeType.ai,
                        ),
                      ),
                      _buildGttList(dash.dashboard?.gtts ?? [])
                          .animate(delay: 160.ms).fadeIn().slideY(begin: 0.04, end: 0),
                      const SizedBox(height: Sp.md),

                      // Orders
                      SectionHeader(title: "Today's Activity"),
                      _buildOrdersList(dash.dashboard?.orders ?? [])
                          .animate(delay: 180.ms).fadeIn().slideY(begin: 0.04, end: 0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(AuthProvider auth, DashboardProvider dash) {
    final vt = context.vt;
    final isDark = vt.isDark;
    return AppBar(
      backgroundColor: vt.surface0,
      titleSpacing: Sp.base,
      title: Row(
        children: [
          // Logo mark — green gradient (matches VanTradeLogoWidget)
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.30),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.candlestick_chart,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: Sp.sm),
          Text('VanTrade', style: AppTextStyles.h3),
        ],
      ),
      actions: [
        if (_streakDays > 0) _StreakBadge(days: _streakDays),
        const SizedBox(width: Sp.xs),
        StatusBadge(
          label: _isMarketOpen ? 'OPEN' : 'CLOSED',
          type: _isMarketOpen ? BadgeType.success : BadgeType.neutral,
          pulseDot: _isMarketOpen,
        ),
        const SizedBox(width: Sp.xs),
        if (dash.isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: vt.accentGreen,
              ),
            ),
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          tooltip: 'More',
          onSelected: (value) {
            if (value == 'backtest') {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const BacktestScreen()));
            } else if (value == 'theme') {
              context.read<ThemeProvider>().toggle();
            } else if (value == 'logout') {
              _handleLogout(context);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'theme',
              child: Row(
                children: [
                  Icon(
                    isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                    size: 18, color: vt.textSecondary,
                  ),
                  const SizedBox(width: Sp.sm),
                  Text(isDark ? 'Light Mode' : 'Dark Mode',
                      style: AppTextStyles.body),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'backtest',
              child: Row(
                children: [
                  Icon(Icons.science_outlined, size: 18, color: vt.textSecondary),
                  const SizedBox(width: Sp.sm),
                  Text('Strategy Backtest', style: AppTextStyles.body),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout, size: 18, color: vt.danger),
                  const SizedBox(width: Sp.sm),
                  Text('Logout',
                      style: AppTextStyles.body.copyWith(color: vt.danger)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: Sp.xs),
      ],
    );
  }

  // ── Demo banner ────────────────────────────────────────────────────────────
  Widget _buildDemoBanner(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: Sp.base, vertical: 10),
      decoration: BoxDecoration(
        color: context.vt.warning.withValues(alpha: 0.10),
        border: Border(
          bottom: BorderSide(color: context.vt.warning.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.science_outlined, color: context.vt.warning, size: 16),
          SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              'Demo Mode — Sample data only. Login with Zerodha to trade live.',
              style: AppTextStyles.caption.copyWith(color: context.vt.warning),
            ),
          ),
          GestureDetector(
            onTap: () => _handleLogout(context),
            child: Text('Login →',
                style: AppTextStyles.caption.copyWith(
                  color: context.vt.accentGreen,
                  fontWeight: FontWeight.w700,
                )),
          ),
        ],
      ),
    );
  }

  // ── Welcome row ────────────────────────────────────────────────────────────
  Widget _buildWelcomeRow(String name) {
    final vt = context.vt;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'T';
    return Row(
      children: [
        // Avatar — green gradient matching app logo
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Text(initial,
                style: AppTextStyles.h3.copyWith(color: Colors.white)),
          ),
        ),
        const SizedBox(width: Sp.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting, style: AppTextStyles.caption.copyWith(color: vt.textSecondary)),
              Text(name, style: AppTextStyles.h3.copyWith(color: vt.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Index strip ────────────────────────────────────────────────────────────
  Widget _buildIndexStrip() {
    final entries = [('NIFTY', '256265'), ('BANKNIFTY', '260105')];
    return Row(
      children: entries.indexed.map((item) {
        final (i, e) = item;
        final label = e.$1;
        final token = e.$2;
        final tick = _indexPrices[token] as Map<String, dynamic>?;
        final ltp = (tick?['last_price'] ?? 0.0) as num;
        final change = (tick?['net_change'] ?? 0.0) as num;
        final isUp = change >= 0;
        final color = isUp ? context.vt.accentGreen : context.vt.danger;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == 0 ? Sp.sm : 0),
            padding: EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
            decoration: BoxDecoration(
              color: context.vt.surface1,
              borderRadius: BorderRadius.circular(Rad.md),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: AppTextStyles.monoSm.copyWith(
                    color: context.vt.textSecondary, fontSize: 11)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      ltp == 0 ? '—' : ltp.toStringAsFixed(0),
                      style: AppTextStyles.monoSm.copyWith(color: context.vt.textPrimary),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isUp ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 9,
                          color: color,
                        ),
                        Text(
                          '${change.abs().toStringAsFixed(2)}%',
                          style: AppTextStyles.label.copyWith(color: color, fontSize: 9),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Balance / P&L hero card ────────────────────────────────────────────────
  Widget _buildBalanceCard(DashboardModel? data) {
    final vt = context.vt;
    final balance = data?.availableBalance ?? 0.0;
    final pnl = data?.todayPnl ?? 0.0;
    final pnlPct = data?.todayPnlPct ?? 0.0;
    final isPnlPos = pnl >= 0;
    final posCount = data?.positions.length ?? 0;
    final gttCount = data?.gtts.length ?? 0;
    final pnlColor = isPnlPos ? vt.accentGreen : vt.danger;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPnlPos
              ? [vt.accentGreen, vt.accentPurple]
              : [vt.danger, vt.accentPurple],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(Rad.xl),
      ),
      padding: const EdgeInsets.only(top: 3),
      child: Container(
        decoration: BoxDecoration(
          color: vt.surface1,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(Rad.xl - 1),
            topRight: const Radius.circular(Rad.xl - 1),
            bottomLeft: const Radius.circular(Rad.xl),
            bottomRight: const Radius.circular(Rad.xl),
          ),
        ),
        padding: const EdgeInsets.all(Sp.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Row(
              children: [
                Text('Available Balance',
                    style: AppTextStyles.caption
                        .copyWith(letterSpacing: 0.3)),
                const Spacer(),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: pnlColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  pnl == 0
                      ? 'No trades today'
                      : isPnlPos
                          ? 'In Profit'
                          : 'In Loss',
                  style: AppTextStyles.caption.copyWith(
                      color: pnlColor, fontSize: 11),
                ),
              ],
            ),

            const SizedBox(height: Sp.xs),

            // ── Balance hero ─────────────────────────────────────────────
            data == null
                ? const SkeletonBox(width: 200, height: 40, radius: Rad.sm)
                : PriceText(
                    value: balance,
                    style: AppTextStyles.display,
                    duration: const Duration(milliseconds: 800),
                  ),

            const SizedBox(height: Sp.md),

            // ── Metrics row ──────────────────────────────────────────────
            Row(
              children: [
                // Today's P&L box
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Sp.sm, vertical: Sp.sm),
                    decoration: BoxDecoration(
                      color: pnlColor.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(Rad.md),
                      border: Border.all(
                          color: pnlColor.withValues(alpha: 0.20)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Today's P&L",
                            style: AppTextStyles.caption
                                .copyWith(fontSize: 10)),
                        const SizedBox(height: 4),
                        data == null
                            ? const SkeletonBox(
                                width: 80, height: 16, radius: Rad.sm)
                            : PnlPill(pnl: pnl, pnlPct: pnlPct),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: Sp.sm),

                // Positions box
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Sp.sm, vertical: Sp.sm),
                    decoration: BoxDecoration(
                      color: vt.surface2,
                      borderRadius: BorderRadius.circular(Rad.md),
                      border: Border.all(color: vt.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Positions',
                            style: AppTextStyles.caption
                                .copyWith(fontSize: 10, color: vt.textSecondary)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              posCount > 0
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              size: 10,
                              color: posCount > 0
                                  ? vt.accentGreen
                                  : vt.textTertiary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              posCount > 0
                                  ? '$posCount Active'
                                  : 'None open',
                              style: AppTextStyles.monoSm.copyWith(
                                color: posCount > 0
                                    ? vt.textPrimary
                                    : vt.textTertiary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        if (gttCount > 0) ...[
                          const SizedBox(height: 2),
                          Text('$gttCount GTTs set',
                              style: AppTextStyles.caption
                                  .copyWith(fontSize: 10, color: vt.textTertiary)),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Add funds nudge ────────────────────────────────────────────────────────
  Widget _buildAddFundsCard() {
    return Container(
      margin: EdgeInsets.only(bottom: Sp.md),
      padding: EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: context.vt.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: context.vt.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              color: context.vt.warning, size: 18),
          SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              'Add funds to your Zerodha account to start trading.',
              style: AppTextStyles.caption.copyWith(color: context.vt.warning),
            ),
          ),
          SizedBox(width: Sp.sm),
          GestureDetector(
            onTap: () async {
              final uri = Uri.parse('https://kite.zerodha.com/funds');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Sp.sm, vertical: Sp.xs),
              decoration: BoxDecoration(
                color: context.vt.warning,
                borderRadius: BorderRadius.circular(Rad.sm),
              ),
              child: Text('Add Funds',
                  style: AppTextStyles.label.copyWith(
                      color: Colors.white, letterSpacing: 0)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Positions ──────────────────────────────────────────────────────────────
  Widget _buildInsightCard() {
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    final insight = _insights[dayOfYear % _insights.length];
    if (_insightDismissed) {
      return GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => AnalysisInputScreen())),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: Sp.base, vertical: Sp.sm),
          decoration: BoxDecoration(
            color: context.vt.surface2,
            borderRadius: BorderRadius.circular(Rad.md),
            border: Border.all(color: context.vt.accentPurple.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: context.vt.accentPurple),
              SizedBox(width: Sp.sm),
              Text('Analyse Market', style: AppTextStyles.caption.copyWith(color: context.vt.accentPurple)),
              Spacer(),
              Icon(Icons.chevron_right_rounded, size: 16, color: context.vt.accentPurple),
            ],
          ),
        ),
      );
    }
    return Dismissible(
      key: ValueKey('market_insight'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => setState(() => _insightDismissed = true),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(Sp.base),
        decoration: BoxDecoration(
          color: context.vt.surface2,
          borderRadius: BorderRadius.circular(Rad.lg),
          border: Border(left: BorderSide(color: context.vt.accentPurple, width: 3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 16, color: context.vt.accentPurple),
            SizedBox(width: Sp.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Market Pulse',
                      style: AppTextStyles.caption.copyWith(
                          color: context.vt.accentPurple, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(insight, style: AppTextStyles.body),
                ],
              ),
            ),
            SizedBox(width: Sp.sm),
            Icon(Icons.swipe_left_rounded, size: 14, color: context.vt.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionsList(List<PositionModel> positions) {
    return Column(
      children: positions.indexed.map((item) {
        final (i, pos) = item;
        final isPos = pos.pnl >= 0;
        return Padding(
          padding: EdgeInsets.only(bottom: i < positions.length - 1 ? Sp.sm : 0),
          child: VtAccentCard(
            accentColor: isPos ? context.vt.accentGreen : context.vt.danger,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pos.symbol, style: AppTextStyles.h3),
                      const SizedBox(height: 3),
                      Text(
                        'Qty: ${pos.quantity}  ·  Avg: ${_currency.format(pos.avgPrice)}  ·  LTP: ${_currency.format(pos.ltp)}',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                PnlPill(pnl: pos.pnl, pnlPct: pos.pnlPct),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── GTTs ───────────────────────────────────────────────────────────────────
  Widget _buildGttList(List<GttModel> gtts) {
    if (gtts.isEmpty) {
      return VtCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: Sp.xl),
            child: Column(
              children: [
                Icon(Icons.alarm_off_outlined,
                    size: 36, color: context.vt.textTertiary),
                const SizedBox(height: Sp.sm),
                Text('No active GTTs', style: AppTextStyles.bodySecondary),
              ],
            ),
          ),
        ),
      );
    }

    return VtCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: gtts.indexed.map((item) {
          final (i, g) = item;
          return _buildGttTile(g, isLast: i == gtts.length - 1);
        }).toList(),
      ),
    );
  }

  Widget _buildGttTile(GttModel g, {required bool isLast}) {
    final isTwoLeg = g.gttType.toLowerCase().contains('two');
    final isSell = g.transactionType.toUpperCase() == 'SELL';
    final isTriggered = g.status.toLowerCase() == 'triggered';
    final triggers = g.triggerValues;
    String triggerText;
    if (isTwoLeg && triggers.length >= 2) {
      triggerText =
          'SL: ${_currency.format(triggers[0])}  ·  Target: ${_currency.format(triggers[1])}';
    } else if (triggers.isNotEmpty) {
      triggerText = 'Trigger: ${_currency.format(triggers[0])}';
    } else {
      triggerText = 'No trigger set';
    }

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GttAnalysisScreen(gtt: g)),
      ),
      borderRadius: BorderRadius.circular(Rad.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Sp.base, vertical: Sp.md),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(color: context.vt.divider, width: 1)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.vt.accentPurpleDim,
                borderRadius: BorderRadius.circular(Rad.sm),
              ),
              child: Icon(
                isTwoLeg ? Icons.swap_vert : Icons.alarm_on,
                size: 16,
                color: context.vt.accentPurple,
              ),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(g.symbol, style: AppTextStyles.bodyLarge),
                      const SizedBox(width: Sp.sm),
                      StatusBadge(
                        label: isTwoLeg ? 'TWO-LEG' : 'SINGLE',
                        type: BadgeType.ai,
                      ),
                      if (isTriggered) ...[
                        const SizedBox(width: Sp.xs),
                        const StatusBadge(
                            label: 'TRIGGERED', type: BadgeType.warning),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Qty: ${g.quantity}  ·  $triggerText',
                    style: AppTextStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            StatusBadge(
              label: g.transactionType,
              type: isSell ? BadgeType.danger : BadgeType.success,
            ),
            SizedBox(width: Sp.sm),
            Icon(Icons.chevron_right,
                size: 16, color: context.vt.textTertiary),
          ],
        ),
      ),
    );
  }

  // ── Orders ─────────────────────────────────────────────────────────────────
  Widget _buildOrdersList(List<OrderModel> orders) {
    if (orders.isEmpty) {
      return VtCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: Sp.xl),
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 36, color: context.vt.textTertiary),
                const SizedBox(height: Sp.sm),
                Text('No orders today', style: AppTextStyles.bodySecondary),
              ],
            ),
          ),
        ),
      );
    }

    return VtCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: orders.take(15).indexed.map((item) {
          final (i, o) = item;
          return _buildOrderTile(
              o, isLast: i == (orders.length > 15 ? 14 : orders.length - 1));
        }).toList(),
      ),
    );
  }

  Widget _buildOrderTile(OrderModel o, {required bool isLast}) {
    final isBuy = o.transactionType.toUpperCase() == 'BUY';
    final statusColor = _statusColor(o.status);
    String timeStr = '';
    if (o.placedAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(o.placedAt).toLocal();
        timeStr = DateFormat('HH:mm').format(dt);
      } catch (_) {}
    }

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Sp.base, vertical: Sp.md),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: context.vt.divider, width: 1)),
      ),
      child: Row(
        children: [
          // Timeline dot
          Column(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          SizedBox(width: Sp.md),
          // Transaction badge
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Sp.sm, vertical: 3),
            decoration: BoxDecoration(
              color: (isBuy ? context.vt.accentGreen : context.vt.danger)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Rad.sm),
            ),
            child: Text(
              o.transactionType,
              style: AppTextStyles.label.copyWith(
                color: isBuy ? context.vt.accentGreen : context.vt.danger,
                letterSpacing: 0.5,
              ),
            ),
          ),
          SizedBox(width: Sp.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(o.symbol, style: AppTextStyles.bodyLarge),
                    const SizedBox(width: Sp.sm),
                    StatusBadge(
                      label: o.status,
                      type: _statusBadgeType(o.status),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Qty: ${o.filledQuantity}/${o.quantity}  ·  ${o.price > 0 ? _currency.format(o.price) : 'MARKET'}${timeStr.isNotEmpty ? '  ·  $timeStr' : ''}',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          if (o.statusMessage.isNotEmpty)
            Tooltip(
              message: o.statusMessage,
              child: Icon(Icons.info_outline,
                  size: 14, color: context.vt.textTertiary),
            ),
        ],
      ),
    );
  }

  Color _statusColor(String status) => switch (status.toUpperCase()) {
        'COMPLETE' => context.vt.accentGreen,
        'REJECTED' || 'CANCELLED' => context.vt.danger,
        'OPEN' || 'PENDING' => context.vt.warning,
        'TRIGGER PENDING' => Color(0xFF60A5FA),
        _ => context.vt.textTertiary,
      };

  BadgeType _statusBadgeType(String status) => switch (status.toUpperCase()) {
        'COMPLETE' => BadgeType.success,
        'REJECTED' || 'CANCELLED' => BadgeType.danger,
        'OPEN' || 'PENDING' => BadgeType.warning,
        'TRIGGER PENDING' => BadgeType.info,
        _ => BadgeType.neutral,
      };

  // ── Error card ─────────────────────────────────────────────────────────────
  Widget _buildErrorCard(String error) {
    final isSession = error.toLowerCase().contains('token') ||
        error.toLowerCase().contains('401');
    return VtCard(
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: Sp.xl),
          child: Column(
            children: [
              Icon(
                isSession ? Icons.lock_outline : Icons.wifi_off_rounded,
                size: 40,
                color: context.vt.warning,
              ),
              const SizedBox(height: Sp.md),
              Text(
                isSession ? 'Session unavailable' : 'Dashboard unavailable',
                style: AppTextStyles.h3,
              ),
              const SizedBox(height: Sp.sm),
              Text(
                error.replaceFirst('Exception: ', ''),
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySecondary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: Sp.base),
              VtButton(
                label: 'Retry',
                onPressed: _refresh,
                variant: VtButtonVariant.secondary,
                width: 120,
                height: 44,
                icon: Icon(Icons.refresh, size: 16,
                    color: context.vt.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom bar ─────────────────────────────────────────────────────────────
  Widget _buildBottomBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.vt.surface1,
        border: Border(top: BorderSide(color: context.vt.divider, width: 1)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sp.base, Sp.sm, Sp.base, Sp.sm),
          child: Row(
            children: [
              Expanded(
                child: VtButton(
                  label: 'AI Analysis',
                  icon: const Icon(Icons.auto_awesome, size: 16,
                      color: Colors.white),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AnalysisInputScreen()),
                  ),
                  height: 48,
                ),
              ),
              SizedBox(width: Sp.sm),
              Expanded(
                child: VtButton(
                  label: 'Holdings',
                  icon: Icon(Icons.account_balance_wallet_outlined,
                      size: 16, color: context.vt.textPrimary),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const HoldingsScreen()),
                  ),
                  variant: VtButtonVariant.secondary,
                  height: 48,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Logout',
                style: AppTextStyles.body.copyWith(color: context.vt.danger)),
          ),
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

class _StreakBadge extends StatefulWidget {
  final int days;
  _StreakBadge({required this.days});

  @override
  State<_StreakBadge> createState() => _StreakBadgeState();
}

class _StreakBadgeState extends State<_StreakBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _glow = Tween<double>(begin: 0.25, end: 0.65).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    if (widget.days >= 7) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gold = context.vt.accentGold;
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 4),
        decoration: BoxDecoration(
          color: gold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(Rad.pill),
          border: Border.all(color: gold.withValues(alpha: 0.35)),
          boxShadow: widget.days >= 7
              ? [BoxShadow(color: gold.withValues(alpha: _glow.value * 0.4), blurRadius: 10, spreadRadius: -2)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔥', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 3),
            Text(
              '${widget.days}',
              style: AppTextStyles.caption.copyWith(
                color: gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
