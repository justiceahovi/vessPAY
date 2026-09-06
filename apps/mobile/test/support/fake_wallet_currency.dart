import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vesspay/core/providers.dart';
import 'package:vesspay/core/storage/currency_preference_storage.dart';
import 'package:vesspay/features/wallet/models/topup_model.dart';
import 'package:vesspay/features/wallet/models/wallet_balance_model.dart';
import 'package:vesspay/features/wallet/models/wallet_currency_model.dart';
import 'package:vesspay/features/wallet/repositories/wallet_repository.dart';

/// Offline wallet repository for tests that only care about the currency the
/// wallet is held in, so no screen reaches for the network.
class FakeCurrencyWalletRepository implements WalletRepository {
  String? savedCurrency;

  FakeCurrencyWalletRepository({this.savedCurrency});

  @override
  Future<List<WalletBalanceModel>> getBalances() async => [
        WalletBalanceModel(
          currency: savedCurrency ?? kDefaultWalletCurrency,
          balance: 500.0,
        ),
      ];

  @override
  Future<List<WalletCurrencyModel>> getSupportedCurrencies() async =>
      kDefaultWalletCurrencies;

  @override
  Future<String> setPrimaryCurrency(String currencyCode) async {
    savedCurrency = currencyCode.toUpperCase();
    return savedCurrency!;
  }

  @override
  Future<TopupResponseModel> initiateTopup({
    required double amount,
    String currency = kDefaultWalletCurrency,
  }) async =>
      throw UnimplementedError();

  @override
  Future<TopupResponseModel> getTopupStatus(String fundingTransactionId) async =>
      throw UnimplementedError();

  @override
  Future<TopupResponseModel> confirmTopup(String fundingTransactionId) async =>
      throw UnimplementedError();
}

/// Overrides that give a test a wallet already held in [currency], skipping the
/// first-run currency prompt. Pass null to model an account that never chose.
///
/// Set [includeRepository] to false when the test already supplies its own
/// wallet repository override.
List<Override> walletCurrencyOverrides({
  String? currency = 'USD',
  bool includeRepository = true,
}) {
  return [
    if (includeRepository)
      walletRepositoryProvider.overrideWithValue(
        FakeCurrencyWalletRepository(savedCurrency: currency),
      ),
    currencyPreferenceStorageProvider.overrideWithValue(
      InMemoryCurrencyPreferenceStorage(initialCurrency: currency),
    ),
  ];
}
