import 'dart:io';

class Env {
  static String get apiBaseUrl {
    // 从环境变量获取，如果没有则使用默认值
    return Platform.environment['API_BASE_URL'] ?? 'http://192.168.0.1:8000';
  }

  static bool get isDevelopment {
    return Platform.environment['FLUTTER_ENV'] == 'development';
  }

  static bool get isProduction {
    return Platform.environment['FLUTTER_ENV'] == 'production';
  }
} 
