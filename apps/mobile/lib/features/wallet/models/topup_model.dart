class TopupAccountDetails {
  final String? bankName;
  final String? accountName;
  final String? accountNumber;
  final String? routingNumber;
  final String? currency;

  const TopupAccountDetails({
    this.bankName,
    this.accountName,
    this.accountNumber,
    this.routingNumber,
    this.currency,
  });

  factory TopupAccountDetails.fromJson(Map<String, dynamic> json) {
    return TopupAccountDetails(
      bankName: json['bankName'] as String?,
      accountName: json['accountName'] as String?,
      accountNumber: json['accountNumber'] as String?,
      routingNumber: json['routingNumber'] as String?,
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

  const TopupResponseModel({
    required this.fundingTransactionId,
    required this.checkoutId,
    this.checkoutUrl,
    required this.status,
    required this.amount,
    required this.currency,
    this.accountDetails,
  });

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
