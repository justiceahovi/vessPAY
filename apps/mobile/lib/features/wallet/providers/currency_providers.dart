import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../auth/repositories/auth_repository.dart';
import '../models/wallet_currency_model.dart';
import '../repositories/wallet_repository.dart';
import 'wallet_providers.dart';

/// Wallet currencies offered by the backend, with an offline-safe fallback.
final supportedWalletCurrenciesProvider =
    FutureProvider<List<WalletCurrencyModel>>((ref) async {
  try {
    final repository = ref.watch(walletRepositoryProvider);
    final currencies = await repository.getSupportedCurrencies();
    if (currencies.isNotEmpty) return currencies;
    return kDefaultWalletCurrencies;
  } catch (_) {
    return kDefaultWalletCurrencies;
  }
});

/// The wallet currency this user chose, or null when they have not chosen yet.
///
/// The backend (User.primaryCurrency) is the source of truth so the choice
/// follows the user to any device; a local cache mirrors it so launch is instant
/// and the app keeps working offline. Launch trusts the cache and [refresh]
/// reconciles it with the server at sign-in.
final walletCurrencyProvider =
    AsyncNotifierProvider<WalletCurrencyNotifier, String?>(() {
  return WalletCurrencyNotifier();
});

class WalletCurrencyNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final storage = ref.watch(currencyPreferenceStorageProvider);
    final cached = await storage.getCurrency();

    // A cached choice is enough to render with; sign-in reconciles it.
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final user = await ref.watch(authRepositoryProvider).getProfile();
      final serverChoice = user.primaryCurrency;
      if (serverChoice != null && serverChoice.isNotEmpty) {
        await storage.saveCurrency(serverChoice);
        return serverChoice;
      }
      // Signed in, but this account has never picked a currency.
      return null;
    } catch (_) {
      // Offline or not signed in yet: nothing chosen that we can rely on.
      return null;
    }
  }

  /// Persists the user's choice on the server and locally, then publishes it.
  Future<String> select(String currencyCode) async {
    final normalized = currencyCode.trim().toUpperCase();
    final storage = ref.read(currencyPreferenceStorageProvider);
    state = const AsyncValue.loading();

    try {
      final stored = await ref
          .read(walletRepositoryProvider)
          .setPrimaryCurrency(normalized);
      await storage.saveCurrency(stored);
      state = AsyncValue.data(stored);
      // Balances are per-currency, so re-read them under the new choice.
      ref.invalidate(walletBalancesProvider);
      return stored;
    } catch (_) {
      // Keep the choice locally so the app stays usable; the next successful
      // sign-in refresh reconciles it with the server.
      await storage.saveCurrency(normalized);
      state = AsyncValue.data(normalized);
      rethrow;
    }
  }

  /// Re-reads the choice from the backend, e.g. right after signing in.
  /// Returns null when this account has not chosen a currency yet.
  Future<String?> refresh() async {
    state = await AsyncValue.guard(() async {
      final storage = ref.read(currencyPreferenceStorageProvider);
      final user = await ref.read(authRepositoryProvider).getProfile();
      final serverChoice = user.primaryCurrency;
      if (serverChoice != null && serverChoice.isNotEmpty) {
        await storage.saveCurrency(serverChoice);
        return serverChoice;
      }
      await storage.clearCurrency();
      return null;
    });
    return state.valueOrNull;
  }

  /// Drops the cached choice so one user's currency never leaks into the next
  /// session on a shared device.
  Future<void> clear() async {
    await ref.read(currencyPreferenceStorageProvider).clearCurrency();
    state = const AsyncValue.data(null);
  }
}

/// The currency code to render with right now, falling back to USD until the
/// user's own choice has loaded.
final activeWalletCurrencyCodeProvider = Provider<String>((ref) {
  return ref.watch(walletCurrencyProvider).valueOrNull ?? kDefaultWalletCurrency;
});

/// The resolved currency (symbol, flag, funding rail) used for formatting money
/// across the wallet, dashboard and top-up screens.
final activeWalletCurrencyProvider = Provider<WalletCurrencyModel>((ref) {
  final code = ref.watch(activeWalletCurrencyCodeProvider);
  final catalog = ref.watch(supportedWalletCurrenciesProvider).valueOrNull ??
      kDefaultWalletCurrencies;
  return resolveWalletCurrency(code, catalog: catalog);
});

/// True once we know the signed-in user still has to choose a currency.
final needsWalletCurrencyChoiceProvider = Provider<bool>((ref) {
  final currency = ref.watch(walletCurrencyProvider);
  return currency.hasValue && currency.value == null;
});
