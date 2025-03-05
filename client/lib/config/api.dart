import './env.dart';

class ApiConfig {
  static String get baseUrl => Env.apiBaseUrl;

  static String get versionUrl => '$baseUrl/version';
  static String get downloadUrl => '$baseUrl/app-release.apk';
  static String getReportUrl(String sd) => '$baseUrl/result/$sd.html';
} 