/// Model representing response from POST /api/payments
class CreatePaymentResponse {
  final String transactionId;
  final String status;
  final String? wewireTransactionId;

  const CreatePaymentResponse({
    required this.transactionId,
    required this.status,
    this.wewireTransactionId,
  });

  factory CreatePaymentResponse.fromJson(Map<String, dynamic> json) {
    return CreatePaymentResponse(
      transactionId: (json['transactionId'] ?? json['id'] ?? '') as String,
      status: (json['status'] ?? 'PENDING') as String,
      wewireTransactionId: json['wewireTransactionId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transactionId': transactionId,
      'status': status,
      if (wewireTransactionId != null) 'wewireTransactionId': wewireTransactionId,
    };
  }
}
