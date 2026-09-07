import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vesspay/features/wallet/models/deposit_account_model.dart';
import 'package:vesspay/features/wallet/models/crypto_deposit_model.dart';
import 'package:vesspay/core/providers.dart';
import 'package:vesspay/core/storage/currency_preference_storage.dart';
import 'package:vesspay/features/wallet/models/topup_model.dart';
import 'package:vesspay/features/wallet/models/wallet_balance_model.dart';
import 'package:vesspay/features/wallet/models/wallet_currency_model.dart';
import 'package:vesspay/features/wallet/repositories/wallet_repository.dart';
import 'package:vesspay/features/pay/models/transaction_model.dart';

/// Offline wallet repository for tests that only care about the currency the
/// wallet is held in, so no screen reaches for the network.
class FakeCurrencyWalletRepository implements WalletRepository {
  @override
  Future<List<CryptoChainModel>> getCryptoChains() async => const [];

  @override
  Future<CryptoAddressModel> getCryptoAddress(String chain) async =>
      CryptoAddressModel.unavailable(chain, 'not stubbed');

  @override
  Future<void> cancelTopup(String fundingTransactionId) async {}

  /// Last funding transaction a WeWire sandbox deposit was requested for.
  String? simulatedDepositFor;


  String? savedCurrency;

  /// Deposit-account state the gate should see. Defaults to a ready account so
  /// screens under test reach their real content.
  DepositAccountModel depositAccount;
  String? provisionedSourceOfFunds;
  int provisionCalls = 0;

  FakeCurrencyWalletRepository({
    this.savedCurrency,
    DepositAccountModel? depositAccount,
  }) : depositAccount = depositAccount ??
            const DepositAccountModel(
              state: DepositAccountState.ready,
              currency: 'USD',
            );

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
  Future<TopupResponseModel?> getPendingTopup({String currency = 'USD'}) async =>
      null;

  @override
  Future<TopupResponseModel> getTopupStatus(String fundingTransactionId) async =>
      throw UnimplementedError();


  @override
  Future<DepositAccountModel> getDepositAccount() async => depositAccount;

  @override
  Future<DepositAccountModel> provisionDepositAccount({
    String? sourceOfFunds,
  }) async {
    provisionCalls++;
    provisionedSourceOfFunds = sourceOfFunds;
    depositAccount = const DepositAccountModel(
      state: DepositAccountState.provisioning,
      currency: 'USD',
    );
    return depositAccount;
  }

  @override
  Future<void> simulateWeWireDeposit(String fundingTransactionId) async {
    simulatedDepositFor = fundingTransactionId;
  }

  /// Deposits this fake reports back into the activity feed.
  List<TransactionModel> deposits = [];

  /// Makes the deposit history unreachable, to prove the feed degrades to the
  /// payments it can still load.
  bool depositsThrow = false;

  @override
  Future<List<TransactionModel>> getDeposits() async {
    if (depositsThrow) {
      throw Exception('deposits unavailable');
    }
    return deposits;
  }

  @override
  Future<TransactionModel> getDepositById(String id) async =>
      deposits.firstWhere((d) => d.id == id);
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
