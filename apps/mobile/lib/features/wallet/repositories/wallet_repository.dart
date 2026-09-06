import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/providers.dart';
import '../models/deposit_account_model.dart';
import '../models/topup_model.dart';
import '../models/wallet_balance_model.dart';
import '../models/wallet_currency_model.dart';

abstract class WalletRepository {
  Future<List<WalletBalanceModel>> getBalances();

  /// Wallet currencies the user is allowed to hold and deposit into.
  Future<List<WalletCurrencyModel>> getSupportedCurrencies();

  /// Persists the user's wallet currency choice and returns the stored code.
  Future<String> setPrimaryCurrency(String currencyCode);

  /// Where the user is in deposit-account setup. Read-only, safe to poll.
  Future<DepositAccountModel> getDepositAccount();

  /// Stores the user's own source-of-funds declaration when given, then asks
  /// WeWire to issue the account. Issuance is asynchronous.
  Future<DepositAccountModel> provisionDepositAccount({String? sourceOfFunds});

  Future<TopupResponseModel> initiateTopup({
    required double amount,
    String currency = kDefaultWalletCurrency,
  });
  Future<TopupResponseModel> getTopupStatus(String fundingTransactionId);
  Future<TopupResponseModel> confirmTopup(String fundingTransactionId);

  /// Asks WeWire to drop a sandbox deposit onto the user's real virtual
  /// account. The wallet is credited by the resulting pay-in webhook, not by
  /// this call, so the caller has to wait for the balance rather than assume it.
  Future<void> simulateWeWireDeposit(String fundingTransactionId);
}

class ApiWalletRepository implements WalletRepository {
  final ApiClient _apiClient;

  ApiWalletRepository(this._apiClient);

  @override
  Future<List<WalletBalanceModel>> getBalances() async {
    return _apiClient.get<List<WalletBalanceModel>>(
      '/api/wallet/balances',
      fromJson: (data) {
        if (data is List) {
          return data
              .map((item) =>
                  WalletBalanceModel.fromJson(item as Map<String, dynamic>))
              .toList();
        }
        return [];
      },
    );
  }

  @override
  Future<List<WalletCurrencyModel>> getSupportedCurrencies() async {
    return _apiClient.get<List<WalletCurrencyModel>>(
      '/api/wallet/currencies',
      fromJson: (data) {
        final list = data is Map<String, dynamic> ? data['currencies'] : data;
        if (list is List) {
          return list
              .map((item) =>
                  WalletCurrencyModel.fromJson(item as Map<String, dynamic>))
              .toList();
        }
        return const <WalletCurrencyModel>[];
      },
    );
  }

  @override
  Future<String> setPrimaryCurrency(String currencyCode) async {
    return _apiClient.put<String>(
      '/api/wallet/currency',
      data: {'currency': currencyCode.trim().toUpperCase()},
      fromJson: (data) {
        if (data is Map<String, dynamic>) {
          final stored = data['primaryCurrency'];
          if (stored is String && stored.trim().isNotEmpty) {
            return stored.trim().toUpperCase();
          }
        }
        return currencyCode.trim().toUpperCase();
      },
    );
  }

  @override
  Future<DepositAccountModel> getDepositAccount() async {
    return _apiClient.get<DepositAccountModel>(
      '/api/wallet/deposit-account',
      fromJson: (data) =>
          DepositAccountModel.fromJson(data as Map<String, dynamic>),
    );
  }

  @override
  Future<DepositAccountModel> provisionDepositAccount({
    String? sourceOfFunds,
  }) async {
    return _apiClient.post<DepositAccountModel>(
      '/api/wallet/deposit-account',
      data: sourceOfFunds == null ? null : {'sourceOfFunds': sourceOfFunds},
      fromJson: (data) =>
          DepositAccountModel.fromJson(data as Map<String, dynamic>),
    );
  }

  @override
  Future<TopupResponseModel> initiateTopup({
    required double amount,
    String currency = kDefaultWalletCurrency,
  }) async {
    return _apiClient.post<TopupResponseModel>(
      '/api/wallet/topup',
      data: {
        'amount': amount,
        'currency': currency,
      },
      fromJson: (data) =>
          TopupResponseModel.fromJson(data as Map<String, dynamic>),
    );
  }

  @override
  Future<TopupResponseModel> getTopupStatus(String fundingTransactionId) async {
    return _apiClient.get<TopupResponseModel>(
      '/api/wallet/topup/$fundingTransactionId',
      fromJson: (data) =>
          TopupResponseModel.fromJson(data as Map<String, dynamic>),
    );
  }

  @override
  Future<void> simulateWeWireDeposit(String fundingTransactionId) async {
    await _apiClient.post<void>(
      '/api/wallet/topup/$fundingTransactionId/simulate',
      fromJson: (_) {},
    );
  }

  @override
  Future<TopupResponseModel> confirmTopup(String fundingTransactionId) async {
    return _apiClient.post<TopupResponseModel>(
      '/api/wallet/topup/$fundingTransactionId/confirm',
      fromJson: (data) =>
          TopupResponseModel.fromJson(data as Map<String, dynamic>),
    );
  }
}

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ApiWalletRepository(apiClient);
});
