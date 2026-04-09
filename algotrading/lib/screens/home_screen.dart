import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../models/dashboard_model.dart';
import '../widgets/info_card.dart';
import '../utils/api_config.dart';
import 'analysis_input_screen.dart';
import 'backtest_screen.dart';
import 'gtt_analysis_screen.dart';
import 'options_input_screen.dart';
import 'active_monitor_screen.dart';
import 'holdings_screen.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../services/active_trade_store.dart';
import '../services/auto_scanner_service.dart';
import '../services/notification_service.dart';
import '../services/alarm_permission_service.dart';
import 'alarm_permission_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'opportunity_execute_sheet.dart';
import 'opportunity_alarm_screen.dart';
import '../main.dart' show routeObserver;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware, WidgetsBindingObserver {
  final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  Map<String, dynamic>? _perfData;
  bool _perfLoading = false;
  String? _perfError;

  // ── Live index prices (KiteTicker snapshot) ────────────────────────────
  Map<String, dynamic> _indexPrices = {};
  Timer? _indexRefreshTimer;

  // ── Active options trade (persisted across app restarts) ───────────────
  ActiveTrade? _activeTrade;

  // ── Auto-scanner state ────────────────────────────────────────────────
  final _scanner = AutoScannerService.instance;

  // Guard: prevent pushing alarm screen twice for the same opportunity
  bool _alarmScreenVisible = false;

  // Alarm permission status — drives the setup banner in the scanner card
  AlarmPermissionStatus? _alarmPermStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scanner.loadState();
    _scanner.addListener(_onScannerChanged);
    FlutterForegroundTask.addTaskDataCallback(_onScannerTaskData);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initDashboard();
      _checkActiveTrade();
      _checkPendingOpportunity();
      _checkAlarmPermissions();
      routeObserver.subscribe(this, ModalRoute.of(context)!);
    });
  }

  @override
  void didPopNext() {
    // Called when user pops back to HomeScreen from any screen on top of it
    // (e.g. live commentary, options results, active monitor)
    _checkActiveTrade();
    _checkPendingOpportunity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // If a test alarm was armed, schedule it NOW (2 min from when app closes)
      _scheduleArmedTestAlarm();
    }
    // When the app comes back to foreground, check if a trade alarm is pending
    if (state == AppLifecycleState.resumed) {
      _checkActiveTrade();
      _checkPendingOpportunity();
    }
  }

  Future<void> _scheduleArmedTestAlarm() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('test_alarm_armed') != true) return;
    await prefs.remove('test_alarm_armed');
    await NotificationService.instance.scheduleTestAlarm(delaySeconds: 120);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    _indexRefreshTimer?.cancel();
    _scanner.removeListener(_onScannerChanged);
    FlutterForegroundTask.removeTaskDataCallback(_onScannerTaskData);
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
      _fetchPerformance();
      _fetchIndexPrices();
      // Refresh index prices every 30 seconds
      _indexRefreshTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _fetchIndexPrices(),
      );
    }
  }

  Future<void> _checkActiveTrade() async {
    final trade = await ActiveTradeStore.load();
    if (!mounted) return;
    setState(() => _activeTrade = trade);
  }

  // ── Scanner callbacks ─────────────────────────────────────────────────────

  /// Rebuild when scanner toggle state changes.
  void _onScannerChanged() {
    if (mounted) setState(() {});
  }

  /// Receive opportunity events from the background isolate.
  /// SharedPreferences are already written by the background isolate before
  /// this fires — just update in-memory state and show the alarm.
  void _onScannerTaskData(Object data) {
    if (data is! Map) return;
    if (data['event'] != 'OPPORTUNITY') return;
    final mode = data['mode'] as String? ?? '';
    final stocks = (data['stocks'] as List?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final optionsTrade = data['trade'] != null
        ? Map<String, dynamic>.from(data['trade'] as Map)
        : null;
    _scanner.onOpportunityReceived(mode,
        stocks: stocks,
        optionsTrade: optionsTrade,
        expiryDate: data['expiry_date'] as String?,
        analysisId: data['analysis_id'] as String?);
    // Prefs already saved by background isolate — just show the alarm.
    _checkPendingOpportunity();
  }

  /// Checks SharedPreferences for a pending alarm (e.g. app opened from
  /// notification tap while already dismissed from home, or after restart).
  Future<void> _checkPendingOpportunity() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('pending_opportunity');
    if (raw == null || !mounted) return;
    try {
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      final mode = payload['mode'] as String? ?? '';
      final stocks = (payload['stocks'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ?? [];
      final optionsTrade = payload['options_trade'] != null
          ? Map<String, dynamic>.from(payload['options_trade'] as Map)
          : null;
      final expiryDate = payload['expiry_date'] as String? ?? '';
      final analysisId = payload['analysis_id'] as String? ?? '';
      _pushAlarmScreen(
        mode: mode,
        stocks: stocks,
        optionsTrade: optionsTrade,
        expiryDate: expiryDate,
        analysisId: analysisId,
      );
    } catch (_) {
      // Corrupted payload — discard
      await prefs.remove('pending_opportunity');
    }
  }

  void _pushAlarmScreen({
    required String mode,
    required List<Map<String, dynamic>> stocks,
    Map<String, dynamic>? optionsTrade,
    required String expiryDate,
    required String analysisId,
  }) {
    if (_alarmScreenVisible) return; // already showing
    _alarmScreenVisible = true;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => OpportunityAlarmScreen(
          mode:         mode,
          stocks:       stocks,
          optionsTrade: optionsTrade,
          expiryDate:   expiryDate,
          analysisId:   analysisId,
        ),
      ),
    ).then((_) => _alarmScreenVisible = false);
  }

  /// Build credentials from current auth + dashboard state.
  ScanCreds _scanCreds() {
    final auth = context.read<AuthProvider>();
    final dash = context.read<DashboardProvider>();
    final capital = (dash.dashboard?.availableBalance ?? 10000).clamp(1000, double.infinity);
    return ScanCreds(
      apiKey:      auth.user?.apiKey      ?? '',
      accessToken: auth.user?.accessToken ?? '',
      capital:     capital.toDouble(),
      riskPercent: 2.0,
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
          // NIFTY 50 = 256265, NIFTY BANK = 260105
          'tokens': '256265,260105',
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() => _indexPrices = data['snapshot'] ?? {});
      }
    } catch (_) {
      // Silent fail — index strip is best-effort
    }
  }

  Future<void> _fetchPerformance() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null || auth.isDemoMode) return;
    if (mounted) setState(() { _perfLoading = true; _perfError = null; });
    try {
      final uri = Uri.parse(ApiConfig.monthlyPerformanceUrl).replace(
        queryParameters: {
          'access_token': auth.user!.accessToken,
          'api_key': auth.user!.apiKey,
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() => _perfData = jsonDecode(response.body));
      } else {
        // Surface the actual error from the server
        String msg;
        try {
          final body = jsonDecode(response.body);
          msg = body['detail'] ?? 'Server error ${response.statusCode}';
        } catch (_) {
          msg = 'Server error ${response.statusCode}';
        }
        setState(() => _perfError = msg);
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _perfError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _perfLoading = false);
    }
  }

  void _checkSessionExpired() {
    if (!mounted) return;
    final dash = context.read<DashboardProvider>();
    if (dash.sessionExpired) {
      _handleSessionExpired();
    }
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
      await Future.wait([
        context.read<DashboardProvider>().fetchDashboard(
          auth.user!.accessToken,
          apiKey: auth.user!.apiKey,
        ),
        _fetchPerformance(),
      ]);
      _checkSessionExpired();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final dash = context.watch<DashboardProvider>();
    final user = auth.user;

    return PopScope(
      canPop: false,
      child: Scaffold(
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
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'More',
              onSelected: (value) {
                if (value == 'backtest') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BacktestScreen()),
                  );
                } else if (value == 'logout') {
                  _handleLogout(context);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'backtest',
                  child: Row(
                    children: [
                      Icon(Icons.science_outlined, size: 20),
                      SizedBox(width: 10),
                      Text('Strategy Backtest'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 20),
                      SizedBox(width: 10),
                      Text('Logout'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        // ── Fixed bottom bar ───────────────────────────────────────────────
        bottomNavigationBar: _buildFixedBottomBar(context),
        body: Column(
          children: [
            // ── Demo-mode banner ─────────────────────────────────────────
            if (auth.isDemoMode)
              Material(
                color: const Color(0xFFFFF8E1), // amber[50]
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.science_outlined,
                        color: Colors.orange[800],
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Demo Mode — Sample data only. '
                          'Login with Zerodha to trade live.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[900],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _handleLogout(context),
                        child: Text(
                          'Login',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green[700],
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            Expanded(
              child: RefreshIndicator(
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
                      const SizedBox(height: 12),

                      // ── Active trade banner ───────────────────────────────────
                      if (_activeTrade != null)
                        _buildActiveTradeBar(_activeTrade!),
                      if (_activeTrade != null)
                        const SizedBox(height: 12),

                      // ── Live index prices strip ───────────────────────────────
                      if (!auth.isDemoMode && _indexPrices.isNotEmpty)
                        _buildIndexPriceStrip(),
                      if (!auth.isDemoMode && _indexPrices.isNotEmpty)
                        const SizedBox(height: 12),

                      // ── Auto-scanner toggle bar ───────────────────────────────
                      if (!auth.isDemoMode)
                        _buildScannerBar(),
                      if (!auth.isDemoMode)
                        const SizedBox(height: 12),

                      // ── Dashboard content ────────────────────────────────────
                      if (dash.error != null && dash.dashboard == null)
                        _buildErrorCard(dash.error!)
                      else ...[
                        _buildBalancePnlCard(dash.dashboard),
                        const SizedBox(height: 12),
                        // Show "Add funds" message when balance is 0
                        if ((dash.dashboard?.availableBalance ?? 0) == 0)
                          InfoCard(
                            type: InfoCardType.warning,
                            title: '💰 Add Funds to Get Started',
                            message:
                                'Your Zerodha account balance is zero. Add funds to your account to start trading with VanTrade.',
                            actions: [
                              ElevatedButton.icon(
                                onPressed: () async {
                                  final uri = Uri.parse(
                                    'https://kite.zerodha.com/funds',
                                  );
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                },
                                icon: const Icon(Icons.open_in_new, size: 16),
                                label: const Text('Add Funds'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber[700],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          const SizedBox.shrink(),
                        const SizedBox(height: 12),
                        _buildMonthCard(dash.dashboard, _perfData, _perfLoading, perfError: _perfError),
                        const SizedBox(height: 12),
                        if ((dash.dashboard?.positions.isNotEmpty ??
                            false)) ...[
                          _buildSectionHeader(
                            'Open Positions',
                            Icons.show_chart,
                            Colors.indigo,
                          ),
                          const SizedBox(height: 8),
                          _buildPositionsList(dash.dashboard!.positions),
                          const SizedBox(height: 12),
                        ],
                        _buildSectionHeader(
                          'Active GTTs',
                          Icons.alarm_on,
                          Colors.deepPurple,
                        ),
                        const SizedBox(height: 8),
                        _buildGttList(dash.dashboard?.gtts ?? []),
                        const SizedBox(height: 12),
                        _buildSectionHeader(
                          'Today\'s Orders',
                          Icons.receipt_long,
                          Colors.blueGrey,
                        ),
                        const SizedBox(height: 8),
                        _buildOrdersList(dash.dashboard?.orders ?? []),
                      ],
                    ],
                  ),
                ),
              ),
            ), // Expanded
          ], // outer Column children
        ), // outer Column
      ), // Scaffold
    ); // PopScope
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
              Text(
                greeting,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
          color: isOpen ? Colors.green[300]! : Colors.red[300]!,
        ),
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

  // ── Auto-scanner bar ─────────────────────────────────────────────────────
  Widget _buildScannerBar() {
    final isOpen = _isMarketCurrentlyOpen();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(Icons.radar, size: 16, color: Colors.green[700]),
              const SizedBox(width: 6),
              Text(
                'Auto Scanner',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[800],
                ),
              ),
              const Spacer(),
              if (_scanner.anyEnabled)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pulsing green dot
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.4, end: 1.0),
                      duration: const Duration(milliseconds: 900),
                      builder: (_, v, child) => Opacity(opacity: v, child: child),
                      onEnd: () => setState(() {}),
                      child: Container(
                        width: 7, height: 7,
                        decoration: const BoxDecoration(
                          color: Colors.green, shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isOpen ? 'Scanning every 3 min' : 'Market closed',
                      style: TextStyle(
                        fontSize: 11,
                        color: isOpen ? Colors.green[700] : Colors.orange[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  'Off — tap to enable',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
            ],
          ),

          const SizedBox(height: 10),

          // Toggle buttons row
          Row(
            children: [
              _scanToggle(
                label: 'Stocks',
                icon: Icons.show_chart,
                active: _scanner.stocksEnabled,
                onTap: () async {
                  final creds = _scanCreds();
                  if (creds.apiKey.isEmpty) return;
                  await _scanner.toggleStocks(!_scanner.stocksEnabled, creds: creds);
                },
              ),
              const SizedBox(width: 8),
              _scanToggle(
                label: 'NIFTY',
                icon: Icons.trending_up,
                active: _scanner.niftyEnabled,
                onTap: () async {
                  final creds = _scanCreds();
                  if (creds.apiKey.isEmpty) return;
                  await _scanner.toggleNifty(!_scanner.niftyEnabled, creds: creds);
                },
              ),
              const SizedBox(width: 8),
              _scanToggle(
                label: 'BANKNIFTY',
                icon: Icons.account_balance,
                active: _scanner.bankniftyEnabled,
                onTap: () async {
                  final creds = _scanCreds();
                  if (creds.apiKey.isEmpty) return;
                  await _scanner.toggleBanknifty(!_scanner.bankniftyEnabled, creds: creds);
                },
              ),
            ],
          ),

          // Alarm permission warning banner
          if (_alarmPermStatus != null && !_alarmPermStatus!.allGranted) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AlarmPermissionScreen(fromSettings: true),
                ));
                _checkAlarmPermissions();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Alarm permissions not set up — tap to fix so trade alerts wake your screen.',
                        style: TextStyle(fontSize: 12, color: Colors.orange[900], fontWeight: FontWeight.w500),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.orange[700], size: 18),
                  ],
                ),
              ),
            ),
          ],


          // Last opportunity — actionable banner with execute button
          if (_scanner.lastOpportunityTime != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _openOpportunitySheet(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green[400]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.notifications_active, size: 16, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Opportunity — ${_scanner.lastOpportunityMode}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[900],
                            ),
                          ),
                          if (_scanner.lastOpportunityStocks.isNotEmpty)
                            Text(
                              _scanner.lastOpportunityStocks
                                  .map((s) => s['stock_symbol'] as String? ?? '')
                                  .take(3)
                                  .join(', '),
                              style: TextStyle(fontSize: 11, color: Colors.green[700]),
                            ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => _openOpportunitySheet(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Review & Execute',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _scanToggle({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? Colors.green[700] : Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? Colors.green[700]! : Colors.grey[300]!,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: active ? Colors.white : Colors.grey[500],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  /// Checks alarm permissions and auto-shows setup screen on first encounter.
  Future<void> _checkAlarmPermissions() async {
    final status = await AlarmPermissionService.instance.checkAll();
    if (!mounted) return;
    setState(() => _alarmPermStatus = status);

    // Auto-show the setup screen once if permissions are missing
    if (!status.allGranted) {
      final prefs = await SharedPreferences.getInstance();
      final shown = prefs.getBool('alarm_perm_screen_shown') ?? false;
      if (!shown && mounted) {
        await prefs.setBool('alarm_perm_screen_shown', true);
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const AlarmPermissionScreen(),
        ));
        // Re-check after returning
        if (mounted) _checkAlarmPermissions();
      }
    }
  }

  void _openOpportunitySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OpportunityExecuteSheet(
        mode:         _scanner.lastOpportunityMode,
        stocks:       _scanner.lastOpportunityStocks,
        optionsTrade: _scanner.lastOpportunityOptionsTrade,
        expiryDate:   _scanner.lastOpportunityExpiryDate,
        analysisId:   _scanner.lastOpportunityAnalysisId,
      ),
    );
  }

  bool _isMarketCurrentlyOpen() {
    final now = DateTime.now();
    if (now.weekday >= 6) return false;
    final t = now.hour * 60 + now.minute;
    return t >= 555 && t <= 930;
  }

  // ── Active trade banner ──────────────────────────────────────────────────
  Widget _buildActiveTradeBar(ActiveTrade trade) {
    final isCE = trade.optionType == 'CE';
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ActiveMonitorScreen(trade: trade),
          ),
        );
        // Re-check after returning — trade may have ended
        if (mounted) _checkActiveTrade();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.grey[900]!, Colors.grey[850]!],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            // Pulsing dot
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.3, end: 1.0),
              duration: const Duration(milliseconds: 900),
              builder: (_, v, child) => Opacity(opacity: v, child: child),
              onEnd: () => setState(() {}),
              child: Container(
                width: 10, height: 10,
                decoration: const BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Live Trade Active',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${trade.symbol}  ${isCE ? "CE ▲" : "PE ▼"}  '
                    'Entry ₹${trade.entryFillPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
              ),
              child: const Text(
                'View',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Live Index Price Strip ───────────────────────────────────────────────
  Widget _buildIndexPriceStrip() {
    final entries = [
      ('NIFTY', '256265'),
      ('BANKNIFTY', '260105'),
    ];
    return Row(
      children: entries.map((e) {
        final label = e.$1;
        final token = e.$2;
        final tick = _indexPrices[token] as Map<String, dynamic>?;
        final ltp = (tick?['last_price'] ?? 0.0) as num;
        final change = (tick?['net_change'] ?? 0.0) as num;
        final isUp = change >= 0;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: label == 'NIFTY' ? 6 : 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isUp ? Colors.green[200]! : Colors.red[200]!,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      ltp == 0 ? '—' : _currency.format(ltp),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(
                          isUp ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 10,
                          color: isUp ? Colors.green[600] : Colors.red[600],
                        ),
                        Text(
                          '${change.abs().toStringAsFixed(2)}%',
                          style: TextStyle(
                            fontSize: 10,
                            color: isUp ? Colors.green[600] : Colors.red[600],
                          ),
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
                const Text(
                  'Available Balance',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Icon(
                  Icons.account_balance_wallet,
                  color: Colors.white54,
                  size: 18,
                ),
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
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Today's P&L",
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
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
                                color: Colors.white.withValues(alpha: 0.7),
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
  Widget _buildMonthCard(DashboardModel? data, Map<String, dynamic>? perf, bool perfLoading, {String? perfError}) {
    final monthPnl = data?.monthPnl ?? 0.0;
    final trades = data?.monthTrades ?? 0;
    final winRate = data?.monthWinRate ?? 0.0;
    final wins = data?.monthWins ?? 0;
    final losses = data?.monthLosses ?? 0;
    final isPositive = monthPnl >= 0;
    final monthLabel = DateFormat('MMMM yyyy').format(DateTime.now());

    final grossProfit = perf != null ? ((perf['gross_profit'] as num?) ?? 0).toDouble() : null;
    final grossLoss = perf != null ? ((perf['gross_loss'] as num?) ?? 0).toDouble() : null;
    final charges = perf != null ? ((perf['total_charges'] as num?) ?? 0).toDouble() : null;
    final netPnl = perf != null ? ((perf['net_pnl'] as num?) ?? 0).toDouble() : null;

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
                Text(
                  '$monthLabel Performance',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                    value: data == null
                        ? '—'
                        : '${winRate.toStringAsFixed(1)}%',
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
                  Text(
                    '$wins wins',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '$losses losses',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.red[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],

            // ── Profit / Loss / Charges from Zerodha API ─────────────────
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            if (perfLoading)
              const Center(
                child: SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (perfError != null)
              Row(
                children: [
                  Icon(Icons.error_outline, size: 14, color: Colors.red[400]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      perfError,
                      style: TextStyle(fontSize: 11, color: Colors.red[600]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _fetchPerformance,
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Retry', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue[700],
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              )
            else ...[
              Row(
                children: [
                  _buildPerfTile('Profit', grossProfit, Colors.green[700]!),
                  const SizedBox(width: 8),
                  _buildPerfTile('Loss', grossLoss, Colors.red[600]!, isLoss: true),
                  const SizedBox(width: 8),
                  _buildPerfTile('Charges', charges, Colors.orange[700]!, isLoss: true),
                ],
              ),
              if (netPnl != null) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Net P&L (after charges)',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    Text(
                      '${netPnl >= 0 ? '+' : ''}${_currency.format(netPnl)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: netPnl >= 0 ? Colors.green[700] : Colors.red[600],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPerfTile(String label, double? value, Color color, {bool isLoss = false}) {
    final display = value == null
        ? '—'
        : '${isLoss ? '' : '+'}${_currency.format(value)}';
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            const SizedBox(height: 3),
            Text(
              display,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
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
            title: Text(
              pos.symbol,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              'Qty: ${pos.quantity}  •  Avg: ${_currency.format(pos.avgPrice)}  •  LTP: ${_currency.format(pos.ltp)}',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
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
                    color: isPos ? Colors.green[600] : Colors.red[500],
                  ),
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
                Icon(
                  Icons.alarm_off_outlined,
                  size: 40,
                  color: Colors.grey[300],
                ),
                const SizedBox(height: 8),
                Text(
                  'No active GTTs',
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                ),
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
      child: Column(children: gtts.map((g) => _buildGttTile(g)).toList()),
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
        MaterialPageRoute(builder: (_) => GttAnalysisScreen(gtt: g)),
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
              Text(
                g.symbol,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (isTwoLeg ? Colors.deepPurple : Colors.orange)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isTwoLeg ? 'TWO-LEG' : 'SINGLE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: isTwoLeg
                        ? Colors.deepPurple[700]
                        : Colors.orange[700],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (isTriggered)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'TRIGGERED',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber[800],
                    ),
                  ),
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
                Icon(
                  Icons.receipt_long_outlined,
                  size: 40,
                  color: Colors.grey[300],
                ),
                const SizedBox(height: 8),
                Text(
                  'No orders today',
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                ),
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
            Text(
              o.symbol,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                o.status,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
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
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Colors.grey[400],
                ),
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
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
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
                      builder: (_) => const AnalysisInputScreen(),
                    ),
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
                          'Analysis',
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
            const SizedBox(width: 8),
            // Options Trading button
            Expanded(
              child: Material(
                color: const Color(0xFF7C3AED),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OptionsInputScreen(),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 13),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.candlestick_chart, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Options',
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
            const SizedBox(width: 8),
            // Holdings button
            Expanded(
              child: Material(
                color: Colors.indigo[700],
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const HoldingsScreen(),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 13),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.account_balance_wallet,
                            color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Holdings',
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
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard(String error) {
    final isMarketClosed =
        error.toLowerCase().contains('market') ||
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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout'),
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
        color: Colors.white.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
