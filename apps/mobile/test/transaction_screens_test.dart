import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vesspay/core/routing/app_routes.dart';
import 'package:vesspay/core/routing/app_router.dart';
import 'package:vesspay/features/pay/models/payment_quote_model.dart';
import 'package:vesspay/features/pay/models/payment_response_model.dart';
import 'package:vesspay/features/pay/models/transaction_model.dart';
import 'package:vesspay/features/pay/providers/recent_activity_provider.dart';
import 'package:vesspay/features/pay/models/payout_institution_model.dart';
import 'package:vesspay/features/pay/models/recipient_resolution_model.dart';
import 'package:vesspay/features/pay/repositories/payment_repository.dart';
import 'package:vesspay/features/pay/screens/transaction_list_screen.dart';
import 'package:vesspay/features/pay/screens/transaction_detail_screen.dart';
import 'package:vesspay/features/pay/screens/payment_success_screen.dart';

class MockPaymentRepository implements PaymentRepository {
  @override
  Future<List<PayoutInstitutionModel>> getInstitutions({
    String currency = 'GHS',
    String? channel,
  }) async =>
      kFallbackGhanaBanks;

  @override
  Future<RecipientResolutionModel> resolveRecipientName({
    required String phone,
    String? network,
  }) async =>
      RecipientResolutionModel.unresolved(phone);

  List<TransactionModel> transactions = [];
  TransactionModel? detailTx;

  @override
  Future<List<TransactionModel>> getTransactions() async {
    return transactions;
  }

