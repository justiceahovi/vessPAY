import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class AppConfig {
  AppConfig._();

  static String? _overrideBaseUrl;

  /// Default local backend port
  static const int defaultPort = 3000;

  /// Retrieves the backend base URL.
  /// Priority:
  /// 1. Runtime override (set via `setBaseUrl`)
  /// 2. Dart compile-time environment variable `API_BASE_URL`
  /// 3. Platform-aware local URL:
  ///    - Android emulator: `http://10.0.2.2:3000`
  ///    - Web / iOS / Desktop / macOS / Windows / Linux: `http://localhost:3000`
  static String get baseUrl {
    if (_overrideBaseUrl != null && _overrideBaseUrl!.isNotEmpty) {
      return _overrideBaseUrl!;
    }

    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }

    if (!kIsWeb) {
      try {
        if (Platform.isAndroid) {
          return 'http://10.0.2.2:$defaultPort';
        }
      } catch (_) {
        // Fall back to localhost if Platform is not available in environment
      }
    }

    return 'http://localhost:$defaultPort';
  }

  /// Sets a runtime override for the base URL (useful for testing or dynamic environment switching).
  static void setBaseUrl(String? url) {
    _overrideBaseUrl = url;
  }

  /// Connection timeout in milliseconds
  static const Duration connectTimeout = Duration(seconds: 10);

  /// Receive timeout in milliseconds
  static const Duration receiveTimeout = Duration(seconds: 10);
}
