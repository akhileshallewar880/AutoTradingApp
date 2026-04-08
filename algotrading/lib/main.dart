import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/analysis_provider.dart';
import 'providers/dashboard_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/login_screen.dart';
import 'screens/api_settings_screen.dart';
import 'screens/home_screen.dart';
import 'services/monitoring_foreground_service.dart';
import 'services/notification_service.dart';
import 'services/auto_scanner_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Initialize foreground task options (must run before startMonitoring / scanner)
  MonitoringForegroundService.init();
  // Initialize timezone data (required before any zonedSchedule calls)
  await NotificationService.initializeTimezone();
  // Initialize local push notifications (including opportunity alarm channel)
  await NotificationService.instance.initialize();
  // Schedule weekday (Mon–Fri) 09:00 login reminders
  await NotificationService.instance.scheduleWeekdayLoginReminders();
  // Restore scanner toggle state from previous session
  await AutoScannerService.instance.loadState();
  runApp(const AlgoTradingApp());
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
