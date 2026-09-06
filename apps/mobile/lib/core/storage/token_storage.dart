import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class TokenStorage {
  Future<String?> getToken();
  Future<void> saveToken(String token);
  Future<void> deleteToken();
  Future<bool> hasToken();
}

class SecureTokenStorage implements TokenStorage {
  static const String _keyToken = 'vesspay_jwt_token';

  final FlutterSecureStorage _storage;

  SecureTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> getToken() async {
    try {
      return await _storage.read(key: _keyToken);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveToken(String token) async {
    await _storage.write(key: _keyToken, value: token);
  }

  @override
  Future<void> deleteToken() async {
    await _storage.delete(key: _keyToken);
  }

  @override
  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.trim().isNotEmpty;
  }
}

/// In-memory implementation of TokenStorage useful for unit testing
class InMemoryTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<String?> getToken() async => _token;

  @override
  Future<void> saveToken(String token) async {
    _token = token;
  }

  @override
  Future<void> deleteToken() async {
    _token = null;
  }

  @override
  Future<bool> hasToken() async => _token != null && _token!.trim().isNotEmpty;
}
