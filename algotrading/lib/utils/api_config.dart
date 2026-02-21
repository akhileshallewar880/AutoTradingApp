class ApiConfig {
  // Base URL for the backend API
  // Change this based on your environment:
  // - Android Emulator: 'http://10.0.2.2:8000/api/v1'
  // - iOS Simulator: 'http://localhost:8000/api/v1'
  // - Real Device: 'http://192.168.x.x:8000/api/v1' (replace with your machine's IP)
  
  static const String baseUrl = 'https://vantradeapp-h6axgng8hkd9aqba.centralindia-01.azurewebsites.net/api/v1';
  
  // API Endpoints
  static const String loginUrl = '$baseUrl/auth/login';
  static const String sessionUrl = '$baseUrl/auth/session';
  static const String profileUrl = '$baseUrl/auth/profile';
  static const String logoutUrl = '$baseUrl/auth/logout';
  
  // Analysis endpoints
  static const String generateAnalysisUrl = '$baseUrl/analysis/generate';
  static String confirmAnalysisUrl(String id) => '$baseUrl/analysis/$id/confirm';
  static String executionStatusUrl(String id) => '$baseUrl/analysis/$id/status';
  static const String analysisHistoryUrl = '$baseUrl/analysis/history';

  // Dashboard endpoint
  static const String dashboardUrl = '$baseUrl/dashboard/summary';
  
  // Timeout duration - 2 minutes for analysis (yfinance + AI can be slow)
  static const Duration timeout = Duration(seconds: 120);
}
