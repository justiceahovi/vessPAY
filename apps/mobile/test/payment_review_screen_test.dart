import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vesspay/features/pay/models/pay_flow_model.dart';
import 'package:vesspay/features/pay/models/payment_quote_model.dart';
import 'package:vesspay/features/pay/models/transaction_model.dart';
import 'package:vesspay/features/pay/providers/pay_anyone_providers.dart';
import 'package:vesspay/features/pay/models/payout_institution_model.dart';
import 'package:vesspay/features/pay/models/recipient_resolution_model.dart';
import 'package:vesspay/features/pay/repositories/payment_repository.dart';
import 'package:vesspay/features/pay/screens/payment_review_screen.dart';

import 'package:vesspay/features/pay/models/payment_response_model.dart';

class MockPaymentRepository implements PaymentRepository {
  @override
  Future<List<PayoutInstitutionModel>> getInstitutions({
    String currency = 'GHS',
    String? channel,
  }) async =>
      kFallbackGhanaBanks;

  @override
  Future<RecipientResolutionModel> resolveRecipientName({
    String? phone,
    String? accountNumber,
    String? network,
  }) async =>
      RecipientResolutionModel.unresolved(phone ?? accountNumber ?? '');

  final PaymentQuoteModel? stubbedQuote;
  final bool shouldFail;
  final CreatePaymentResponse? stubbedPaymentResponse;
  final TransactionModel? stubbedTransaction;

  MockPaymentRepository({
    this.stubbedQuote,
    this.shouldFail = false,
    this.stubbedPaymentResponse,
    this.stubbedTransaction,
  });

  bool createPaymentCalled = false;
  bool getQuoteCalled = false;

  @override
  Future<List<TransactionModel>> getTransactions() async => [];

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
    createPaymentCalled = true;
    if (shouldFail) {
      throw Exception('Payment creation failed');
    }
    return stubbedPaymentResponse ??
        const CreatePaymentResponse(
          transactionId: 'test-tx-uuid-12345',
          status: 'PENDING',
          wewireTransactionId: 'ww-tx-123',
        );
  }

  @override
  Future<TransactionModel> getPaymentById(String id) async {
    if (shouldFail) {
      throw Exception('Payment lookup failed');
    }
    return stubbedTransaction ??
        TransactionModel(
          id: id,
          type: 'payout',
          status: 'COMPLETED',
          sourceCurrency: 'USD',
          sourceAmount: 12.95,
          destinationCurrency: 'GHS',
          destinationAmount: 150.0,
          fee: 0.13,
          exchangeRate: 11.58,
          recipientName: 'Kwame Mensah',
          recipientPhone: '024 123 4567',
          network: 'MTN',
          country: 'GH',
          createdAt: DateTime.now(),
        );
  }

  @override
  Future<PaymentQuoteModel> getQuote({
    required String country,
    required String network,
    required String phone,
    required double destinationAmount,
    String destinationCurrency = 'GHS',
  }) async {
    getQuoteCalled = true;
    if (shouldFail) {
      throw Exception('Failed to connect to WeWire rates service');
    }
    return stubbedQuote ??
        PaymentQuoteModel(
          sourceCurrency: 'USD',
          sourceAmount: 12.95,
          destinationCurrency: 'GHS',
          destinationAmount: destinationAmount > 0 ? destinationAmount : 150.0,
          exchangeRate: 11.58,
          fee: 0.13,
          total: 13.08,
          country: country,
          network: network,
          phone: phone,
        );
  }
}

