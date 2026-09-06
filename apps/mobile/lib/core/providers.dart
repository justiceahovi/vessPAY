import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api/api_client.dart';
import 'storage/currency_preference_storage.dart';
import 'storage/token_storage.dart';

/// Provides the active TokenStorage implementation (defaults to SecureTokenStorage)
final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return SecureTokenStorage();
});

/// Provides the local cache of the user's chosen wallet currency
final currencyPreferenceStorageProvider =
    Provider<CurrencyPreferenceStorage>((ref) {
  return SecureCurrencyPreferenceStorage();
});

/// Provides the shared ApiClient instance
final apiClientProvider = Provider<ApiClient>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  return ApiClient(tokenStorage: tokenStorage);
});
