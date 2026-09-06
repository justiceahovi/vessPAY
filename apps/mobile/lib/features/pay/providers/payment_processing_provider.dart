import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/transaction_model.dart';
import '../repositories/payment_repository.dart';

/// State of an in-flight payment processing lifecycle
class PaymentProcessingState {
  final String transactionId;
  final String status; // 'PENDING' | 'PROCESSING' | 'COMPLETED' | 'FAILED' | 'TIMEOUT'
  final TransactionModel? transaction;
  final String stepLabel;
  final int currentStep; // 1, 2, or 3
  final double progress; // 0.0 to 1.0
  final String? errorMessage;
  final bool isPolling;
  final int pollCount;

  const PaymentProcessingState({
    required this.transactionId,
    this.status = 'PENDING',
    this.transaction,
    this.stepLabel = 'Submitting payout to payment rails...',
    this.currentStep = 1,
    this.progress = 0.33,
    this.errorMessage,
    this.isPolling = true,
    this.pollCount = 0,
  });

  PaymentProcessingState copyWith({
    String? transactionId,
    String? status,
    TransactionModel? transaction,
    String? stepLabel,
    int? currentStep,
    double? progress,
    String? errorMessage,
    bool? isPolling,
    int? pollCount,
  }) {
    return PaymentProcessingState(
      transactionId: transactionId ?? this.transactionId,
      status: status ?? this.status,
      transaction: transaction ?? this.transaction,
      stepLabel: stepLabel ?? this.stepLabel,
      currentStep: currentStep ?? this.currentStep,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      isPolling: isPolling ?? this.isPolling,
      pollCount: pollCount ?? this.pollCount,
    );
  }

  bool get isCompleted => status.toUpperCase() == 'COMPLETED';
  bool get isFailed => status.toUpperCase() == 'FAILED';
  bool get isPendingOrProcessing =>
      status.toUpperCase() == 'PENDING' || status.toUpperCase() == 'PROCESSING';
}

/// Notifier that actively polls GET /api/payments/:id for true status changes
class PaymentProcessingNotifier extends StateNotifier<PaymentProcessingState> {
  final PaymentRepository _repository;
  Timer? _pollingTimer;
  static const int maxPollAttempts = 30; // ~45 seconds
  static const Duration pollInterval = Duration(milliseconds: 1500);

  PaymentProcessingNotifier({
    required String transactionId,
    required PaymentRepository repository,
    TransactionModel? initialTransaction,
  })  : _repository = repository,
        super(PaymentProcessingState(
          transactionId: transactionId,
          transaction: initialTransaction,
          status: initialTransaction?.status ?? 'PENDING',
        )) {
    if (initialTransaction != null && initialTransaction.status == 'COMPLETED') {
      _handleCompleted(initialTransaction);
    } else if (initialTransaction != null && initialTransaction.status == 'FAILED') {
      _handleFailed(initialTransaction, initialTransaction.errorMessage);
    } else {
      _startPolling();
    }
  }

  void _startPolling() {
    // Perform initial fetch immediately
    _pollOnce();

    _pollingTimer = Timer.periodic(pollInterval, (_) {
      _pollOnce();
    });
  }

  Future<void> _pollOnce() async {
    if (!mounted || !state.isPolling) return;

    final nextCount = state.pollCount + 1;

    try {
      final tx = await _repository.getPaymentById(state.transactionId);
      if (!mounted) return;

      final upperStatus = tx.status.toUpperCase();

      if (upperStatus == 'COMPLETED') {
        _handleCompleted(tx);
      } else if (upperStatus == 'FAILED') {
        _handleFailed(tx, tx.errorMessage);
      } else if (upperStatus == 'PROCESSING') {
        state = state.copyWith(
          status: 'PROCESSING',
          transaction: tx,
          currentStep: 2,
          progress: 0.66,
          stepLabel: 'Partner network processing payout...',
          pollCount: nextCount,
        );
      } else {
        // PENDING
        state = state.copyWith(
          status: 'PENDING',
          transaction: tx,
          currentStep: 1,
          progress: 0.33,
          stepLabel: 'Submitting payout to payment rails...',
          pollCount: nextCount,
        );
      }
    } catch (e) {
      if (!mounted) return;
      // Network hiccup during polling: log and retry next tick
      state = state.copyWith(pollCount: nextCount);
    }

    if (nextCount >= maxPollAttempts && state.isPendingOrProcessing) {
      _pollingTimer?.cancel();
      state = state.copyWith(
        status: 'TIMEOUT',
        isPolling: false,
        stepLabel: 'Your payout is still being processed by the operator.',
      );
    }
  }

  void _handleCompleted(TransactionModel tx) {
    _pollingTimer?.cancel();
    state = state.copyWith(
      status: 'COMPLETED',
      transaction: tx,
      currentStep: 3,
      progress: 1.0,
      stepLabel: 'Payment completed successfully!',
      isPolling: false,
    );
  }

  void _handleFailed(TransactionModel? tx, String? error) {
    _pollingTimer?.cancel();
    state = state.copyWith(
      status: 'FAILED',
      transaction: tx,
      stepLabel: 'Payment could not be completed.',
      errorMessage: error ?? 'Mobile network operator rejected payout.',
      isPolling: false,
    );
  }

  void retry() {
    _pollingTimer?.cancel();
    state = PaymentProcessingState(
      transactionId: state.transactionId,
      status: 'PENDING',
      currentStep: 1,
      progress: 0.33,
      stepLabel: 'Retrying verification with payment rails...',
      pollCount: 0,
      isPolling: true,
    );
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}

/// Auto-dispose provider family taking a transactionId
final paymentProcessingProvider = StateNotifierProvider.autoDispose
    .family<PaymentProcessingNotifier, PaymentProcessingState, String>(
  (ref, transactionId) {
    final repository = ref.watch(paymentRepositoryProvider);
    return PaymentProcessingNotifier(
      transactionId: transactionId,
      repository: repository,
    );
  },
);
