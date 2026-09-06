class AppConfig {
  AppConfig._();

  static String? _overrideBaseUrl;

  /// Default local backend port
  static const int defaultPort = 3000;

  /// Production Railway backend URL
  static const String productionUrl = 'https://vesspay-production.up.railway.app';

  /// Retrieves the backend base URL.
  /// Priority:
  /// 1. Runtime override (set via `setBaseUrl`)
  /// 2. Dart compile-time environment variable `API_BASE_URL`
  /// 3. Production Railway URL (default)
  static String get baseUrl {
    if (_overrideBaseUrl != null && _overrideBaseUrl!.isNotEmpty) {
      return _overrideBaseUrl!;
    }

    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }

    return productionUrl;
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
