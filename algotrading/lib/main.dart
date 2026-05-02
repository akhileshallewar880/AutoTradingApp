import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/analysis_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/login_screen.dart';
import 'screens/api_settings_screen.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

/// Allows the app to connect to api.vantrade.in even when the device's trust
/// store doesn't recognise the intermediate CA (common on older Android).
class _TrustAllCerts extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => host.endsWith('vantrade.in');
  }
}

/// Global route observer — lets HomeScreen detect when it regains focus.
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _TrustAllCerts();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  Animate.restartOnHotReload = true;

  // Load persisted theme before first frame
  final themeProvider = ThemeProvider();
  await themeProvider.load();

  runApp(AlgoTradingApp(themeProvider: themeProvider));

  NotificationService.instance.initialize().then((_) {
    NotificationService.initializeTimezone().then((_) {
      NotificationService.instance.scheduleWeekdayLoginReminders();
    }).catchError((_) {});
  }).catchError((_) {});
}

class AlgoTradingApp extends StatelessWidget {
  const AlgoTradingApp({super.key, required this.themeProvider});
  final ThemeProvider themeProvider;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AnalysisProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (_, tp, _) => MaterialApp(
          title: 'VanTrade',
          debugShowCheckedModeBanner: false,
          navigatorObservers: [routeObserver],
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: tp.mode,
          builder: (context, child) {
            final theme = Theme.of(context);
            return DefaultTextStyle(
              style: theme.textTheme.bodyMedium!.copyWith(
                color: theme.colorScheme.onSurface,
              ),
              child: child!,
            );
          },
          initialRoute: '/',
          routes: {
            '/': (context) => const SplashScreen(),
            '/onboarding': (context) => const OnboardingScreen(),
            '/login': (context) => const LoginScreen(),
            '/api-settings': (context) => const ApiSettingsScreen(),
            '/home': (context) => const HomeScreen(),
          },
        ),
      ),
    );
  }
}