void main() {
  const samplePayData = PayFlowData(
    countryCode: 'GH',
    countryName: 'Ghana',
    countryFlag: '🇬🇭',
    paymentType: PaymentType.mobileMoney,
    network: 'MTN',
    recipientPhone: '024 123 4567',
    recipientName: 'Kwame Mensah',
    destinationAmount: 150.0,
    quoteSourceAmount: 12.95,
    quoteFee: 0.13,
    quoteTotal: 13.08,
    exchangeRate: 11.58,
  );

  const sampleQuote = PaymentQuoteModel(
    sourceCurrency: 'USD',
    sourceAmount: 12.95,
    destinationCurrency: 'GHS',
    destinationAmount: 150.0,
    exchangeRate: 11.58,
    fee: 0.13,
    total: 13.08,
    country: 'GH',
    network: 'MTN',
    phone: '024 123 4567',
  );

  group('T4.4: Payment Review Screen Tests', () {
    testWidgets(
        'Accurately reflects live quote and Section 11 "always show both currencies" principle',
        (WidgetTester tester) async {
      final mockRepo = MockPaymentRepository(stubbedQuote: sampleQuote);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            payFlowProvider.overrideWith(
              (ref) => PayFlowNotifier(11.58)..setAmount(150.0),
            ),
            paymentRepositoryProvider.overrideWithValue(
              mockRepo,
            ),
          ],
          child: const MaterialApp(
            home: PaymentReviewScreen(
              dataOverride: samplePayData,
              quoteOverride: sampleQuote,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header title
      expect(find.text('Review Payment'), findsOneWidget);

      // Section 11 Principle: Both currencies displayed prominently
      expect(find.byKey(const Key('review_you_pay_header')), findsOneWidget);
      expect(find.text('\$13.08'), findsWidgets);

      expect(find.byKey(const Key('review_recipient_gets_header')), findsOneWidget);
      expect(find.text('GH₵150.00'), findsWidgets);

      // Verify Recipient card
      expect(find.byKey(const Key('review_recipient_phone')), findsOneWidget);
      expect(find.text('024 123 4567'), findsOneWidget);

      expect(find.byKey(const Key('review_network')), findsOneWidget);
      expect(find.text('MTN'), findsOneWidget);

      expect(find.byKey(const Key('review_recipient_name')), findsOneWidget);
      expect(find.text('Kwame Mensah'), findsOneWidget);

      // Breakdown rows
      expect(find.byKey(const Key('review_source_amount')), findsOneWidget);
      expect(find.text('\$12.95'), findsOneWidget);

      expect(find.byKey(const Key('review_fee')), findsOneWidget);
      expect(find.text('\$0.13'), findsOneWidget);

      expect(find.byKey(const Key('review_total')), findsOneWidget);

      // Scroll until Confirm Payment button is visible, then tap
      await tester.ensureVisible(find.byKey(const Key('review_confirm_payment_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('review_confirm_payment_button')), findsOneWidget);
      expect(find.textContaining('Confirm Payment • Pay \$13.08'), findsOneWidget);

      await tester.tap(find.byKey(const Key('review_confirm_payment_button')));
      await tester.pump();
      expect(mockRepo.createPaymentCalled, isTrue);
    });

    testWidgets('Loads quote via repository provider when no quoteOverride is passed',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paymentRepositoryProvider.overrideWithValue(
              MockPaymentRepository(stubbedQuote: sampleQuote),
            ),
          ],
          child: const MaterialApp(
            home: PaymentReviewScreen(dataOverride: samplePayData),
          ),
        ),
      );

      // After settling, shows quote content from repository provider
      await tester.pumpAndSettle();
      expect(find.text('Review Payment'), findsOneWidget);
      expect(find.byKey(const Key('review_you_pay_header')), findsOneWidget);
      expect(find.byKey(const Key('review_recipient_gets_header')), findsOneWidget);
      expect(find.text('\$13.08'), findsWidgets);
      expect(find.text('GH₵150.00'), findsWidgets);
    });


    testWidgets(
        'Incomplete details are never quoted: shows the local estimate instead',
        (WidgetTester tester) async {
      final mockRepo = MockPaymentRepository(stubbedQuote: sampleQuote);

      // No recipient and no amount -- there is nothing real to price
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paymentRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(
            home: PaymentReviewScreen(dataOverride: PayFlowData()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(mockRepo.getQuoteCalled, isFalse);
      expect(find.byKey(const Key('review_estimate_notice')), findsOneWidget);
    });

    testWidgets('Displays error card with retry button on quote fetch failure',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paymentRepositoryProvider.overrideWithValue(
              MockPaymentRepository(shouldFail: true),
            ),
          ],
          child: const MaterialApp(
            home: PaymentReviewScreen(dataOverride: samplePayData),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Unable to fetch live quote'), findsOneWidget);
      expect(find.byKey(const Key('review_retry_button')), findsOneWidget);
    });

    testWidgets(
        'A corridor with no payout rail is priced in full but cannot be confirmed',
        (WidgetTester tester) async {
      // Nigeria: the recipient is confirmed and the quote is real, so the whole
      // flow is demonstrable. Only the step that moves money is held back.
      const nigeriaPayData = PayFlowData(
        countryCode: 'NG',
        countryName: 'Nigeria',
        countryFlag: '🇳🇬',
        destinationCurrency: 'NGN',
        paymentType: PaymentType.bankTransfer,
        network: '100004',
        accountNumber: '8012345678',
        recipientName: 'Stone 1206',
        destinationAmount: 50000.0,
        exchangeRate: 1146.906607,
      );
      const nigeriaQuote = PaymentQuoteModel(
        sourceCurrency: 'GBP',
        sourceAmount: 43.60,
        destinationCurrency: 'NGN',
        destinationAmount: 50000.0,
        exchangeRate: 1146.906607,
        fee: 0.44,
        wewireFee: 0.87,
        total: 44.91,
        country: 'NG',
        network: '100004',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paymentRepositoryProvider.overrideWithValue(
              MockPaymentRepository(stubbedQuote: nigeriaQuote),
            ),
          ],
          child: const MaterialApp(
            home: PaymentReviewScreen(
              dataOverride: nigeriaPayData,
              quoteOverride: nigeriaQuote,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The quote itself is fully rendered, in Naira.
      expect(find.text('₦50,000.00'), findsWidgets);
      expect(find.text('Stone 1206'), findsOneWidget);

      // The gate sits on confirmation, and explains itself.
      expect(
        find.byKey(const Key('review_payout_unavailable_notice')),
        findsOneWidget,
      );
      expect(
        find.text('Nigeria payouts are not live yet'),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing will be charged'), findsOneWidget);

      final confirmButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('review_confirm_payment_button')),
      );
      expect(confirmButton.onPressed, isNull);
      expect(find.text('Nigeria payouts coming soon'), findsOneWidget);
    });

    testWidgets('A live corridor keeps its confirm button enabled',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paymentRepositoryProvider.overrideWithValue(
              MockPaymentRepository(stubbedQuote: sampleQuote),
            ),
          ],
          child: const MaterialApp(
            home: PaymentReviewScreen(
              dataOverride: samplePayData,
              quoteOverride: sampleQuote,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('review_payout_unavailable_notice')),
        findsNothing,
      );
      final confirmButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('review_confirm_payment_button')),
      );
      expect(confirmButton.onPressed, isNotNull);
    });
  });
}
