import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vesspay/features/wallet/models/deposit_account_model.dart';
import 'package:vesspay/core/routing/app_router.dart';
import 'package:vesspay/core/routing/app_routes.dart';
import 'package:vesspay/features/pay/models/pay_flow_model.dart';
import 'package:vesspay/features/pay/models/payment_estimate.dart';
import 'package:vesspay/features/pay/providers/pay_anyone_providers.dart';
import 'package:vesspay/features/pay/screens/payment_review_screen.dart';

import 'package:vesspay/features/pay/models/payment_quote_model.dart';
import 'package:vesspay/features/pay/models/transaction_model.dart';
import 'package:vesspay/features/pay/models/payout_institution_model.dart';
import 'package:vesspay/features/pay/models/recipient_resolution_model.dart';
import 'package:vesspay/features/kyc/models/kyc_model.dart';
import 'package:vesspay/features/kyc/repositories/kyc_repository.dart';
import 'package:vesspay/features/pay/repositories/payment_repository.dart';
import 'package:vesspay/features/wallet/models/topup_model.dart';
import 'package:vesspay/features/wallet/models/wallet_balance_model.dart';
import 'package:vesspay/features/wallet/models/wallet_currency_model.dart';
import 'package:vesspay/features/wallet/repositories/wallet_repository.dart';

import 'package:vesspay/features/pay/models/payment_response_model.dart';

/// Money-movement screens are gated on KYC, so these tests act as a verified
/// user; the gate itself is covered in kyc_flow_test.dart.
class VerifiedKycRepository implements KycRepository {
  @override
  Future<KycLinkModel> getKycLink() async =>
      KycLinkModel(url: 'https://verify.wewire.com/session', stage: 'ONBOARDING');

  @override
  Future<KycStatusModel> getKycStatus() async => KycStatusModel(
        onboardingStatus: 'APPROVED',
        enhancedKycStatus: 'TIER_2',
      );

  @override
  Future<KycStatusModel> submitDemoKyc() async => getKycStatus();
}

class MockPaymentRepository implements PaymentRepository {
  final List<TransactionModel> transactions;
  final List<PayoutInstitutionModel>? institutions;

  /// Records what the screen asked for, so tests can assert the wiring.
  final List<String> institutionQueries = [];
  Map<String, dynamic>? lastCreatePayment;

  MockPaymentRepository({this.transactions = const [], this.institutions});

  @override
  Future<List<PayoutInstitutionModel>> getInstitutions({
    String currency = 'GHS',
    String? channel,
  }) async {
    institutionQueries.add('$currency/${channel ?? 'ALL'}');
    return institutions ?? kFallbackGhanaBanks;
  }

