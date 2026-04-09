import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../models/analysis_model.dart';
import '../models/dashboard_model.dart';
import '../models/live_trading_model.dart';
import '../utils/api_config.dart';

class ApiService {
  // Authentication
  static Future<String> getLoginUrl({required String apiKey}) async {
    final uri = Uri.parse(ApiConfig.loginUrl).replace(
      queryParameters: {'api_key': apiKey},
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['login_url'];
    } else {
      throw Exception('Failed to get login URL: ${response.body}');
    }
  }

  static Future<UserModel> createSession(
    String requestToken, {
    required String apiKey,
    required String apiSecret,
  }) async {
    final response = await http.post(
      Uri.parse(ApiConfig.sessionUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'request_token': requestToken,
        'api_key': apiKey,
        'api_secret': apiSecret,
      }),
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return UserModel.fromJson(data);
    } else {
      throw Exception('Failed to create session: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getProfile(String accessToken) async {
    final response = await http.get(
      Uri.parse(ApiConfig.profileUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).timeout(ApiConfig.timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get profile: ${response.body}');
    }
  }

  static Future<void> logout(String accessToken) async {
    final response = await http.post(
      Uri.parse(ApiConfig.logoutUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).timeout(ApiConfig.timeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to logout: ${response.body}');
    }
  }

  // Analysis
  static Future<AnalysisResponseModel> generateAnalysis({
    required String analysisDate,
    required int numStocks,
    required double riskPercent,
    required String accessToken,
    required String apiKey,
    required int userId,
    List<String> sectors = const ['ALL'],
    int holdDurationDays = 0,
    double capitalToUse = 0,
    int leverage = 1,
  }) async {
    final response = await http.post(
      Uri.parse(ApiConfig.generateAnalysisUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'analysis_date': analysisDate,
        'num_stocks': numStocks,
        'risk_percent': riskPercent,
        'access_token': accessToken,
        'api_key': apiKey,
        'user_id': userId,
        'sectors': sectors,
        'hold_duration_days': holdDurationDays,
        if (capitalToUse > 0) 'capital_to_use': capitalToUse,
        'leverage': leverage,
      }),
    ).timeout(ApiConfig.timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return AnalysisResponseModel.fromJson(data);
    } else {
      throw Exception('Failed to generate analysis: ${response.body}');
    }
  }

  static Future<void> confirmAnalysis({
    required String analysisId,
    required bool confirmed,
    String? notes,
    required String accessToken,
    required String apiKey,
    String? userId,
    int holdDurationDays = 0,
    List<Map<String, dynamic>>? stockOverrides,
  }) async {
    final response = await http.post(
      Uri.parse(ApiConfig.confirmAnalysisUrl(analysisId)),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'confirmed': confirmed,
        'access_token': accessToken,
        'api_key': apiKey,
        'user_notes': notes,
        'user_id': userId,
        'hold_duration_days': holdDurationDays,
        'stock_overrides': ?stockOverrides,
      }),
    ).timeout(ApiConfig.timeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to confirm analysis: ${response.body}');
    }
  }

  static Future<ExecutionStatusModel> getExecutionStatus({
    required String analysisId,
    required String accessToken,
  }) async {
    final response = await http.get(
      Uri.parse(ApiConfig.executionStatusUrl(analysisId)),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).timeout(ApiConfig.timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return ExecutionStatusModel.fromJson(data);
    } else {
      throw Exception('Failed to get execution status: ${response.body}');
    }
  }