  @override
  Future<TransactionModel> getPaymentById(String id) async {
    if (detailTx != null && detailTx!.id == id) {
      return detailTx!;
    }
    return transactions.firstWhere(
      (tx) => tx.id == id,
      orElse: () => TransactionModel(
        id: id,
        type: 'payout',
        status: 'COMPLETED',
        sourceCurrency: 'USD',
        sourceAmount: 10.0,
        destinationCurrency: 'GHS',
        destinationAmount: 150.0,
        fee: 0.10,
        exchangeRate: 15.0,
        recipientName: 'Kofi Mensah',
        recipientPhone: '+233241234567',
        network: 'MTN',
        country: 'GH',
        vesspayReference: 'VP-PAY-TEST1234',
        wewireReference: 'WW-DISB-998877',
        createdAt: DateTime.now(),
      ),
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
    throw UnimplementedError();
  }

  @override
  Future<PaymentQuoteModel> getQuote({
    required String country,
    required String network,
    required String phone,
    required double destinationAmount,
    String destinationCurrency = 'GHS',
  }) async {
    throw UnimplementedError();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 14, 30);
  final yesterday = today.subtract(const Duration(days: 1));
  final lastMonth = DateTime(2026, 8, 15, 10, 0);

  final sampleTxToday = TransactionModel(
    id: 'tx-today-1',
    type: 'payout',
    status: 'COMPLETED',
    sourceCurrency: 'USD',
    sourceAmount: 10.0,
    destinationCurrency: 'GHS',
    destinationAmount: 150.0,
    fee: 0.10,
    exchangeRate: 15.0,
    recipientName: 'Ama Serwaa',
    recipientPhone: '+233201112233',
    network: 'Telecel',
    country: 'GH',
    vesspayReference: 'VP-PAY-AMA1234',
    wewireReference: 'WW-DISB-AMA789',
    createdAt: today,
  );

  final sampleTxYesterday = TransactionModel(
    id: 'tx-yesterday-1',
    type: 'payout',
    status: 'PENDING',
    sourceCurrency: 'USD',
    sourceAmount: 20.0,
    destinationCurrency: 'GHS',
    destinationAmount: 300.0,
    fee: 0.20,
    exchangeRate: 15.0,
    recipientName: 'Kwame Nkrumah',
    recipientPhone: '+233244445566',
    network: 'MTN',
    country: 'GH',
    vesspayReference: 'VP-PAY-KWAME56',
    wewireReference: 'WW-DISB-KWM44',
    createdAt: yesterday,
  );

  final sampleTxOlder = TransactionModel(
    id: 'tx-older-1',
    type: 'payout',
    status: 'FAILED',
    sourceCurrency: 'USD',
    sourceAmount: 5.0,
    destinationCurrency: 'GHS',
    destinationAmount: 75.0,
    fee: 0.05,
    exchangeRate: 15.0,
    recipientName: 'Kojo Antwi',
    recipientPhone: '+233501234567',
    network: 'AT',
    country: 'GH',
    vesspayReference: 'VP-PAY-KOJO99',
    wewireReference: 'WW-DISB-KOJ99',
    errorMessage: 'Insufficient provider liquidity',
    createdAt: lastMonth,
  );

  group('T5.7: Date Grouping Utilities', () {
    test('formatGroupingDate categorizes Today, Yesterday, and specific date correctly', () {
      expect(formatGroupingDate(today), 'Today');
      expect(formatGroupingDate(yesterday), 'Yesterday');
      expect(formatGroupingDate(DateTime(2026, 9, 1)), '1 September 2026');
      expect(formatGroupingDate(DateTime(2026, 8, 15)), '15 August 2026');
    });

    test('groupTransactionsByDate groups items into chronological date buckets', () {
      final groups = groupTransactionsByDate([
        sampleTxToday,
        sampleTxYesterday,
        sampleTxOlder,
      ]);

      expect(groups.keys.toList(), ['Today', 'Yesterday', '15 August 2026']);
      expect(groups['Today']!.length, 1);
      expect(groups['Today']!.first.id, 'tx-today-1');
      expect(groups['Yesterday']!.length, 1);
      expect(groups['Yesterday']!.first.id, 'tx-yesterday-1');
      expect(groups['15 August 2026']!.length, 1);
      expect(groups['15 August 2026']!.first.id, 'tx-older-1');
    });
  });

  group('T5.7: TransactionListScreen Widget Tests', () {
    testWidgets('Renders empty state when no transactions exist', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: TransactionListScreen(
              transactionsOverride: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Transactions'), findsOneWidget);
      expect(find.byKey(const Key('transactions_empty_text')), findsOneWidget);
      expect(find.text('Pay Anyone'), findsOneWidget);
    });

    testWidgets('Renders grouped transactions with headers, amounts, and badges', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: TransactionListScreen(
              transactionsOverride: [
                sampleTxToday,
                sampleTxYesterday,
                sampleTxOlder,
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check date group headers
      expect(find.byKey(const Key('date_group_today')), findsOneWidget);
      expect(find.byKey(const Key('date_group_yesterday')), findsOneWidget);
      expect(find.byKey(const Key('date_group_15_august_2026')), findsOneWidget);

      // Check transaction rows
      expect(find.text('Transfer to Ama Serwaa'), findsOneWidget);
      expect(find.text('- GHS 150.00'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);

      expect(find.text('Transfer to Kwame Nkrumah'), findsOneWidget);
      expect(find.text('- GHS 300.00'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);

      expect(find.text('Transfer to Kojo Antwi'), findsOneWidget);
      expect(find.text('- GHS 75.00'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
    });
  });

  group('T5.7: TransactionDetailScreen Widget Tests', () {
    testWidgets('Renders all blueprint transaction fields correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TransactionDetailScreen(
            transaction: sampleTxToday,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // App bar & title
      expect(find.text('Transaction Details'), findsOneWidget);

      // Hero Amount & Badge
      expect(find.byKey(const Key('detail_hero_amount')), findsOneWidget);
      expect(find.text('GHS 150.00'), findsNWidgets(2));
      expect(find.text('-\$10.10 USD total debited'), findsOneWidget);
      expect(find.byKey(const Key('detail_status_badge')), findsOneWidget);
      expect(find.text('COMPLETED'), findsOneWidget);

      // Recipient Card
      expect(find.text('RECIPIENT'), findsOneWidget);
      expect(find.text('Ama Serwaa'), findsOneWidget);
      expect(find.text('+233201112233'), findsOneWidget);
      expect(find.text('Telecel'), findsOneWidget);

      // Payment Breakdown
      expect(find.text('PAYMENT BREAKDOWN'), findsOneWidget);
      expect(find.text('\$10.00 USD'), findsOneWidget);
      expect(find.text('\$0.10 USD'), findsOneWidget);
      expect(find.text('1 USD = 15.00 GHS'), findsOneWidget);
      expect(find.text('\$10.10 USD'), findsOneWidget);

      // Transaction References
      expect(find.text('TRANSACTION REFERENCES'), findsOneWidget);
      expect(find.text('VP-PAY-AMA1234'), findsOneWidget);
      expect(find.text('WW-DISB-AMA789'), findsOneWidget);
      expect(find.text('PAYOUT'), findsOneWidget);

      // Done button
      expect(find.byKey(const Key('transaction_detail_done_button')), findsOneWidget);
    });

    testWidgets('Loads transaction by ID using transactionDetailProvider', (tester) async {
      final mockRepo = MockPaymentRepository();
      mockRepo.detailTx = sampleTxYesterday;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paymentRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(
            home: TransactionDetailScreen(
              transactionId: 'tx-yesterday-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('GHS 300.00'), findsNWidgets(2));
      expect(find.text('Kwame Nkrumah'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);
      expect(find.text('VP-PAY-KWAME56'), findsOneWidget);
    });
  });

  group('T5.7: Acceptance Criteria — Immediate Visibility After Success', () {
    testWidgets('Completed demo payment appears immediately in transaction list after success', (tester) async {
      final mockRepo = MockPaymentRepository();
      mockRepo.transactions = [sampleTxYesterday]; // initially only yesterday's tx

      final router = GoRouter(
        initialLocation: AppRoutes.transactionList,
        routes: [
          GoRoute(
            path: AppRoutes.transactionList,
            builder: (context, state) => const TransactionListScreen(),
          ),
          GoRoute(
            path: AppRoutes.paymentSuccess,
            builder: (context, state) => PaymentSuccessScreen(transaction: sampleTxToday),
          ),
          GoRoute(
            path: AppRoutes.transactionDetail,
            builder: (context, state) {
              final tx = state.extra as TransactionModel?;
              return TransactionDetailScreen(transaction: tx);
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paymentRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially only Yesterday's transaction is displayed
      expect(find.byKey(const Key('date_group_yesterday')), findsOneWidget);
      expect(find.text('Transfer to Kwame Nkrumah'), findsOneWidget);
      expect(find.text('Transfer to Ama Serwaa'), findsNothing);

      // Now a demo payment completes: simulate navigating to PaymentSuccessScreen
      mockRepo.transactions = [sampleTxToday, sampleTxYesterday];
      router.push(AppRoutes.paymentSuccess);
      await tester.pumpAndSettle();

      // On PaymentSuccessScreen, verify receipt details and button
      expect(find.text('Payment Sent!'), findsOneWidget);
      expect(find.byKey(const Key('success_view_history_button')), findsOneWidget);

      // Scroll to button & tap 'View Transaction Receipt'
      await tester.ensureVisible(find.byKey(const Key('success_view_history_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('success_view_history_button')));
      await tester.pumpAndSettle();

      // Verify we arrived on TransactionDetailScreen with sampleTxToday
      expect(find.text('Transaction Details'), findsOneWidget);
      expect(find.text('Ama Serwaa'), findsOneWidget);
      expect(find.text('VP-PAY-AMA1234'), findsOneWidget);

      // Pop back to transactions list
      router.go(AppRoutes.transactionList);
      await tester.pumpAndSettle();

      // The completed transaction immediately appears in the list under Today!
      expect(find.byKey(const Key('date_group_today')), findsOneWidget);
      expect(find.text('Transfer to Ama Serwaa'), findsOneWidget);
      expect(find.text('- GHS 150.00'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
    });

    testWidgets('Tapping transaction row navigates to TransactionDetailScreen', (tester) async {
      final mockRepo = MockPaymentRepository();
      mockRepo.transactions = [sampleTxToday];

      final router = GoRouter(
        initialLocation: AppRoutes.transactionList,
        routes: [
          GoRoute(
            path: AppRoutes.transactionList,
            builder: (context, state) => const TransactionListScreen(),
          ),
          GoRoute(
            path: AppRoutes.transactionDetail,
            builder: (context, state) {
              final tx = state.extra as TransactionModel?;
              return TransactionDetailScreen(transaction: tx);
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paymentRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the transaction item row
      final rowFinder = find.byKey(Key('transaction_item_${sampleTxToday.id}'));
      expect(rowFinder, findsOneWidget);
      await tester.tap(rowFinder);
      await tester.pumpAndSettle();

      // Verified navigated to TransactionDetailScreen
      expect(find.text('Transaction Details'), findsOneWidget);
      expect(find.text('Ama Serwaa'), findsOneWidget);
      expect(find.text('VP-PAY-AMA1234'), findsOneWidget);
    });

    testWidgets('createAppRouter navigates correctly to transactionList and transactionDetail', (tester) async {
      final mockRepo = MockPaymentRepository();
      mockRepo.detailTx = sampleTxToday;

      final router = createAppRouter(initialLocation: AppRoutes.transactionList);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paymentRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Transactions'), findsOneWidget);

      router.push(AppRoutes.transactionDetail, extra: sampleTxToday);
      await tester.pumpAndSettle();

      expect(find.text('Transaction Details'), findsOneWidget);
      expect(find.text('Ama Serwaa'), findsOneWidget);
    });
  });
}
