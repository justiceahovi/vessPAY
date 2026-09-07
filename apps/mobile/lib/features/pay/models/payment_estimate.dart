/// Single source of truth for the client-side payment estimate.
///
/// The server recalculates every quote before a payment is created, so these
/// numbers are only ever an estimate shown while the user types. Keeping the
/// formula in one place is what stops the form, the review screen and the
/// server from disagreeing about the fee.
class PaymentEstimate {
  /// Fee model mirrored from the backend quote calculation.
  static const double feeRate = 0.01;
  static const double minimumFee = 0.01;

  /// WeWire's flat processor fee in GHS, mirrored from the backend's
  /// WEWIRE_PROCESSOR_FEE_GHS default.
  static const double wewireProcessorFeeGhs = 5.0;

  /// The same flat fee per corridor, denominated in the payout currency and
  /// mirroring lib/corridors.ts. Ghana's 5 is measured; Nigeria's 1000 was read
  /// off a live disbursement record. The server's quote is authoritative -- this
  /// only has to be close enough that the figure does not jump on arrival.
  static const Map<String, double> wewireProcessorFees = {
    'GHS': 5.0,
    'NGN': 1000.0,
  };

  static double processorFeeFor(String currency) =>
      wewireProcessorFees[currency.toUpperCase()] ?? 0.0;

  final double destinationAmount;
  final double sourceAmount;
  final double fee;
  final double wewireFee;
  final double total;
  final double exchangeRate;

  const PaymentEstimate({
    required this.destinationAmount,
    required this.sourceAmount,
    required this.fee,
    this.wewireFee = 0.0,
    required this.total,
    required this.exchangeRate,
  });

  static const PaymentEstimate empty = PaymentEstimate(
    destinationAmount: 0.0,
    sourceAmount: 0.0,
    fee: 0.0,
    wewireFee: 0.0,
    total: 0.0,
    exchangeRate: 0.0,
  );

  bool get isEmpty => destinationAmount <= 0;

  /// Computes the local estimate for [destinationAmount] at [exchangeRate],
  /// using the same rounding order as the server.
  factory PaymentEstimate.local({
    required double destinationAmount,
    required double exchangeRate,
    String destinationCurrency = 'GHS',
  }) {
    final rate = exchangeRate > 0 ? exchangeRate : 11.58;
    if (destinationAmount <= 0) {
      return PaymentEstimate(
        destinationAmount: 0.0,
        sourceAmount: 0.0,
        fee: 0.0,
        wewireFee: 0.0,
        total: 0.0,
        exchangeRate: rate,
      );
    }

    final sourceAmount =
        double.parse((destinationAmount / rate).toStringAsFixed(2));
    final rawFee = sourceAmount * feeRate;
    final fee = double.parse(
      (rawFee < minimumFee ? minimumFee : rawFee).toStringAsFixed(2),
    );
    final wewireFee = double.parse(
      (processorFeeFor(destinationCurrency) / rate).toStringAsFixed(2),
    );
    final total =
        double.parse((sourceAmount + fee + wewireFee).toStringAsFixed(2));

    return PaymentEstimate(
      destinationAmount: destinationAmount,
      sourceAmount: sourceAmount,
      fee: fee,
      wewireFee: wewireFee,
      total: total,
      exchangeRate: rate,
    );
  }
}
