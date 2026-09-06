enum PaymentType {
  mobileMoney,
  bankTransfer;

  String get displayName {
    switch (this) {
      case PaymentType.mobileMoney:
        return 'Mobile Money';
      case PaymentType.bankTransfer:
        return 'Bank Transfer';
    }
  }

  String get description {
    switch (this) {
      case PaymentType.mobileMoney:
        return 'Instant payout to MTN, Telecel, or AirtelTigo';
      case PaymentType.bankTransfer:
        return 'Direct transfer to local Ghanaian bank account';
    }
  }
}

class PayFlowData {
  final String countryCode;
  final String countryName;
  final String countryFlag;
  final String destinationCurrency;
  final String sourceCurrency;
  final PaymentType paymentType;
  final String network;
  final String recipientPhone;
  final String recipientName;
  final String accountNumber;
  final double destinationAmount;
  final double? quoteSourceAmount;
  final double? quoteFee;
  final double? quoteTotal;
  final double exchangeRate;

  const PayFlowData({
    this.countryCode = 'GH',
    this.countryName = 'Ghana',
    this.countryFlag = '🇬🇭',
    this.destinationCurrency = 'GHS',
    this.sourceCurrency = 'USD',
    this.paymentType = PaymentType.mobileMoney,
    this.network = 'MTN',
    this.recipientPhone = '',
    this.recipientName = '',
    this.accountNumber = '',
    this.destinationAmount = 0.0,
    this.quoteSourceAmount,
    this.quoteFee,
    this.quoteTotal,
    this.exchangeRate = 11.58,
  });

  PayFlowData copyWith({
    String? countryCode,
    String? countryName,
    String? countryFlag,
    String? destinationCurrency,
    String? sourceCurrency,
    PaymentType? paymentType,
    String? network,
    String? recipientPhone,
    String? recipientName,
    String? accountNumber,
    double? destinationAmount,
    double? quoteSourceAmount,
    double? quoteFee,
    double? quoteTotal,
    double? exchangeRate,
  }) {
    return PayFlowData(
      countryCode: countryCode ?? this.countryCode,
      countryName: countryName ?? this.countryName,
      countryFlag: countryFlag ?? this.countryFlag,
      destinationCurrency: destinationCurrency ?? this.destinationCurrency,
      sourceCurrency: sourceCurrency ?? this.sourceCurrency,
      paymentType: paymentType ?? this.paymentType,
      network: network ?? this.network,
      recipientPhone: recipientPhone ?? this.recipientPhone,
      recipientName: recipientName ?? this.recipientName,
      accountNumber: accountNumber ?? this.accountNumber,
      destinationAmount: destinationAmount ?? this.destinationAmount,
      quoteSourceAmount: quoteSourceAmount ?? this.quoteSourceAmount,
      quoteFee: quoteFee ?? this.quoteFee,
      quoteTotal: quoteTotal ?? this.quoteTotal,
      exchangeRate: exchangeRate ?? this.exchangeRate,
    );
  }
}
