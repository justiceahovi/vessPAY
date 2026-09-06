import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vesspay/core/routing/app_routes.dart';
import 'package:vesspay/features/pay/models/payment_quote_model.dart';
import 'package:vesspay/features/pay/models/payment_response_model.dart';
import 'package:vesspay/features/pay/models/transaction_model.dart';
import 'package:vesspay/features/pay/models/pay_flow_model.dart';
import 'package:vesspay/features/pay/providers/pay_anyone_providers.dart';
import 'package:vesspay/features/pay/models/payout_institution_model.dart';
import 'package:vesspay/features/pay/models/recipient_resolution_model.dart';
import 'package:vesspay/features/pay/repositories/payment_repository.dart';
import 'package:vesspay/features/pay/screens/payment_processing_screen.dart';
import 'package:vesspay/features/pay/screens/payment_success_screen.dart';
import 'package:vesspay/features/pay/screens/payment_failure_screen.dart';
import 'package:vesspay/features/pay/screens/payment_review_screen.dart';

class ControllablePaymentRepository implements PaymentRepository {
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

  final StreamController<TransactionModel> _txStream =
      StreamController<TransactionModel>.broadcast();
  TransactionModel _currentTx;

  ControllablePaymentRepository(this._currentTx);

  void updateTransaction(TransactionModel nextTx) {
    _currentTx = nextTx;
    _txStream.add(nextTx);
  }

  @override
  Future<TransactionModel> getPaymentById(String id) async {
    return _currentTx;
  }

  @override
  Completer<CreatePaymentResponse>? createPaymentCompleter;

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
    if (createPaymentCompleter != null) {
      return await createPaymentCompleter!.future;
    }
    return CreatePaymentResponse(
      transactionId: _currentTx.id,
      status: _currentTx.status,
      wewireTransactionId: 'ww-test-12345',
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
    return PaymentQuoteModel(
      sourceCurrency: 'USD',
      sourceAmount: 12.95,
      destinationCurrency: 'GHS',
      destinationAmount: destinationAmount,
      exchangeRate: 11.58,
      fee: 0.13,
      total: 13.08,
      country: country,
      network: network,
      phone: phone,
    );
  }

  @override
  Future<List<TransactionModel>> getTransactions() async => [_currentTx];

  void dispose() {
    _txStream.close();
  }
}

