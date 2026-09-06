import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vesspay/features/wallet/models/deposit_account_model.dart';
import 'package:vesspay/core/routing/app_router.dart';
import 'package:vesspay/core/routing/app_routes.dart';
import 'package:vesspay/features/wallet/models/topup_model.dart';
import 'package:vesspay/features/wallet/models/wallet_balance_model.dart';
import 'package:vesspay/features/wallet/providers/wallet_providers.dart';
import 'package:vesspay/features/wallet/models/wallet_currency_model.dart';
import 'package:vesspay/features/kyc/models/kyc_model.dart';
import 'package:vesspay/features/kyc/repositories/kyc_repository.dart';
import 'package:vesspay/features/wallet/repositories/wallet_repository.dart';
import 'package:vesspay/features/wallet/screens/add_money_screen.dart';

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

class MockWalletRepositoryForAddMoney implements WalletRepository {
  /// Last funding transaction a WeWire sandbox deposit was requested for.
  String? simulatedDepositFor;


  List<WalletBalanceModel> balances = [
    const WalletBalanceModel(currency: 'USD', balance: 50.00),
  ];
  String currentStatus = 'PENDING';
  int initiateCalls = 0;
  int getStatusCalls = 0;

  @override
  Future<List<WalletBalanceModel>> getBalances() async {
    return balances;
  }

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
  }) async {
    initiateCalls++;
    return TopupResponseModel(
      fundingTransactionId: 'ftx-test-123456',
      checkoutId: 'chk-test-123456',
      checkoutUrl: 'https://stage-capi.wewireafrica.com/checkout/chk-test-123456',
      status: currentStatus,
      amount: amount,
      currency: currency,
      accountDetails: const TopupAccountDetails(
        bankName: 'WeWire Treasury Bank',
        accountNumber: '123456789',
      ),
    );
  }

  @override
  Future<TopupResponseModel> getTopupStatus(String fundingTransactionId) async {
    getStatusCalls++;
    return TopupResponseModel(
      fundingTransactionId: fundingTransactionId,
      checkoutId: 'chk-test-123456',
      status: currentStatus,
      amount: 100.0,
      currency: 'USD',
    );
  }

  @override
  Future<TopupResponseModel> confirmTopup(String fundingTransactionId) async {
    currentStatus = 'COMPLETED';
    return TopupResponseModel(
      fundingTransactionId: fundingTransactionId,
      checkoutId: 'chk-test-123456',
      status: 'COMPLETED',
      amount: 100.0,
      currency: 'USD',
    );
  }

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

  @override
  Future<void> simulateWeWireDeposit(String fundingTransactionId) async {
    simulatedDepositFor = fundingTransactionId;
  }
}

