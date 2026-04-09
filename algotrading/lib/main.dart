import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/auth_provider.dart';
import 'providers/analysis_provider.dart';
import 'providers/dashboard_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/login_screen.dart';
import 'screens/api_settings_screen.dart';
import 'screens/home_screen.dart';
import 'screens/opportunity_alarm_screen.dart';
import 'services/monitoring_foreground_service.dart';
import 'services/notification_service.dart';
import 'services/auto_scanner_service.dart';

/// Global route observer — lets HomeScreen detect when it regains focus.
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

/// Global navigator key — lets us push the alarm screen from anywhere,
/// including notification tap callbacks that have no BuildContext.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  MonitoringForegroundService.init();
  await AutoScannerService.instance.loadState();

  // runApp FIRST so permission dialogs appear over a real screen
  runApp(const AlgoTradingApp());

  // Notifications: set up AFTER runApp so permission dialog appears over splash
  _initNotifications();
}

void _initNotifications() {
  // Wire the alarm-tap callback before initialising so it catches the launch tap
  NotificationService.onAlarmTap = _showAlarmFromPrefs;

  NotificationService.instance.initialize().then((_) {
    NotificationService.initializeTimezone().then((_) {
      NotificationService.instance.scheduleWeekdayLoginReminders();
    }).catchError((_) {});
  }).catchError((_) {});
}

/// Called by NotificationService when the opportunity alarm notification is tapped.
/// Reads the pending payload from SharedPreferences and pushes OpportunityAlarmScreen
/// via the global navigator key (works from any isolate/callback context).
Future<void> _showAlarmFromPrefs() async {
  // Wait up to 3 s for the navigator to be ready (first-launch case)
  for (int i = 0; i < 30; i++) {
    if (navigatorKey.currentState != null) break;
    await Future.delayed(const Duration(milliseconds: 100));
  }
  final nav = navigatorKey.currentState;
  if (nav == null) return;

  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('pending_opportunity');
  if (raw == null) return;

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

    // Pop everything back to the root (avoids stacking alarms)
    nav.popUntil((route) => route.isFirst);
    nav.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => OpportunityAlarmScreen(
        mode:         mode,
        stocks:       stocks,
        optionsTrade: optionsTrade,
        expiryDate:   expiryDate,
        analysisId:   analysisId,
      ),
    ));
  } catch (_) {
    prefs.remove('pending_opportunity');
  }
}

class AlgoTradingApp extends StatelessWidget {
  const AlgoTradingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AnalysisProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
      ],
      child: MaterialApp(
        title: 'VanTrade',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        navigatorObservers: [routeObserver],
        theme: ThemeData(
          primarySwatch: Colors.green,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.green,
            primary: Colors.green[700]!,
          ),
          useMaterial3: true,
          cardTheme: const CardThemeData(
            elevation: 2,
          ),
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/onboarding': (context) => const OnboardingScreen(),
          '/login': (context) => const LoginScreen(),
          '/api-settings': (context) => const ApiSettingsScreen(),
          '/home': (context) => const HomeScreen(),
        },
      ),
    );
  }
}
