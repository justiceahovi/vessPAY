import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/providers.dart';
import '../models/payment_quote_model.dart';
import '../models/payment_response_model.dart';
import '../models/payout_institution_model.dart';
import '../models/recipient_resolution_model.dart';
import '../models/transaction_model.dart';

abstract class PaymentRepository {
  Future<PaymentQuoteModel> getQuote({
    required String country,
    required String network,
    required String phone,
    required double destinationAmount,
    String destinationCurrency = 'GHS',
  });

  Future<CreatePaymentResponse> createPayment({
    required String country,
    required String network,
    required String phone,
    required double destinationAmount,
    String destinationCurrency = 'GHS',
    required String idempotencyKey,
    String? recipientName,
    /// 'MOBILE_MONEY' (default) or 'BANK'.
    String? channel,
    /// Bank account number, required when channel is 'BANK'.
    String? accountNumber,
  });

  /// Resolves the recipient name known for a mobile money number, so the
  /// Pay Anyone flow can auto-fill it while the user types.
  Future<RecipientResolutionModel> resolveRecipientName({
    String? phone,
    String? accountNumber,
    String? network,
  });

  /// Payout institutions (banks and mobile money operators) for a currency,
  /// sourced from WeWire via GET /api/banks.
  Future<List<PayoutInstitutionModel>> getInstitutions({
    String currency = 'GHS',
    String? channel,
  });

  Future<TransactionModel> getPaymentById(String id);

  Future<List<TransactionModel>> getTransactions();
}

class ApiPaymentRepository implements PaymentRepository {
  final ApiClient _apiClient;

  ApiPaymentRepository(this._apiClient);

  @override
  Future<PaymentQuoteModel> getQuote({
    required String country,
    required String network,
    required String phone,
    required double destinationAmount,
    String destinationCurrency = 'GHS',
  }) async {
    return _apiClient.post<PaymentQuoteModel>(
      '/api/payments/quote',
      data: {
        'country': country,
        'network': network,
        'phone': phone,
        'destinationAmount': destinationAmount,
        'destinationCurrency': destinationCurrency,
      },
      fromJson: (data) =>
          PaymentQuoteModel.fromJson(data as Map<String, dynamic>),
    );
  }

  @override
  Future<CreatePaymentResponse> createPayment({
    required String country,
    required String network,
    required String phone,
    required double destinationAmount,
    String destinationCurrency = 'GHS',
    required String idempotencyKey,
    String? recipientName,
    String? channel,
    String? accountNumber,
  }) async {
    final isBank = channel == 'BANK';

    return _apiClient.post<CreatePaymentResponse>(
      '/api/payments',
      data: {
        'country': country,
        'network': network,
        // A bank payout is addressed by account number, not a phone number
        if (!isBank) 'phone': phone,
        if (isBank) 'accountNumber': accountNumber,
        if (channel != null && channel.isNotEmpty) 'channel': channel,
        'destinationAmount': destinationAmount,
        'destinationCurrency': destinationCurrency,
        'idempotencyKey': idempotencyKey,
        if (recipientName != null && recipientName.isNotEmpty)
          'recipientName': recipientName,
      },
      fromJson: (data) =>
          CreatePaymentResponse.fromJson(data as Map<String, dynamic>),
    );
  }

  @override
  Future<RecipientResolutionModel> resolveRecipientName({
    String? phone,
    String? accountNumber,
    String? network,
  }) async {
    return _apiClient.get<RecipientResolutionModel>(
      '/api/beneficiaries/resolve',
      queryParameters: {
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (accountNumber != null && accountNumber.isNotEmpty)
          'accountNumber': accountNumber,
        if (network != null && network.isNotEmpty) 'network': network,
      },
      fromJson: (data) =>
          RecipientResolutionModel.fromJson(data as Map<String, dynamic>),
    );
  }

  @override
  Future<List<PayoutInstitutionModel>> getInstitutions({
    String currency = 'GHS',
    String? channel,
  }) async {
    return _apiClient.get<List<PayoutInstitutionModel>>(
      '/api/banks',
      queryParameters: {
        'currency': currency,
        if (channel != null && channel.isNotEmpty) 'channel': channel,
      },
      fromJson: (data) {
        if (data is List) {
          return data
              .map((item) =>
                  PayoutInstitutionModel.fromJson(item as Map<String, dynamic>))
              .toList();
        }
        return <PayoutInstitutionModel>[];
      },
    );
  }

  @override
  Future<TransactionModel> getPaymentById(String id) async {
    return _apiClient.get<TransactionModel>(
      '/api/payments/$id',
      fromJson: (data) =>
          TransactionModel.fromJson(data as Map<String, dynamic>),
    );
  }

  @override
  Future<List<TransactionModel>> getTransactions() async {
    return _apiClient.get<List<TransactionModel>>(
      '/api/payments',
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
}

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ApiPaymentRepository(apiClient);
});
