class PaymentQuoteModel {
  final String sourceCurrency;
  final double sourceAmount;
  final String destinationCurrency;
  final double destinationAmount;
  final double exchangeRate;
  final double fee;

  /// WeWire's flat processor fee, estimated upfront and converted into
  /// [sourceCurrency]. Reconciled against the actual charge once the payout
  /// is sent (see [TransactionModel.wewireFee]).
  final double wewireFee;
  final double total;
  final String? country;
  final String? network;
  final String? phone;

  const PaymentQuoteModel({
    required this.sourceCurrency,
    required this.sourceAmount,
    required this.destinationCurrency,
    required this.destinationAmount,
    required this.exchangeRate,
    required this.fee,
    this.wewireFee = 0.0,
    required this.total,
    this.country,
    this.network,
    this.phone,
  });

  factory PaymentQuoteModel.fromJson(Map<String, dynamic> json) {
    return PaymentQuoteModel(
      sourceCurrency: json['sourceCurrency'] as String? ?? 'USD',
      sourceAmount: (json['sourceAmount'] as num).toDouble(),
      destinationCurrency: json['destinationCurrency'] as String? ?? 'GHS',
      destinationAmount: (json['destinationAmount'] as num).toDouble(),
      exchangeRate: (json['exchangeRate'] as num).toDouble(),
      fee: (json['fee'] as num).toDouble(),
      wewireFee: (json['wewireFee'] as num?)?.toDouble() ?? 0.0,
      total: (json['total'] as num).toDouble(),
      country: json['country'] as String?,
      network: json['network'] as String?,
      phone: json['phone'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sourceCurrency': sourceCurrency,
      'sourceAmount': sourceAmount,
      'destinationCurrency': destinationCurrency,
      'destinationAmount': destinationAmount,
      'exchangeRate': exchangeRate,
      'fee': fee,
      'wewireFee': wewireFee,
      'total': total,
      if (country != null) 'country': country,
      if (network != null) 'network': network,
      if (phone != null) 'phone': phone,
    };
  }
}
