class TopupAccountDetails {
  final String? bankName;
  final String? accountName;
  final String? accountNumber;
  final String? routingNumber;
  final String? sortCode;
  final String? iban;
  final String? bic;
  final List<String> paymentRails;
  final String? currency;

  const TopupAccountDetails({
    this.bankName,
    this.accountName,
    this.accountNumber,
    this.routingNumber,
    this.sortCode,
    this.iban,
    this.bic,
    this.paymentRails = const [],
    this.currency,
  });

  /// US accounts are addressed by account + routing number, EUR/GBP ones by
  /// IBAN and BIC, so a card should render whichever pair is present.
  bool get hasLocalNumbers =>
      (accountNumber?.isNotEmpty ?? false) ||
      (routingNumber?.isNotEmpty ?? false) ||
      (sortCode?.isNotEmpty ?? false);

  bool get hasIban => (iban?.isNotEmpty ?? false) || (bic?.isNotEmpty ?? false);

  factory TopupAccountDetails.fromJson(Map<String, dynamic> json) {
    final rails = json['paymentRails'];
    return TopupAccountDetails(
      bankName: json['bankName'] as String?,
      accountName: json['accountName'] as String?,
      accountNumber: json['accountNumber'] as String?,
      routingNumber: json['routingNumber'] as String?,
      sortCode: json['sortCode'] as String?,
      iban: json['iban'] as String?,
      bic: json['bic'] as String?,
      paymentRails:
          rails is List ? rails.map((r) => r.toString()).toList() : const [],
      currency: json['currency'] as String?,
    );
  }
}

class TopupResponseModel {
  final String fundingTransactionId;
  final String checkoutId;
  final String? checkoutUrl;
  final String status;
  final double amount;
  final String currency;
  final TopupAccountDetails? accountDetails;

  /// 'wewire' when the deposit address is a real issued virtual account,
  /// 'local' when the backend fell back to its own demo rails.
  final String accountSource;

  const TopupResponseModel({
    required this.fundingTransactionId,
    required this.checkoutId,
    this.checkoutUrl,
    required this.status,
    required this.amount,
    required this.currency,
    this.accountDetails,
    this.accountSource = 'local',
  });

  /// Whether money can actually be moved through WeWire for this top-up.
  bool get isWeWireBacked => accountSource == 'wewire';

  factory TopupResponseModel.fromJson(Map<String, dynamic> json) {
    return TopupResponseModel(
      fundingTransactionId: (json['fundingTransactionId'] as String?) ??
          (json['id'] as String?) ??
          '',
      checkoutId: (json['checkoutId'] as String?) ?? '',
      checkoutUrl: json['checkoutUrl'] as String?,
      status: (json['status'] as String?) ?? 'PENDING',
      amount: (json['amount'] is num)
          ? (json['amount'] as num).toDouble()
          : double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      currency: (json['currency'] as String?) ?? 'USD',
      accountSource: (json['accountSource'] as String?) ?? 'local',
      accountDetails: json['accountDetails'] != null
          ? TopupAccountDetails.fromJson(
              json['accountDetails'] as Map<String, dynamic>)
          : null,
    );
  }

  bool get isCompleted => status.toUpperCase() == 'COMPLETED';
  bool get isPending => status.toUpperCase() == 'PENDING';
  bool get isFailed => status.toUpperCase() == 'FAILED';
}
