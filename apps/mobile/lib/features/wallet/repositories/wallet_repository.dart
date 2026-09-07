import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_error.dart';
import '../../../core/providers.dart';
import '../../pay/models/transaction_model.dart';
import '../models/crypto_deposit_model.dart';
import '../models/deposit_account_model.dart';
import '../models/topup_model.dart';
import '../models/wallet_balance_model.dart';
import '../models/wallet_currency_model.dart';

abstract class WalletRepository {
  Future<List<WalletBalanceModel>> getBalances();

  /// Networks a crypto deposit address can be issued on, and what each accepts.
  Future<List<CryptoChainModel>> getCryptoChains();

  /// The user's deposit address for a chain, issuing one if they have none.
  /// Safe to poll: issuance is asynchronous and the endpoint is idempotent.
  Future<CryptoAddressModel> getCryptoAddress(String chain);

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

  /// Abandons a deposit the user started but never funded, so they can start a
  /// different one. Cannot stop money already in flight.
  Future<void> cancelTopup(String fundingTransactionId);

  /// The deposit the user still has in flight for [currency], or null when
  /// there is none. A top-up outlives the screen that started it, so this is
  /// what lets an interrupted one be picked back up.
  Future<TopupResponseModel?> getPendingTopup({
    String currency = kDefaultWalletCurrency,
  });

  /// Asks WeWire to drop a sandbox deposit onto the user's real virtual
  /// account. The wallet is credited by the resulting pay-in webhook, not by
  /// this call, so the caller has to wait for the balance rather than assume it.
  Future<void> simulateWeWireDeposit(String fundingTransactionId);

  /// The user's deposits as unified transaction records, so the activity feed
  /// can show money coming in next to money going out.
  Future<List<TransactionModel>> getDeposits();

  /// A single deposit by id, for opening one from a feed row that only carries
  /// its identifier.
  Future<TransactionModel> getDepositById(String id);
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
  Future<List<CryptoChainModel>> getCryptoChains() async {
    return _apiClient.get<List<CryptoChainModel>>(
      '/api/wallet/crypto-chains',
      fromJson: (data) => (data as List)
          .map((e) => CryptoChainModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<CryptoAddressModel> getCryptoAddress(String chain) async {
    try {
      return await _apiClient.get<CryptoAddressModel>(
        '/api/wallet/crypto-address',
        queryParameters: {'chain': chain},
        fromJson: (data) =>
            CryptoAddressModel.fromJson(data as Map<String, dynamic>),
      );
    } on ApiException catch (e) {
      // "Finish verifying first" is an answer, not a failure. Letting it throw
      // would put a raw exception string in front of the user where a next
      // step belongs.
      if (e.code == 'SUBCUSTOMER_REQUIRED') {
        return CryptoAddressModel.verificationRequired(chain);
      }
      if (e.code == 'ADDRESS_UNAVAILABLE' || e.code == 'INVALID_CHAIN') {
        return CryptoAddressModel.unavailable(chain, e.message);
      }
      rethrow;
    }
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
  Future<TopupResponseModel?> getPendingTopup({
    String currency = kDefaultWalletCurrency,
  }) async {
    return _apiClient.get<TopupResponseModel?>(
      '/api/wallet/topup/pending',
      queryParameters: {'currency': currency},
      fromJson: (data) {
        final pending = data is Map<String, dynamic> ? data['pending'] : null;
        return pending is Map<String, dynamic>
            ? TopupResponseModel.fromJson(pending)
            : null;
      },
    );
  }

  @override
  Future<void> cancelTopup(String fundingTransactionId) async {
    await _apiClient.post<void>(
      '/api/wallet/topup/$fundingTransactionId/cancel',
      fromJson: (_) {},
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
  Future<List<TransactionModel>> getDeposits() async {
    return _apiClient.get<List<TransactionModel>>(
      '/api/wallet/deposits',
      fromJson: (data) {
        if (data is List) {
          return data
              .map((item) =>
                  TransactionModel.fromJson(item as Map<String, dynamic>))
              .toList();
        }
        return <TransactionModel>[];
      },
    );
  }

  @override
  Future<TransactionModel> getDepositById(String id) async {
    return _apiClient.get<TransactionModel>(
      '/api/wallet/deposits/$id',
      fromJson: (data) =>
          TransactionModel.fromJson(data as Map<String, dynamic>),
    );
  }
}

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ApiWalletRepository(apiClient);
});