void main() {
  group('T3.7: Add Money Flow Tests', () {
    test('TopupResponseModel parses JSON accurately', () {
      final json = {
        'fundingTransactionId': 'ftx-888',
        'checkoutId': 'chk-888',
        'checkoutUrl': 'https://example.com/pay',
        'status': 'PENDING',
        'amount': 150.0,
        'currency': 'USD',
        'accountDetails': {
          'bankName': 'Evolve Bank',
          'accountNumber': '99887766',
        }
      };

      final model = TopupResponseModel.fromJson(json);
      expect(model.fundingTransactionId, equals('ftx-888'));
      expect(model.checkoutId, equals('chk-888'));
      expect(model.amount, equals(150.0));
      expect(model.isPending, isTrue);
      expect(model.isCompleted, isFalse);
      expect(model.accountDetails?.bankName, equals('Evolve Bank'));
    });

    testWidgets('AddMoneyScreen renders amount entry, quick chips, and GHS conversion',
        (tester) async {
      final mockRepo = MockWalletRepositoryForAddMoney();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            walletRepositoryProvider.overrideWithValue(mockRepo),
            kycRepositoryProvider.overrideWithValue(VerifiedKycRepository()),
          ],
          child: const MaterialApp(
            home: AddMoneyScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Add Money'), findsOneWidget);
      expect(find.byKey(const Key('add_money_amount_input')), findsOneWidget);
      expect(find.text('Amount to Add (USD)'), findsOneWidget);
      expect(find.text('Quick Amounts'), findsOneWidget);
      expect(find.text('+\$25'), findsOneWidget);
      expect(find.text('+\$50'), findsOneWidget);
      expect(find.text('+\$100'), findsOneWidget);
      expect(find.text('+\$250'), findsOneWidget);

      // Default amount is 100.00 -> 100 * 15.50 = 1550.00
      expect(find.byKey(const Key('add_money_ghs_equivalent_text')), findsOneWidget);
      expect(find.textContaining('GH₵ 1550.00'), findsOneWidget);

      // Tap +$250 chip
      await tester.tap(find.text('+\$250'));
      await tester.pumpAndSettle();

      // 250 * 15.50 = 3875.00
      expect(find.textContaining('GH₵ 3875.00'), findsOneWidget);
      expect(find.text('Continue to Funding (\$250.00)'), findsOneWidget);
    });

    testWidgets('Tapping Continue initiates topup and enters waitingConfirmation state',
        (tester) async {
      final mockRepo = MockWalletRepositoryForAddMoney();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            walletRepositoryProvider.overrideWithValue(mockRepo),
            kycRepositoryProvider.overrideWithValue(VerifiedKycRepository()),
          ],
          child: const MaterialApp(
            home: AddMoneyScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final submitBtn = find.byKey(const Key('add_money_submit_button'));
      expect(submitBtn, findsOneWidget);

      await tester.tap(submitBtn);
      await tester.pump(); // Start async call

      expect(mockRepo.initiateCalls, equals(1));
      await tester.pump(const Duration(milliseconds: 100));

      // Should now be in Waiting for Bank Confirmation state
      expect(find.byKey(const Key('waiting_confirmation_title')), findsOneWidget);
      expect(find.text('Waiting for Bank Confirmation'), findsOneWidget);
      expect(find.textContaining('PENDING (Awaiting settlement)'), findsOneWidget);
      expect(find.byKey(const Key('reopen_checkout_button')), findsOneWidget);

      // Clean up timer before exiting test
      final container = ProviderScope.containerOf(tester.element(find.byType(AddMoneyScreen)));
      container.read(topupControllerProvider.notifier).reset();
      await tester.pump();
    });

    testWidgets('Status transitioning to COMPLETED updates screen to Deposit Confirmed',
        (tester) async {
      final mockRepo = MockWalletRepositoryForAddMoney();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            walletRepositoryProvider.overrideWithValue(mockRepo),
            kycRepositoryProvider.overrideWithValue(VerifiedKycRepository()),
          ],
          child: const MaterialApp(
            home: AddMoneyScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initiate topup
      await tester.tap(find.byKey(const Key('add_money_submit_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('waiting_confirmation_title')), findsOneWidget);

      // Simulate webhook processing: backend marks status COMPLETED and updates balance
      mockRepo.currentStatus = 'COMPLETED';
      mockRepo.balances = [
        const WalletBalanceModel(currency: 'USD', balance: 150.00),
      ];

      // Advance clock by polling duration (2 seconds)
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // Success screen should be visible!
      expect(find.byKey(const Key('topup_success_title')), findsOneWidget);
      expect(find.text('Deposit Confirmed!'), findsOneWidget);
      expect(find.byKey(const Key('add_money_done_button')), findsOneWidget);
      expect(find.text('View Updated Wallet'), findsOneWidget);
    });

    testWidgets('Home screen Add Money button routes directly to AddMoneyScreen',
        (tester) async {
      final mockRepo = MockWalletRepositoryForAddMoney();
      final router = createAppRouter(initialLocation: AppRoutes.home);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            walletRepositoryProvider.overrideWithValue(mockRepo),
            kycRepositoryProvider.overrideWithValue(VerifiedKycRepository()),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final addMoneyBtn = find.byKey(const Key('wallet_add_money_button'));
      expect(addMoneyBtn, findsOneWidget);

      await tester.tap(addMoneyBtn);
      await tester.pumpAndSettle();

      // Now on AddMoneyScreen
      expect(find.byKey(const Key('add_money_amount_input')), findsOneWidget);
      expect(find.text('Add Money'), findsOneWidget);
    });
  });
}
