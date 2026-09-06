import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Local cache of the wallet currency the user chose.
///
/// The server is the source of truth (User.primaryCurrency); this cache lets the
/// app render the right symbols on launch before /api/auth/me comes back, and keeps
/// the choice usable while offline.
abstract class CurrencyPreferenceStorage {
  Future<String?> getCurrency();
  Future<void> saveCurrency(String currencyCode);
  Future<void> clearCurrency();
}

class SecureCurrencyPreferenceStorage implements CurrencyPreferenceStorage {
  static const String _keyCurrency = 'vesspay_wallet_currency';

  final FlutterSecureStorage _storage;

  SecureCurrencyPreferenceStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> getCurrency() async {
    try {
      final value = await _storage.read(key: _keyCurrency);
      if (value == null || value.trim().isEmpty) return null;
      return value.trim().toUpperCase();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveCurrency(String currencyCode) async {
    try {
      await _storage.write(
        key: _keyCurrency,
        value: currencyCode.trim().toUpperCase(),
      );
    } catch (_) {
      // A failed cache write is not fatal; the server still holds the choice.
    }
  }

  @override
  Future<void> clearCurrency() async {
    try {
      await _storage.delete(key: _keyCurrency);
    } catch (_) {
      // Ignore: nothing to clean up if secure storage is unavailable.
    }
  }
}

/// In-memory implementation useful for widget and unit tests.
class InMemoryCurrencyPreferenceStorage implements CurrencyPreferenceStorage {
  String? _currency;

  InMemoryCurrencyPreferenceStorage({String? initialCurrency})
      : _currency = initialCurrency;

  @override
  Future<String?> getCurrency() async => _currency;

  @override
  Future<void> saveCurrency(String currencyCode) async {
    _currency = currencyCode.trim().toUpperCase();
  }

  @override
  Future<void> clearCurrency() async {
    _currency = null;
  }
}