  static Future<List<Map<String, dynamic>>> getAnalysisHistory({
    required String accessToken,
    int limit = 50,
  }) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.analysisHistoryUrl}?limit=$limit'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).timeout(ApiConfig.timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['analyses']);
    } else {
      throw Exception('Failed to get analysis history: ${response.body}');
    }
  }

  // Dashboard
  static Future<DashboardModel> getDashboard(
    String accessToken, {
    String? apiKey,
  }) async {
    final queryParams = {'access_token': accessToken};
    if (apiKey != null) {
      queryParams['api_key'] = apiKey;
    }

    final uri = Uri.parse(ApiConfig.dashboardUrl)
        .replace(queryParameters: queryParams);
    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      return DashboardModel.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 401) {
      throw Exception('SESSION_EXPIRED');
    } else {
      throw Exception('Failed to load dashboard: ${response.body}');
    }
  }

  /// Validate that the Zerodha access token is still alive.
  /// Returns true if valid, false if expired/invalid.
  /// Throws only on unexpected network errors.
  static Future<bool> validateToken({
    required String accessToken,
    required String apiKey,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/auth/validate-token')
          .replace(queryParameters: {
        'access_token': accessToken,
        'api_key': apiKey,
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (_) {
      // Network error — treat as inconclusive (let the home screen handle it)
      return true;
    }
  }

  // Live Trading (Autonomous Agent)
  static Future<void> startLiveAgent({
    required String userId,
    required String accessToken,
    required String apiKey,
    int maxPositions = 2,
    double riskPercent = 1.0,
    int scanIntervalMinutes = 5,
    int maxTradesPerDay = 6,
    double maxDailyLossPct = 2.0,
    double capitalToUse = 0.0,
    int leverage = 1,
  }) async {
    final response = await http.post(
      Uri.parse(ApiConfig.liveAgentStartUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'access_token': accessToken,
        'api_key': apiKey,
        'max_positions': maxPositions,
        'risk_percent': riskPercent,
        'scan_interval_minutes': scanIntervalMinutes,
        'max_trades_per_day': maxTradesPerDay,
        'max_daily_loss_pct': maxDailyLossPct,
        'capital_to_use': capitalToUse,
        'leverage': leverage,
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Failed to start agent: ${response.body}');
    }
  }

  static Future<void> stopLiveAgent({required String userId}) async {
    final uri = Uri.parse(ApiConfig.liveAgentStopUrl)
        .replace(queryParameters: {'user_id': userId});
    // 60s: squaring off multiple positions + cancelling GTTs can take time
    final response = await http.post(uri).timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw Exception('Failed to stop agent: ${response.body}');
    }
  }

  static Future<AgentStatusModel> getLiveAgentStatus({
    required String userId,
  }) async {
    final uri = Uri.parse(ApiConfig.liveAgentStatusUrl)
        .replace(queryParameters: {'user_id': userId});
    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      return AgentStatusModel.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to get agent status: ${response.body}');
    }
  }

  static Future<bool> validateZerodhaCredentials(
      String apiKey, String apiSecret) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/validate-zerodha-credentials'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'api_key': apiKey,
          'api_secret': apiSecret,
        }),
      ).timeout(const Duration(seconds: 90));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['valid'] == true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// Run intraday market analysis — same screener as the normal analysis feature.
  /// Returns a list of candidate stocks with entry, SL, and target price.
  /// No agent is started, no trades are placed.
  static Future<List<Map<String, dynamic>>> analyzeIntraday({
    required String userId,
    required String apiKey,
    required String accessToken,
    int limit = 5,
  }) async {
    final uri = Uri.parse(ApiConfig.liveAgentAnalyzeUrl).replace(
      queryParameters: {
        'user_id': userId,
        'api_key': apiKey,
        'access_token': accessToken,
        'limit': '$limit',
      },
    );
    // Analysis can be slow (screener + indicator calc) — use 2-minute timeout
    final response = await http.get(uri).timeout(const Duration(seconds: 120));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(
          data['candidates'] as List<dynamic>? ?? []);
    } else {
      throw Exception('Analyze failed: ${response.body}');
    }
  }

  /// Register a manually-executed position with the monitoring agent.
  static Future<void> registerPosition({
    required String userId,
    required String apiKey,
    required String accessToken,
    required String symbol,
    required String action,
    required int quantity,
    required double entryPrice,
    required double stopLoss,
    required double target,
    String? gttId,
    String entryOrderId = '',
    double atr = 0.0,
  }) async {
    final response = await http.post(
      Uri.parse(ApiConfig.liveAgentRegisterPositionUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'api_key': apiKey,
        'access_token': accessToken,
        'symbol': symbol,
        'action': action,
        'quantity': quantity,
        'entry_price': entryPrice,
        'stop_loss': stopLoss,
        'target': target,
        if (gttId != null) 'gtt_id': gttId,
        'entry_order_id': entryOrderId,
        'atr': atr,
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'Failed to register position');
    }
  }

  /// Fetch available equity balance from Zerodha margins.
  /// Returns {available, net, used}.
  static Future<Map<String, double>> getBalance({
    required String apiKey,
    required String accessToken,
  }) async {
    final uri = Uri.parse(ApiConfig.liveAgentBalanceUrl).replace(
      queryParameters: {
        'api_key': apiKey,
        'access_token': accessToken,
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'available': (data['available'] as num?)?.toDouble() ?? 0,
        'net': (data['net'] as num?)?.toDouble() ?? 0,
        'used': (data['used'] as num?)?.toDouble() ?? 0,
      };
    } else {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'Failed to fetch balance');
    }
  }

  /// Place a LIMIT order on Zerodha. The backend computes quantity from
  /// capital × risk% / |limitPrice - stopLoss|.
  /// Returns the full response map: {order_id, quantity, symbol, limit_price, …}
  static Future<Map<String, dynamic>> placeLimitOrder({
    required String userId,
    required String accessToken,
    required String apiKey,
    required String symbol,
    required String action,
    required double limitPrice,
    required double stopLoss,
    required double target,
    double atr = 0.0,
    double capitalToUse = 0.0,
    double riskPercent = 1.0,
    int leverage = 1,
    String orderType = 'LIMIT',
  }) async {
    final response = await http.post(
      Uri.parse(ApiConfig.liveAgentPlaceLimitOrderUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'api_key': apiKey,
        'access_token': accessToken,
        'symbol': symbol,
        'action': action,
        'limit_price': limitPrice,
        'stop_loss': stopLoss,
        'target': target,
        'atr': atr,
        'capital_to_use': capitalToUse,
        'risk_percent': riskPercent,
        'leverage': leverage,
        'order_type': orderType,
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'Failed to place limit order');
    }
  }
}