void main() {
  final samplePendingTx = TransactionModel(
    id: 'tx-test-001',
    type: 'payout',
    status: 'PENDING',
    sourceCurrency: 'USD',
    sourceAmount: 12.95,
    destinationCurrency: 'GHS',
    destinationAmount: 150.0,
    fee: 0.13,
    exchangeRate: 11.58,
    recipientName: 'Kwame Mensah',
    recipientPhone: '0241234567',
    network: 'MTN',
    country: 'GH',
    vesspayReference: 'VP-PAY-TX001SAMPLE',
    createdAt: DateTime(2026, 9, 4, 16, 0),
  );

  final sampleCompletedTx = TransactionModel(
    id: 'tx-test-001',
    type: 'payout',
    status: 'COMPLETED',
    sourceCurrency: 'USD',
    sourceAmount: 12.95,
    destinationCurrency: 'GHS',
    destinationAmount: 150.0,
    fee: 0.13,
    exchangeRate: 11.58,
    recipientName: 'Kwame Mensah',
    recipientPhone: '0241234567',
    network: 'MTN',
    country: 'GH',
    vesspayReference: 'VP-PAY-TX001SAMPLE',
    wewireReference: 'ww-tx-12345',
    createdAt: DateTime(2026, 9, 4, 16, 0),
  );

  final sampleFailedTx = TransactionModel(
    id: 'tx-test-001',
    type: 'payout',
    status: 'FAILED',
    sourceCurrency: 'USD',
    sourceAmount: 12.95,
    destinationCurrency: 'GHS',
    destinationAmount: 150.0,
    fee: 0.13,
    exchangeRate: 11.58,
    recipientName: 'Kwame Mensah',
    recipientPhone: '0241234567',
    network: 'MTN',
    country: 'GH',
    vesspayReference: 'VP-PAY-TX001SAMPLE',
    errorMessage: 'Recipient mobile money account is suspended or blocked.',
    createdAt: DateTime(2026, 9, 4, 16, 0),
  );

  group('T5.6: Payment Processing, Success, and Failure Screens', () {
    testWidgets(
      'Acceptance Criteria: Processing state shows real progress and NEVER shows Success while status is PENDING or PROCESSING',
      (WidgetTester tester) async {
        final mockRepo = ControllablePaymentRepository(samplePendingTx);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              paymentRepositoryProvider.overrideWithValue(mockRepo),
            ],
            child: MaterialApp(
              home: PaymentProcessingScreen(
                transactionId: samplePendingTx.id,
                initialTransaction: samplePendingTx,
              ),
            ),
          ),
        );

        // Verify initial render: shows Processing Payment, not Success
        expect(find.byKey(const Key('processing_title')), findsOneWidget);
        expect(find.text('Processing Payment'), findsOneWidget);
        expect(find.byKey(const Key('processing_step_label')), findsOneWidget);
        expect(find.byKey(const Key('processing_dest_amount')), findsOneWidget);
        expect(find.text('GHS 150.00'), findsOneWidget);
        expect(find.text('Kwame Mensah'), findsOneWidget);

        // MUST NOT show success while backend status is PENDING
        expect(find.byKey(const Key('success_title')), findsNothing);
        expect(find.text('Payment Sent!'), findsNothing);

        // Advance 2 seconds while status moves to PROCESSING
        final processingTx = TransactionModel(
          id: samplePendingTx.id,
          type: 'payout',
          status: 'PROCESSING',
          sourceCurrency: 'USD',
          sourceAmount: 12.95,
          destinationCurrency: 'GHS',
          destinationAmount: 150.0,
          fee: 0.13,
          exchangeRate: 11.58,
          recipientName: 'Kwame Mensah',
          recipientPhone: '0241234567',
          network: 'MTN',
          country: 'GH',
          createdAt: DateTime(2026, 9, 4, 16, 0),
        );
        mockRepo.updateTransaction(processingTx);

        await tester.pump(const Duration(seconds: 2));

        // Still in processing state
        expect(find.byKey(const Key('processing_title')), findsOneWidget);
        expect(find.text('Partner network processing payout...'), findsOneWidget);
        expect(find.text('Payment Sent!'), findsNothing);

        mockRepo.dispose();
      },
    );

    testWidgets(
      'PaymentSuccessScreen renders twin currencies, recipient details, and VessPay reference',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: PaymentSuccessScreen(transaction: sampleCompletedTx),
            ),
          ),
        );

        // Verify hero elements
        expect(find.byKey(const Key('success_title')), findsOneWidget);
        expect(find.text('Payment Sent!'), findsOneWidget);

        // Verify twin-currency display: Recipient got GHS 150.00 / You paid $13.08
        expect(find.byKey(const Key('success_recipient_amount')), findsOneWidget);
        expect(find.text('GHS 150.00'), findsOneWidget);
        expect(find.byKey(const Key('success_you_pay_amount')), findsOneWidget);
        expect(find.text('\$13.08'), findsOneWidget);

        // Verify details card
        expect(find.text('Kwame Mensah'), findsOneWidget);
        expect(find.text('0241234567'), findsOneWidget);
        expect(find.text('MTN'), findsOneWidget);
        expect(find.text('COMPLETED'), findsOneWidget);
        expect(find.text('VP-PAY-TX001SAMPLE'), findsOneWidget);

        // Verify Done button
        expect(find.byKey(const Key('success_done_button')), findsOneWidget);
      },
    );

    testWidgets(
      'PaymentFailureScreen prominently reassures user money is safe and offers retry button',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: PaymentFailureScreen(transaction: sampleFailedTx),
            ),
          ),
        );

        // Verify failure header
        expect(find.byKey(const Key('failure_title')), findsOneWidget);
        expect(find.text('Payment Could Not Be Completed'), findsOneWidget);
        expect(
          find.text('Recipient mobile money account is suspended or blocked.'),
          findsOneWidget,
        );

        // MANDATORY REASSURANCE CHECK
        expect(find.byKey(const Key('failure_reassurance_card')), findsOneWidget);
        expect(find.text('Your money is safe'), findsOneWidget);
        expect(
          find.text(
            'No funds were deducted from your wallet. If any funds were temporarily held, they have been completely restored to your balance.',
          ),
          findsOneWidget,
        );

        // Verify retry and wallet buttons
        expect(find.byKey(const Key('failure_retry_button')), findsOneWidget);
        expect(find.byKey(const Key('failure_wallet_button')), findsOneWidget);
      },
    );

    testWidgets(
      'PaymentReviewScreen Confirm Payment initiates payout and disables button during submission',
      (WidgetTester tester) async {
        final mockRepo = ControllablePaymentRepository(samplePendingTx);
        final completer = Completer<CreatePaymentResponse>();
        mockRepo.createPaymentCompleter = completer;

        const samplePayData = PayFlowData(
          countryCode: 'GH',
          countryName: 'Ghana',
          countryFlag: '🇬🇭',
          paymentType: PaymentType.mobileMoney,
          network: 'MTN',
          recipientPhone: '0241234567',
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
          phone: '0241234567',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              paymentRepositoryProvider.overrideWithValue(mockRepo),
            ],
            child: const MaterialApp(
              home: PaymentReviewScreen(
                dataOverride: samplePayData,
                quoteOverride: sampleQuote,
              ),
            ),
          ),
        );

        final confirmButton =
            find.byKey(const Key('review_confirm_payment_button'));
        expect(confirmButton, findsOneWidget);

        // Ensure button is visible within scrollview before tapping
        await tester.ensureVisible(confirmButton);
        await tester.pumpAndSettle();

        // Tap confirm button
        await tester.tap(confirmButton);
        await tester.pump();

        // Button should be in submitting state showing progress indicator
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Complete the in-flight payout creation
        completer.complete(CreatePaymentResponse(
          transactionId: samplePendingTx.id,
          status: 'PENDING',
        ));
        await tester.pump();

        mockRepo.dispose();
      },
    );
  });
}