  @override
  Future<RecipientResolutionModel> resolveRecipientName({
    String? phone,
    String? accountNumber,
    String? network,
  }) async =>
      RecipientResolutionModel.unresolved(phone ?? accountNumber ?? '');

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
      destinationAmount: destinationAmount > 0 ? destinationAmount : 150.0,
      exchangeRate: 11.58,
      fee: 0.13,
      total: 13.08,
      country: country,
      network: network,
      phone: phone,
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
    lastCreatePayment = {
      'country': country,
      'network': network,
      'phone': channel == 'BANK' ? null : phone,
      'accountNumber': accountNumber,
      'channel': channel,
      'destinationAmount': destinationAmount,
      'recipientName': recipientName,
    };
    return const CreatePaymentResponse(
      transactionId: 'test-flow-tx-123',
      status: 'PENDING',
    );
  }

  @override
  Future<TransactionModel> getPaymentById(String id) async {
    return TransactionModel(
      id: id,
      type: 'payout',
      status: 'COMPLETED',
      sourceCurrency: 'USD',
      sourceAmount: 12.95,
      destinationCurrency: 'GHS',
      destinationAmount: 150.0,
      fee: 0.13,
      exchangeRate: 11.58,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<List<TransactionModel>> getTransactions() async => transactions;
}

class ResolvingPaymentRepository extends MockPaymentRepository {
  final List<String> lookups = [];

  ResolvingPaymentRepository({super.transactions});

  @override
  Future<RecipientResolutionModel> resolveRecipientName({
    String? phone,
    String? accountNumber,
    String? network,
  }) async {
    lookups.add(phone ?? accountNumber ?? '');
    if (phone == '0249510123') {
      return const RecipientResolutionModel(
        resolved: true,
        phone: '0249510123',
        network: 'Telecel',
        name: 'Ama Serwaa',
        source: 'beneficiary',
      );
    }
    return RecipientResolutionModel.unresolved(phone ?? accountNumber ?? '');
  }
}

/// Stands in for the operator/bank name enquiry: the account holder comes back
/// confirmed, the way GET /api/beneficiaries/resolve reports a provider match.
class VerifyingPaymentRepository extends MockPaymentRepository {
  final List<String> lookups = [];

  VerifyingPaymentRepository({super.transactions});

  @override
  Future<RecipientResolutionModel> resolveRecipientName({
    String? phone,
    String? accountNumber,
    String? network,
  }) async {
    final target = phone ?? accountNumber ?? '';
    lookups.add(target);

    if (target == '0249510123') {
      return const RecipientResolutionModel(
        resolved: true,
        verified: true,
        phone: '0249510123',
        network: 'MTN Mobile Money',
        institutionCode: 'MTN',
        channel: 'MOBILE_MONEY',
        name: 'Janet Adzo Ahialey',
        source: 'provider',
      );
    }

    if (target == '1234567890123') {
      return const RecipientResolutionModel(
        resolved: true,
        verified: true,
        phone: '',
        accountNumber: '1234567890123',
        network: 'GCB BANK LIMITED',
        institutionCode: 'GCB',
        channel: 'BANK',
        name: 'Kwabena Owusu',
        source: 'provider',
      );
    }

    return RecipientResolutionModel.unresolved(target);
  }
}

class StubWalletRepository implements WalletRepository {
  final double usdBalance;

  StubWalletRepository({this.usdBalance = 500.0});

  @override
  Future<List<WalletBalanceModel>> getBalances() async => [
        WalletBalanceModel(currency: 'USD', balance: usdBalance),
      ];

  @override
  Future<List<WalletCurrencyModel>> getSupportedCurrencies() async =>
      kDefaultWalletCurrencies;

  @override
  Future<String> setPrimaryCurrency(String currencyCode) async =>
      currencyCode.toUpperCase();

  @override
  Future<TopupResponseModel> initiateTopup({
    required double amount,
    String currency = 'USD',
  }) async =>
      throw UnimplementedError();

  @override
  Future<TopupResponseModel> getTopupStatus(String fundingTransactionId) async =>
      throw UnimplementedError();

  @override
  Future<TopupResponseModel> confirmTopup(String fundingTransactionId) async =>
      throw UnimplementedError();

  @override
  Future<DepositAccountModel> getDepositAccount() async =>
      const DepositAccountModel(
        state: DepositAccountState.ready,
        currency: 'USD',
      );

  @override
  Future<DepositAccountModel> provisionDepositAccount({
    String? sourceOfFunds,
  }) async =>
      const DepositAccountModel(
        state: DepositAccountState.ready,
        currency: 'USD',
      );
}

TransactionModel payoutTo(
  String name,
  String phone, {
  String network = 'MTN',
  String id = 'tx-1',
}) {
  return TransactionModel(
    id: id,
    type: 'payout',
    status: 'COMPLETED',
    sourceCurrency: 'USD',
    sourceAmount: 12.95,
    destinationCurrency: 'GHS',
    destinationAmount: 150.0,
    fee: 0.13,
    exchangeRate: 11.58,
    recipientName: name,
    recipientPhone: phone,
    network: network,
    country: 'GH',
    createdAt: DateTime.now(),
  );
}

/// The form is one long page, so lower controls have to be scrolled into view
/// before they can be tapped.
Future<void> tapChip(WidgetTester tester, int amount) async {
  final finder = find.byKey(Key('pay_chip_$amount'));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// A recipient nobody could confirm needs the user's own tick before the
/// payment can be reviewed.
Future<void> confirmRecipient(WidgetTester tester) async {
  final tick = find.byKey(const Key('pay_recipient_name_confirm_tick'));
  if (tick.evaluate().isEmpty) return;
  await tester.ensureVisible(tick);
  await tester.pumpAndSettle();
  await tester.tap(tick);
  await tester.pumpAndSettle();
}

Future<void> selectNetwork(WidgetTester tester, String key) async {
  final dropdown = find.byKey(const Key('pay_network_dropdown'));
  await tester.ensureVisible(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)).last, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  Widget createTestWidget({
    String initialRoute = AppRoutes.payAnyone,
    PaymentRepository? paymentRepository,
    WalletRepository? walletRepository,
  }) {
    final router = createAppRouter(initialLocation: initialRoute);
    return ProviderScope(
      overrides: [
        paymentRepositoryProvider
            .overrideWithValue(paymentRepository ?? MockPaymentRepository()),
        kycRepositoryProvider.overrideWithValue(VerifiedKycRepository()),
        if (walletRepository != null)
          walletRepositoryProvider.overrideWithValue(walletRepository),
      ],
      child: MaterialApp.router(
        routerConfig: router,
      ),
    );
  }

  group('T4.3: Pay Anyone single-page send form', () {
    testWidgets(
        'Method, destination, recipient and amount all live on one page',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Pay Anyone'), findsOneWidget);
      expect(find.text('Send money'), findsOneWidget);

      // Country is already determined from onboarding (Ghana by default)
      expect(
          find.byKey(const Key('pay_determined_country_badge')), findsOneWidget);
      expect(find.text('Destination: Ghana'), findsOneWidget);

      // Payment method is a compact control, not its own step
      expect(find.byKey(const Key('pay_type_mobile_money')), findsOneWidget);
      expect(find.byKey(const Key('pay_type_bank')), findsOneWidget);

      // Recipient and amount are on the same page
      expect(find.byKey(const Key('pay_network_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('pay_recipient_phone_field')), findsOneWidget);
      expect(find.byKey(const Key('pay_recipient_name_field')), findsOneWidget);
      expect(find.byKey(const Key('pay_amount_field')), findsOneWidget);
      expect(find.byKey(const Key('pay_chip_150')), findsOneWidget);

      // A single CTA leads to the review screen
      expect(find.byKey(const Key('pay_continue_to_review_button')),
          findsOneWidget);
      expect(find.byKey(const Key('pay_step1_continue_button')), findsNothing);
      expect(find.byKey(const Key('pay_step2_continue_button')), findsNothing);
    });

    testWidgets('Switching to Bank swaps in the bank fields',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pay_type_bank')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pay_account_number_field')), findsOneWidget);
      expect(find.byKey(const Key('pay_recipient_phone_field')), findsNothing);
      // Banks come from the institution list, defaulting to GCB
      expect(find.text('GCB Bank Limited'), findsWidgets);
      expect(find.text('Account Holder Name'), findsOneWidget);
    });

    testWidgets('Network can be picked manually and the phone is validated',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Select Telecel from the dropdown
      await selectNetwork(tester, 'pay_network_telecel');

      // Submitting with an empty phone fails validation
      await tester.tap(find.byKey(const Key('pay_continue_to_review_button')));
      await tester.pumpAndSettle();
      expect(find.text('Please enter recipient phone number'), findsOneWidget);

      // Too short also fails
      await tester.enterText(
          find.byKey(const Key('pay_recipient_phone_field')), '1234');
      await tester.tap(find.byKey(const Key('pay_continue_to_review_button')));
      await tester.pumpAndSettle();
      expect(find.text('Please enter a valid Ghana phone number (min 9 digits)'),
          findsOneWidget);

      // A valid number with no amount also stops at validation
      await tester.enterText(
          find.byKey(const Key('pay_recipient_phone_field')), '024 123 4567');
      await tester.tap(find.byKey(const Key('pay_continue_to_review_button')));
      await tester.pumpAndSettle();
      expect(find.text('Please enter an amount'), findsOneWidget);
      expect(find.byType(PaymentReviewScreen), findsNothing);
    });

    testWidgets('The network is inferred from the number prefix',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // 020 is a Telecel range
      await tester.enterText(
          find.byKey(const Key('pay_recipient_phone_field')), '0201234567');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pay_network_auto_badge')), findsOneWidget);
      expect(find.text('Telecel Cash'), findsWidgets);

      // 026 is an AirtelTigo range
      await tester.enterText(
          find.byKey(const Key('pay_recipient_phone_field')), '0261234567');
      await tester.pumpAndSettle();
      expect(find.text('AirtelTigo Money'), findsWidgets);

      // A manual choice wins and stops the inference
      await selectNetwork(tester, 'pay_network_mtn');

      await tester.enterText(
          find.byKey(const Key('pay_recipient_phone_field')), '0201234567');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pay_network_auto_badge')), findsNothing);
      expect(find.text('MTN Mobile Money'), findsWidgets);
    });

    testWidgets(
        'Live estimate updates as the amount is typed and Review lands with data intact',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('pay_recipient_phone_field')), '0241234567');
      await tester.enterText(
          find.byKey(const Key('pay_recipient_name_field')), 'Kwame Mensah');
      await tester.pumpAndSettle();

      await tapChip(tester, 150);

      expect(find.byKey(const Key('pay_live_rate_text')), findsOneWidget);
      expect(find.byKey(const Key('pay_estimated_usd_text')), findsOneWidget);
      expect(find.byKey(const Key('pay_estimated_fee_text')), findsOneWidget);
      expect(find.byKey(const Key('pay_estimated_total_text')), findsOneWidget);
      expect(find.byKey(const Key('pay_estimate_disclaimer')), findsOneWidget);
      await confirmRecipient(tester);

      await tester.tap(find.byKey(const Key('pay_continue_to_review_button')));
      await tester.pumpAndSettle();

      // ==========================================================
      // Acceptance Criteria: Lands on Review screen with data intact
      // ==========================================================
      expect(find.byType(PaymentReviewScreen), findsOneWidget);

      expect(find.byKey(const Key('review_destination_amount')), findsOneWidget);
      expect(find.text('GH₵150.00'), findsWidgets);

      expect(find.byKey(const Key('review_recipient_phone')), findsOneWidget);
      expect(find.text('0241234567'), findsOneWidget);

      expect(find.byKey(const Key('review_recipient_name')), findsOneWidget);
      expect(find.text('Kwame Mensah'), findsOneWidget);

      expect(find.byKey(const Key('review_country')), findsOneWidget);
      expect(find.text('🇬🇭 Ghana'), findsOneWidget);
      expect(find.byKey(const Key('review_network')), findsOneWidget);
      expect(find.text('MTN'), findsOneWidget);

      expect(find.byKey(const Key('review_confirm_payment_button')),
          findsOneWidget);
    });

    testWidgets('Details entered earlier are restored when the form reopens',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('pay_recipient_phone_field')), '0241234567');
      await tester.enterText(
          find.byKey(const Key('pay_recipient_name_field')), 'Kwame Mensah');
      await tapChip(tester, 150);
      await confirmRecipient(tester);

      // Go to review, then come back with the flow's back button
      await tester.tap(find.byKey(const Key('pay_continue_to_review_button')));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentReviewScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('review_back_button')));
      await tester.pumpAndSettle();

      expect(find.text('Send money'), findsOneWidget);
      expect(find.text('0241234567'), findsOneWidget);
      expect(find.text('Kwame Mensah'), findsOneWidget);
      expect(find.text('150'), findsWidgets);
    });

    testWidgets('PaymentReviewScreen renders standalone with dataOverride',
        (WidgetTester tester) async {
      const testData = PayFlowData(
        countryCode: 'GH',
        countryName: 'Ghana',
        countryFlag: '🇬🇭',
        paymentType: PaymentType.mobileMoney,
        network: 'MTN',
        recipientPhone: '0241234567',
        recipientName: 'Alex Taxi',
        destinationAmount: 150.0,
        quoteSourceAmount: 12.95,
        quoteFee: 0.13,
        quoteTotal: 13.08,
        exchangeRate: 11.58,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paymentRepositoryProvider.overrideWithValue(MockPaymentRepository()),
          ],
          child: const MaterialApp(
            home: PaymentReviewScreen(dataOverride: testData),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(PaymentReviewScreen), findsOneWidget);
      expect(find.text('GH₵150.00'), findsWidgets);
      expect(find.text('0241234567'), findsOneWidget);
      expect(find.text('Alex Taxi'), findsOneWidget);
      expect(find.text('\$12.95'), findsOneWidget);
      expect(find.text('\$0.13'), findsOneWidget);
      expect(find.text('\$13.08'), findsWidgets);
    });
  });

  group('Bank transfers', () {
    testWidgets('The bank list is loaded from the institutions endpoint',
        (WidgetTester tester) async {
      final repository = MockPaymentRepository(
        institutions: const [
          PayoutInstitutionModel(
              code: 'ECO', name: 'ECOBANK GHANA LTD', channel: 'BANK'),
          PayoutInstitutionModel(
              code: 'CAL', name: 'CAL BANK LIMITED', channel: 'BANK'),
        ],
      );
      await tester.pumpWidget(createTestWidget(paymentRepository: repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pay_type_bank')));
      await tester.pumpAndSettle();

      expect(repository.institutionQueries, contains('GHS/BANK'));
      await selectNetwork(tester, 'pay_network_cal');
      expect(find.text('CAL Bank Limited'), findsWidgets);
    });

    testWidgets('Account number and holder name are validated',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pay_type_bank')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pay_continue_to_review_button')));
      await tester.pumpAndSettle();
      expect(find.text('Please enter account number'), findsOneWidget);
      expect(find.text('Please enter account holder name'), findsOneWidget);

      // Too short for any Ghana bank account
      await tester.enterText(
          find.byKey(const Key('pay_account_number_field')), '12345');
      await tester.tap(find.byKey(const Key('pay_continue_to_review_button')));
      await tester.pumpAndSettle();
      expect(find.text('Please enter a valid account number (8-20 digits)'),
          findsOneWidget);
      expect(find.byType(PaymentReviewScreen), findsNothing);
    });

    testWidgets('A complete bank payment reaches review with its details',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pay_type_bank')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('pay_account_number_field')), '1234567890123');
      await tester.enterText(
          find.byKey(const Key('pay_recipient_name_field')), 'Kwabena Owusu');
      await tapChip(tester, 150);

      await confirmRecipient(tester);
      await tester.tap(find.byKey(const Key('pay_continue_to_review_button')));
      await tester.pumpAndSettle();

      expect(find.byType(PaymentReviewScreen), findsOneWidget);
      expect(find.text('Account Number'), findsOneWidget);
      expect(find.text('1234567890123'), findsOneWidget);
      expect(find.text('Kwabena Owusu'), findsOneWidget);
    });

    testWidgets('Confirming a bank payment sends the BANK channel',
        (WidgetTester tester) async {
      final repository = MockPaymentRepository();
      await tester.pumpWidget(createTestWidget(paymentRepository: repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pay_type_bank')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('pay_account_number_field')), '1234567890123');
      await tester.enterText(
          find.byKey(const Key('pay_recipient_name_field')), 'Kwabena Owusu');
      await tapChip(tester, 150);

      await confirmRecipient(tester);
      await tester.tap(find.byKey(const Key('pay_continue_to_review_button')));
      await tester.pumpAndSettle();

      final confirm = find.byKey(const Key('review_confirm_payment_button'));
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pump();

      final call = repository.lastCreatePayment;
      expect(call, isNotNull);
      expect(call!['channel'], 'BANK');
      expect(call['accountNumber'], '1234567890123');
      expect(call['network'], 'GCB');
      expect(call['recipientName'], 'Kwabena Owusu');
    });

    testWidgets('Mobile money payments still send the MOBILE_MONEY channel',
        (WidgetTester tester) async {
      final repository = MockPaymentRepository();
      await tester.pumpWidget(createTestWidget(paymentRepository: repository));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('pay_recipient_phone_field')), '0241234567');
      await tester.enterText(
          find.byKey(const Key('pay_recipient_name_field')), 'Ama Serwaa');
      await tapChip(tester, 150);

      await confirmRecipient(tester);
      await tester.tap(find.byKey(const Key('pay_continue_to_review_button')));
      await tester.pumpAndSettle();

      final confirm = find.byKey(const Key('review_confirm_payment_button'));
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pump();

      final call = repository.lastCreatePayment;
      expect(call, isNotNull);
      expect(call!['channel'], 'MOBILE_MONEY');
      expect(call['phone'], '0241234567');
      expect(call['accountNumber'], isNull);
    });
  });

  group('Recent recipients shortcut', () {
    testWidgets('Tapping a previous recipient fills in the whole recipient',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        paymentRepository: MockPaymentRepository(
          transactions: [
            payoutTo('Ama Serwaa', '0201234567', network: 'Telecel'),
            payoutTo('Kofi Mensah', '0241234567', id: 'tx-2'),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pay_recent_recipients')), findsOneWidget);
      expect(find.text('Ama'), findsOneWidget);
      expect(find.text('Kofi'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pay_recent_recipient_0201234567')));
      await tester.pumpAndSettle();

      expect(find.text('0201234567'), findsOneWidget);
      expect(find.text('Ama Serwaa'), findsOneWidget);
      expect(find.text('Telecel Cash'), findsWidgets);
    });

    testWidgets('No shortcuts are shown for a user with no payment history',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pay_recent_recipients')), findsNothing);
    });
  });

  group('Wallet balance guard', () {
    testWidgets('Available balance is shown next to the estimate',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        walletRepository: StubWalletRepository(usdBalance: 500.0),
      ));
      await tester.pumpAndSettle();

      await tapChip(tester, 150);

      expect(find.byKey(const Key('pay_available_balance_text')), findsOneWidget);
      expect(find.text('Available \$500.00'), findsOneWidget);
      expect(
          find.byKey(const Key('pay_insufficient_balance_warning')), findsNothing);
    });

    testWidgets('An amount above the balance is blocked before review',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        walletRepository: StubWalletRepository(usdBalance: 5.0),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('pay_recipient_phone_field')), '0241234567');
      await tapChip(tester, 500);

      expect(find.byKey(const Key('pay_insufficient_balance_warning')),
          findsOneWidget);

      final cta = tester.widget<ElevatedButton>(
        find.byKey(const Key('pay_continue_to_review_button')),
      );
      expect(cta.onPressed, isNull);

      await tester.tap(find.byKey(const Key('pay_continue_to_review_button')));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentReviewScreen), findsNothing);
      expect(find.text('Send money'), findsOneWidget);
    });
  });

  group('Automatic recipient name resolution', () {
    testWidgets('typing a known recipient number fills in the name automatically',
        (WidgetTester tester) async {
      final repository = ResolvingPaymentRepository();
      await tester.pumpWidget(createTestWidget(paymentRepository: repository));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('pay_recipient_phone_field')), '0249510123');

      // Debounce window plus the lookup itself
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      expect(repository.lookups, ['0249510123']);
      expect(find.text('Ama Serwaa'), findsOneWidget);
      expect(
          find.byKey(const Key('pay_recipient_name_status')), findsOneWidget);
      expect(find.text('From your saved recipients'), findsOneWidget);
    });

    testWidgets('incomplete numbers are never sent to the backend',
        (WidgetTester tester) async {
      final repository = ResolvingPaymentRepository();
      await tester.pumpWidget(createTestWidget(paymentRepository: repository));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('pay_recipient_phone_field')), '02495');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      expect(repository.lookups, isEmpty);
      expect(find.byKey(const Key('pay_recipient_name_status')), findsNothing);
    });

    testWidgets('a name typed by the user is not overwritten by the lookup',
        (WidgetTester tester) async {
      final repository = ResolvingPaymentRepository();
      await tester.pumpWidget(createTestWidget(paymentRepository: repository));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('pay_recipient_name_field')), 'Taxi Driver');
      await tester.pump();
      await tester.enterText(
          find.byKey(const Key('pay_recipient_phone_field')), '0249510123');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      expect(repository.lookups, ['0249510123']);
      expect(find.text('Taxi Driver'), findsOneWidget);
      expect(find.text('Ama Serwaa'), findsNothing);
    });

    testWidgets('an unknown number leaves the name field for the user to fill',
        (WidgetTester tester) async {
      final repository = ResolvingPaymentRepository();
      await tester.pumpWidget(createTestWidget(paymentRepository: repository));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('pay_recipient_phone_field')), '0241234567');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      expect(repository.lookups, ['0241234567']);
      // Nothing was auto-filled, and the user is told the account is unconfirmed
      expect(find.byKey(const Key('pay_recipient_name_verified_badge')),
          findsNothing);
      expect(
          find.text('We could not confirm this account. Check the details below.'),
          findsOneWidget);
    });
  });

  group('Recipient name confirmation', () {
    testWidgets('a name confirmed by the operator is shown verified and locked',
        (WidgetTester tester) async {
      final repository = VerifyingPaymentRepository();
      await tester.pumpWidget(createTestWidget(paymentRepository: repository));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('pay_recipient_phone_field')), '0249510123');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      // The confirmation is surfaced in the name box itself
      expect(find.text('Janet Adzo Ahialey'), findsOneWidget);
      expect(find.byKey(const Key('pay_recipient_name_verified_badge')),
          findsOneWidget);
      expect(find.text('Confirmed with MTN Mobile Money'), findsOneWidget);

      final field = tester.widget<TextFormField>(
        find.byKey(const Key('pay_recipient_name_field')),
      );
      expect(field.controller?.text, 'Janet Adzo Ahialey');

      // A confirmed recipient needs no tick from the user
      expect(find.byKey(const Key('pay_recipient_name_confirm_tick')),
          findsNothing);

      await tapChip(tester, 150);
      await tester.tap(find.byKey(const Key('pay_continue_to_review_button')));
      await tester.pumpAndSettle();

      expect(find.byType(PaymentReviewScreen), findsOneWidget);
      expect(find.byKey(const Key('review_recipient_name_verified')),
          findsOneWidget);
    });

    testWidgets('an unconfirmed recipient cannot be reviewed until ticked',
        (WidgetTester tester) async {
      final repository = ResolvingPaymentRepository();
      await tester.pumpWidget(createTestWidget(paymentRepository: repository));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('pay_recipient_phone_field')), '0241234567');
      await tester.enterText(
          find.byKey(const Key('pay_recipient_name_field')), 'Taxi Driver');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tapChip(tester, 150);

      // Trying to continue without confirming is refused, with a reason
      await tester.tap(find.byKey(const Key('pay_continue_to_review_button')));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentReviewScreen), findsNothing);
      expect(find.byKey(const Key('pay_recipient_name_confirm_required')),
          findsOneWidget);

      // Ticking the confirmation lets it through
      await confirmRecipient(tester);
      await tester.tap(find.byKey(const Key('pay_continue_to_review_button')));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentReviewScreen), findsOneWidget);
      expect(find.byKey(const Key('review_recipient_name_verified')),
          findsNothing);
    });

    testWidgets('changing the number drops a confirmation already given',
        (WidgetTester tester) async {
      final repository = ResolvingPaymentRepository();
      await tester.pumpWidget(createTestWidget(paymentRepository: repository));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('pay_recipient_phone_field')), '0241234567');
      await tester.enterText(
          find.byKey(const Key('pay_recipient_name_field')), 'Taxi Driver');
      await tester.pumpAndSettle();
      await tapChip(tester, 150);
      await confirmRecipient(tester);

      // A different number means a different recipient
      await tester.enterText(
          find.byKey(const Key('pay_recipient_phone_field')), '0247654321');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pay_continue_to_review_button')));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentReviewScreen), findsNothing);
      expect(find.byKey(const Key('pay_recipient_name_confirm_required')),
          findsOneWidget);
    });

    testWidgets('a confirmed name can be taken over with Change',
        (WidgetTester tester) async {
      final repository = VerifyingPaymentRepository();
      await tester.pumpWidget(createTestWidget(paymentRepository: repository));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('pay_recipient_phone_field')), '0249510123');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pay_recipient_name_verified_badge')),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('pay_recipient_name_change_button')));
      await tester.pumpAndSettle();

      // Editing over a confirmed name drops the verification
      expect(find.byKey(const Key('pay_recipient_name_verified_badge')),
          findsNothing);
      expect(find.byKey(const Key('pay_recipient_name_confirm_tick')),
          findsOneWidget);
    });

    testWidgets('bank accounts are confirmed by account number',
        (WidgetTester tester) async {
      final repository = VerifyingPaymentRepository();
      await tester.pumpWidget(createTestWidget(paymentRepository: repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pay_type_bank')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('pay_account_number_field')), '1234567890123');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(repository.lookups, ['1234567890123']);
      expect(find.text('Kwabena Owusu'), findsOneWidget);
      expect(find.byKey(const Key('pay_recipient_name_verified_badge')),
          findsOneWidget);
    });
  });

  group('Fee model', () {
    test('the local estimate matches the server 1% fee model', () {
      final estimate =
          PaymentEstimate.local(destinationAmount: 150.0, exchangeRate: 11.58);

      expect(estimate.sourceAmount, 12.95);
      expect(estimate.fee, 0.13);
      expect(estimate.total, 13.08);
    });

    test('the fee never rounds below the one cent minimum', () {
      final estimate =
          PaymentEstimate.local(destinationAmount: 1.0, exchangeRate: 11.58);

      expect(estimate.sourceAmount, 0.09);
      expect(estimate.fee, 0.01);
      expect(estimate.total, 0.10);
    });

    test('an empty amount produces an empty estimate', () {
      final estimate =
          PaymentEstimate.local(destinationAmount: 0.0, exchangeRate: 11.58);

      expect(estimate.isEmpty, isTrue);
      expect(estimate.total, 0.0);
    });
  });

  group('Quote requests', () {
    test('a request is only complete with real recipient and amount', () {
      const empty = PayFlowData();
      expect(PaymentQuoteRequest.fromPayData(empty).isComplete, isFalse);

      const noAmount = PayFlowData(recipientPhone: '0241234567');
      expect(PaymentQuoteRequest.fromPayData(noAmount).isComplete, isFalse);

      const complete = PayFlowData(
        recipientPhone: '0241234567',
        destinationAmount: 150.0,
      );
      expect(PaymentQuoteRequest.fromPayData(complete).isComplete, isTrue);
    });
  });
}
