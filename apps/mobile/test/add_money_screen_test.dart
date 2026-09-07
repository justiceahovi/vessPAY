import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vesspay/features/wallet/models/deposit_account_model.dart';
import 'package:vesspay/features/wallet/models/crypto_deposit_model.dart';
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
import 'package:vesspay/features/pay/models/transaction_model.dart';

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
  @override
  Future<List<CryptoChainModel>> getCryptoChains() async => const [];

  @override
  Future<CryptoAddressModel> getCryptoAddress(String chain) async =>
      CryptoAddressModel.unavailable(chain, 'not stubbed');

  @override
  Future<void> cancelTopup(String fundingTransactionId) async {
    cancelledTopupIds.add(fundingTransactionId);
  }

  final List<String> cancelledTopupIds = [];

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

  /// A deposit the backend still has waiting on the rails, for the resume
  /// path. Null means the user has nothing in flight.
  TopupResponseModel? pendingTopup;
  int pendingTopupCalls = 0;

  @override
  Future<TopupResponseModel?> getPendingTopup({String currency = 'USD'}) async {
    pendingTopupCalls++;
    return pendingTopup;
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

  /// Deposits this fake reports back into the activity feed.
  List<TransactionModel> deposits = [];

  @override
  Future<List<TransactionModel>> getDeposits() async => deposits;

  @override
  Future<TransactionModel> getDepositById(String id) async =>
      deposits.firstWhere((d) => d.id == id);
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
      expect(find.textContaining('GH₵ 1,550.00'), findsOneWidget);

      // Tap +$250 chip
      await tester.tap(find.text('+\$250'));
      await tester.pumpAndSettle();

      // 250 * 15.50 = 3875.00
      expect(find.textContaining('GH₵ 3,875.00'), findsOneWidget);
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

    testWidgets('A deposit left pending is resumed when the screen reopens',
        (tester) async {
      final mockRepo = MockWalletRepositoryForAddMoney();
      // The user started this deposit before leaving the screen. The top-up
      // controller is autoDispose, so by now only the backend knows about it.
      mockRepo.pendingTopup = const TopupResponseModel(
        fundingTransactionId: 'ftx-resumed-1',
        checkoutId: 'chk-resumed-1',
        status: 'PENDING',
        amount: 250.0,
        currency: 'USD',
        accountSource: 'wewire',
        accountDetails: TopupAccountDetails(
          bankName: 'WeWire Treasury Bank',
          accountNumber: '123456789',
        ),
      );

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

      // Not pumpAndSettle: once restored, the waiting step spins a progress
      // indicator that never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Opens straight on the waiting step, showing the deposit that is
      // already expected rather than an empty amount field.
      expect(mockRepo.pendingTopupCalls, equals(1));
      expect(find.byKey(const Key('waiting_confirmation_title')), findsOneWidget);
      expect(find.textContaining('250.00'), findsWidgets);
      expect(find.byKey(const Key('reopen_checkout_button')), findsOneWidget);
      // Nothing was initiated: resuming must not open a second deposit.
      expect(mockRepo.initiateCalls, equals(0));

      final container =
          ProviderScope.containerOf(tester.element(find.byType(AddMoneyScreen)));
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

    testWidgets('Home screen Add Money button opens the method choice, then the bank flow',
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

      // The rails are asked about before any amount is: crypto has no amount
      // to declare, and is not gated on a fiat deposit account.
      expect(find.byKey(const Key('deposit_method_screen')), findsOneWidget);
      expect(find.byKey(const Key('deposit_method_bank')), findsOneWidget);
      expect(find.byKey(const Key('deposit_method_crypto')), findsOneWidget);

      await tester.tap(find.byKey(const Key('deposit_method_bank')));
      await tester.pumpAndSettle();

      // Now on AddMoneyScreen
      expect(find.byKey(const Key('add_money_amount_input')), findsOneWidget);
      expect(find.text('Add Money'), findsWidgets);
    });

    testWidgets('A pending deposit can be cancelled to start a different one',
        (tester) async {
      // Without this the restored deposit is a trap: it reopens on every visit,
      // for an amount the user may no longer want, with no way past it.
      final mockRepo = MockWalletRepositoryForAddMoney();
      mockRepo.pendingTopup = const TopupResponseModel(
        fundingTransactionId: 'ftx-cancel-1',
        checkoutId: 'chk-cancel-1',
        status: 'PENDING',
        amount: 100.0,
        currency: 'USD',
        accountSource: 'wewire',
        accountDetails: TopupAccountDetails(
          bankName: 'WeWire Treasury Bank',
          accountNumber: '123456789',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            walletRepositoryProvider.overrideWithValue(mockRepo),
            kycRepositoryProvider.overrideWithValue(VerifiedKycRepository()),
          ],
          child: const MaterialApp(home: AddMoneyScreen()),
        ),
      );

      // The waiting step spins, so settle by pumping rather than pumpAndSettle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      final cancelButton = find.byKey(const Key('add_money_cancel_deposit_button'));
      expect(cancelButton, findsOneWidget);

      await tester.ensureVisible(cancelButton);
      await tester.tap(cancelButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Confirmed first: money already sent still arrives, and the user has to
      // be told that before deciding.
      expect(find.byKey(const Key('cancel_deposit_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancel_deposit_confirm_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The server was told, so reopening will not restore it again.
      expect(mockRepo.cancelledTopupIds, contains('ftx-cancel-1'));

      // And the user is back on amount entry, free to choose a new figure.
      expect(find.byKey(const Key('add_money_amount_input')), findsOneWidget);
    });
  });
}
