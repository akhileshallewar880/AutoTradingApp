import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../models/analysis_model.dart';
import '../models/dashboard_model.dart';
import '../utils/api_config.dart';

class ApiService {
  // Authentication
  static Future<String> getLoginUrl() async {
    final response = await http.get(
      Uri.parse(ApiConfig.loginUrl),
    ).timeout(ApiConfig.timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['login_url'];
    } else {
      throw Exception('Failed to get login URL: ${response.body}');
    }
  }

  static Future<UserModel> createSession(String requestToken) async {
    final response = await http.post(
      Uri.parse(ApiConfig.sessionUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'request_token': requestToken}),
    ).timeout(ApiConfig.timeout);

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
    List<String> sectors = const ['ALL'],
    int holdDurationDays = 0,
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
        'sectors': sectors,
        'hold_duration_days': holdDurationDays,
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
        'user_notes': notes,
        'hold_duration_days': holdDurationDays,
        if (stockOverrides != null) 'stock_overrides': stockOverrides,
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
  static Future<DashboardModel> getDashboard(String accessToken) async {
    final uri = Uri.parse(ApiConfig.dashboardUrl)
        .replace(queryParameters: {'access_token': accessToken});
    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      return DashboardModel.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load dashboard: ${response.body}');
    }
  }
}
