import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../pay/providers/recent_activity_provider.dart';
import '../models/crypto_deposit_model.dart';
import '../models/deposit_account_model.dart';
import '../models/topup_model.dart';
import '../models/wallet_balance_model.dart';
import '../repositories/wallet_repository.dart';
import '../../travel/providers/travel_providers.dart';
import 'currency_providers.dart';
import '../../../core/api/api_error.dart';

/// Fallback used only until the live rate resolves. Per corridor, because a
/// single number cannot stand in for both a ~15 GHS and a ~1150 NGN rate --
/// showing 15.50 to a Nigeria user would be off by two orders of magnitude.
const Map<String, double> _kFallbackRates = {
  'GHS': 15.50,
  'NGN': 1146.90,
};

double _fallbackRateFor(String currency) =>
    _kFallbackRates[currency.toUpperCase()] ?? 15.50;

/// Fetches the live exchange rate from the user's wallet currency into the
/// currency of the destination they are travelling to, via backend
/// `GET /api/rates?from=<wallet currency>&to=<destination currency>`.
final liveExchangeRateProvider = FutureProvider<double>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final fromCurrency = ref.watch(activeWalletCurrencyCodeProvider);
  final toCurrency = ref.watch(activeDestinationCurrencyProvider) ?? 'GHS';
  try {
    final res = await apiClient.get<Map<String, dynamic>>(
      '/api/rates',
      queryParameters: {'from': fromCurrency, 'to': toCurrency},
    );
    final rateVal = res['rate'];
    if (rateVal is num) {
      return rateVal.toDouble();
    }
    return _fallbackRateFor(toCurrency);
  } catch (e) {
    return _fallbackRateFor(toCurrency);
  }
});

/// Current exchange rate from whichever currency the user holds into the
/// active destination's currency. Sourced live, with a per-corridor fallback.
final walletToDestinationRateProvider = Provider<double>((ref) {
  final liveRateAsync = ref.watch(liveExchangeRateProvider);
  final toCurrency = ref.watch(activeDestinationCurrencyProvider) ?? 'GHS';
  return liveRateAsync.valueOrNull ?? _fallbackRateFor(toCurrency);
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

  /// Abandons the deposit currently being waited on and returns to amount entry.
  ///
  /// [reset] alone would not do: the deposit stays PENDING on the server, and
  /// [restorePendingTopup] would drag the user straight back to the waiting
  /// screen next time they open Add Money. Cancelling server-side is what
  /// actually lets them start a deposit for a different amount.
  Future<bool> cancelPendingTopup() async {
    final id = state.response?.fundingTransactionId;
    if (id == null) {
      reset();
      return true;
    }

    try {
      await _repository.cancelTopup(id);
      _stopPolling();
      state = const TopupState();
      return true;
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Could not cancel this deposit. Please try again.',
      );
      return false;
    }
  }

  /// Picks a deposit back up where the user left it.
  ///
  /// A top-up lives on the backend as a PENDING funding transaction, but this
  /// notifier is autoDispose: leaving Add Money throws its state away, and the
  /// virtual account the user was told to transfer to goes with it. Asking for
  /// that record rebuilds the waiting step around it, so the details are there
  /// again instead of the user opening a second deposit.
  ///
  /// Only ever acts from the amount-entry step: a top-up already under way in
  /// this session is the fresher truth and is left alone.
  Future<void> restorePendingTopup() async {
    if (state.step != TopupStep.enterAmount) return;

    try {
      final pending = await _repository.getPendingTopup(
        currency: _ref.read(activeWalletCurrencyCodeProvider),
      );
      // The user can start their own top-up while this is in flight, and
      // their intent outranks the restored one.
      if (pending == null || !mounted || state.step != TopupStep.enterAmount) {
        return;
      }

      state = state.copyWith(
        step: TopupStep.waitingConfirmation,
        amount: pending.amount,
        response: pending,
        isPolling: true,
      );
      _startPolling(pending.fundingTransactionId);
    } catch (_) {
      // Resuming is a convenience. If it fails the user simply lands on the
      // amount entry step, which is where they would have been anyway.
    }
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

      // The deposit now exists as a pending record, so the activity feed has
      // something new to show.
      _ref.invalidate(userTransactionsProvider);

      // Start automatic polling loop for confirmation
      _startPolling(response.fundingTransactionId);

      return response;
    } catch (e) {
      state = state.copyWith(
        step: TopupStep.failed,
        errorMessage: friendlyErrorMessage(e),
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
          // And the activity feed, so the deposit shows as settled.
          _ref.invalidate(userTransactionsProvider);
        } else if (currentStatus.isFailed) {
          _stopPolling();
          state = state.copyWith(
            step: TopupStep.failed,
            errorMessage: 'Funding transaction was declined or failed.',
            isPolling: false,
          );
          _ref.invalidate(userTransactionsProvider);
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

/// Networks a crypto deposit address can be issued on. Reference data, so it
/// is fetched once and shared.
final cryptoChainsProvider =
    FutureProvider<List<CryptoChainModel>>((ref) async {
  return ref.watch(walletRepositoryProvider).getCryptoChains();
});

/// The user's deposit address for a chain.
///
/// Issuance is asynchronous, so this resolves to PROVISIONING first and the
/// screen re-reads it until an address appears. The endpoint is idempotent, so
/// re-reading never issues a second address.
final cryptoAddressProvider = FutureProvider.autoDispose
    .family<CryptoAddressModel, String>((ref, chain) async {
  return ref.watch(walletRepositoryProvider).getCryptoAddress(chain);
});
