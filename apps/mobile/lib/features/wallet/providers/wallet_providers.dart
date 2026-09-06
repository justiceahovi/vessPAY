import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../models/deposit_account_model.dart';
import '../models/topup_model.dart';
import '../models/wallet_balance_model.dart';
import '../repositories/wallet_repository.dart';
import 'currency_providers.dart';

/// Fetches the live exchange rate from the user's wallet currency into GHS
/// via backend `GET /api/rates?from=<wallet currency>&to=GHS`
final liveExchangeRateProvider = FutureProvider<double>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final fromCurrency = ref.watch(activeWalletCurrencyCodeProvider);
  try {
    final res = await apiClient.get<Map<String, dynamic>>(
      '/api/rates',
      queryParameters: {'from': fromCurrency, 'to': 'GHS'},
    );
    final rateVal = res['rate'];
    if (rateVal is num) {
      return rateVal.toDouble();
    }
    return 15.50;
  } catch (e) {
    return 15.50;
  }
});

/// Provides current exchange rate for GHS equivalent conversion, from whichever
/// currency the user holds their wallet in.
/// Sourced live from backend / WeWire rates (resolves live, with fallback).
final walletToGhsRateProvider = Provider<double>((ref) {
  final liveRateAsync = ref.watch(liveExchangeRateProvider);
  return liveRateAsync.valueOrNull ?? 15.50;
});

/// Provides the live list of wallet balances from GET /api/wallet/balances
final walletBalancesProvider = FutureProvider<List<WalletBalanceModel>>((ref) async {
  final repository = ref.watch(walletRepositoryProvider);
  return repository.getBalances();
});

/// Computes the balance model for the currency the user chose to hold
final primaryWalletBalanceProvider =
    Provider<AsyncValue<WalletBalanceModel?>>((ref) {
  final balancesAsync = ref.watch(walletBalancesProvider);
  final activeCurrency = ref.watch(activeWalletCurrencyCodeProvider);
  return balancesAsync.whenData((balances) {
    if (balances.isEmpty) return null;
    // Never fall back to another currency's wallet: the UI labels this amount
    // with the active currency, so a foreign balance would be mislabelled.
    // A user who has just switched simply holds nothing in the new currency yet.
    return balances.firstWhere(
      (b) => b.currency.toUpperCase() == activeCurrency,
      orElse: () => WalletBalanceModel(currency: activeCurrency, balance: 0.0),
    );
  });
});

/// Deposit-account setup state. Read-only, so it is safe to poll while WeWire
/// provisions the account.
final depositAccountProvider =
    FutureProvider<DepositAccountModel>((ref) async {
  // Re-read whenever the held currency changes: accounts are per-currency.
  ref.watch(activeWalletCurrencyCodeProvider);
  return ref.watch(walletRepositoryProvider).getDepositAccount();
});

/// Balances still held in currencies other than the active one.
///
/// Switching wallet currency never converts anything: the old wallet keeps its
/// money. These are surfaced so that balance stays visible instead of silently
/// dropping out of the UI.
final secondaryWalletBalancesProvider =
    Provider<List<WalletBalanceModel>>((ref) {
  final balances = ref.watch(walletBalancesProvider).valueOrNull ??
      const <WalletBalanceModel>[];
  final active = ref.watch(activeWalletCurrencyCodeProvider);
  return balances
      .where((b) => b.currency.toUpperCase() != active && b.balance > 0)
      .toList();
});

enum TopupStep {
  enterAmount,
  initiating,
  waitingConfirmation,
  completed,
  failed,
}

class TopupState {
  final TopupStep step;
  final double amount;
  final TopupResponseModel? response;
  final String? errorMessage;
  final bool isPolling;

  const TopupState({
    this.step = TopupStep.enterAmount,
    this.amount = 0.0,
    this.response,
    this.errorMessage,
    this.isPolling = false,
  });

  TopupState copyWith({
    TopupStep? step,
    double? amount,
    TopupResponseModel? response,
    String? errorMessage,
    bool? isPolling,
  }) {
    return TopupState(
      step: step ?? this.step,
      amount: amount ?? this.amount,
      response: response ?? this.response,
      errorMessage: errorMessage,
      isPolling: isPolling ?? this.isPolling,
    );
  }
}

class TopupNotifier extends StateNotifier<TopupState> {
  final WalletRepository _repository;
  final Ref _ref;
  Timer? _pollTimer;

  TopupNotifier(this._repository, this._ref) : super(const TopupState());

  void setAmount(double amount) {
    state = state.copyWith(amount: amount, errorMessage: null);
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void reset() {
    _stopPolling();
    state = const TopupState();
  }

  Future<TopupResponseModel?> initiateTopup(double amount) async {
    _stopPolling();
    state = state.copyWith(
      step: TopupStep.initiating,
      amount: amount,
      errorMessage: null,
    );

    try {
      final response = await _repository.initiateTopup(
        amount: amount,
        currency: _ref.read(activeWalletCurrencyCodeProvider),
      );
      state = state.copyWith(
        step: TopupStep.waitingConfirmation,
        response: response,
        isPolling: true,
      );

      // Start automatic polling loop for confirmation
      _startPolling(response.fundingTransactionId);

      return response;
    } catch (e) {
      state = state.copyWith(
        step: TopupStep.failed,
        errorMessage: e.toString(),
        isPolling: false,
      );
      return null;
    }
  }

  void _startPolling(String fundingTransactionId) {
    _stopPolling();
    const pollInterval = Duration(seconds: 2);
    int attempts = 0;
    const maxAttempts = 60;

    _pollTimer = Timer.periodic(pollInterval, (timer) async {
      attempts++;
      if (attempts >= maxAttempts) {
        _stopPolling();
        state = state.copyWith(isPolling: false);
        return;
      }

      try {
        final currentStatus =
            await _repository.getTopupStatus(fundingTransactionId);
        if (currentStatus.isCompleted) {
          _stopPolling();
          state = state.copyWith(
            step: TopupStep.completed,
            response: currentStatus,
            isPolling: false,
          );
          // Invalidate wallet balances so the entire app reflects the new balance immediately!
          _ref.invalidate(walletBalancesProvider);
        } else if (currentStatus.isFailed) {
          _stopPolling();
          state = state.copyWith(
            step: TopupStep.failed,
            errorMessage: 'Funding transaction was declined or failed.',
            isPolling: false,
          );
        }
      } catch (_) {
        // Continue polling on transient errors
      }
    });
  }

  /// Real deposit path: WeWire drops the money on the user's virtual account
  /// and the pay-in webhook credits the wallet. Nothing is credited here, so
  /// this keeps polling the funding transaction until the webhook lands.
  Future<bool> simulateWeWireDeposit(String fundingTransactionId) async {
    try {
      await _repository.simulateWeWireDeposit(fundingTransactionId);
      state = state.copyWith(
        step: TopupStep.waitingConfirmation,
        isPolling: true,
        errorMessage: null,
      );
      _startPolling(fundingTransactionId);
      return true;
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Could not request the deposit: $e',
      );
      return false;
    }
  }



  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}

final topupControllerProvider = StateNotifierProvider.autoDispose<TopupNotifier, TopupState>((ref) {
  final repository = ref.watch(walletRepositoryProvider);
  return TopupNotifier(repository, ref);
});
