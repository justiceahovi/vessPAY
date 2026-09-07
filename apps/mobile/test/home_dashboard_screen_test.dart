import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesspay/features/wallet/models/deposit_account_model.dart';
import 'package:vesspay/core/providers.dart';
import 'package:vesspay/core/routing/app_router.dart';
import 'package:vesspay/core/routing/app_routes.dart';
import 'package:vesspay/core/storage/token_storage.dart';
import 'package:vesspay/core/theme/app_theme.dart';
import 'package:vesspay/features/auth/models/user_model.dart';
import 'package:vesspay/features/auth/repositories/auth_repository.dart';
import 'package:vesspay/features/travel/models/destination_model.dart';
import 'package:vesspay/features/travel/models/travel_profile_model.dart';
import 'package:vesspay/features/travel/repositories/travel_repository.dart';
import 'package:vesspay/features/wallet/models/topup_model.dart';
import 'package:vesspay/features/wallet/models/wallet_balance_model.dart';
import 'package:vesspay/features/wallet/models/wallet_currency_model.dart';
import 'package:vesspay/features/wallet/providers/wallet_providers.dart';
import 'package:vesspay/features/wallet/repositories/wallet_repository.dart';
import 'package:vesspay/features/pay/models/transaction_model.dart';

class TestMockAuthRepository implements AuthRepository {
  final UserModel? user;
  TestMockAuthRepository({this.user});

  @override
  Future<UserModel> getProfile() async {
    return user ??
        const UserModel(
          id: 'test-user-id',
          firstName: 'Justice',
          lastName: 'Ahovi',
          email: 'justice@example.com',
        );
  }

  @override
  Future<UserModel> login({required String email, required String password}) async =>
      throw UnimplementedError();

  @override
  Future<UserModel> register(
          {required String firstName,
          required String lastName,
          required String email,
          required String password,
          String? country,
          String? nationality}) async =>
      throw UnimplementedError();

  @override
  Future<UserModel> updateProfile({
    String? firstName,
    String? lastName,
    String? country,
    String? nationality,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> logout() async {}
}

class TestMockWalletRepository implements WalletRepository {
  /// Last funding transaction a WeWire sandbox deposit was requested for.
  String? simulatedDepositFor;


  final List<WalletBalanceModel> balances;
  final bool failOnBalances;
  TestMockWalletRepository({List<WalletBalanceModel>? balances, this.failOnBalances = false})
      : balances = balances ??
            [
              const WalletBalanceModel(currency: 'USD', balance: 500.00),
            ];

  @override
  Future<List<WalletBalanceModel>> getBalances() async {
    if (failOnBalances) throw Exception('balances unavailable');
    return balances;
  }

  @override
  Future<List<WalletCurrencyModel>> getSupportedCurrencies() async =>
      kDefaultWalletCurrencies;

  @override
  Future<String> setPrimaryCurrency(String currencyCode) async =>
      currencyCode.toUpperCase();

  @override
  Future<TopupResponseModel> initiateTopup(
          {required double amount, String currency = 'USD'}) async =>
      throw UnimplementedError();

  @override
  Future<TopupResponseModel?> getPendingTopup({String currency = 'USD'}) async =>
      null;

  @override
  Future<TopupResponseModel> getTopupStatus(String fundingTransactionId) async =>
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

class TestMockTravelRepository implements TravelRepository {
  @override
  Future<List<DestinationModel>> getDestinations() async => [
        const DestinationModel(country: 'GH', name: 'Ghana', currency: 'GHS'),
      ];

  @override
  Future<TravelProfileModel?> getCurrentProfile() async => TravelProfileModel(
        id: 'prof-1',
        userId: 'u-1',
        destinationCountry: 'GH',
        destinationCurrency: 'GHS',
        isActive: true,
      );

  @override
  Future<TravelProfileModel> setCurrentProfile(String destinationCountry) async =>
      throw UnimplementedError();
}

void main() {
  group('Home Dashboard Screen Banking UI Tests', () {
    late TokenStorage storage;
    late TestMockAuthRepository authRepo;
    late TestMockWalletRepository walletRepo;
    late TestMockTravelRepository travelRepo;

    setUp(() async {
      storage = InMemoryTokenStorage();
      await storage.saveToken('valid-token');
      authRepo = TestMockAuthRepository();
      walletRepo = TestMockWalletRepository();
      travelRepo = TestMockTravelRepository();
    });

    Widget createTestHomeWidget({UserModel? user}) {
      final activeAuthRepo =
          user != null ? TestMockAuthRepository(user: user) : authRepo;

      final router = createAppRouter(initialLocation: AppRoutes.home);

      return ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          authRepositoryProvider.overrideWithValue(activeAuthRepo),
          walletRepositoryProvider.overrideWithValue(walletRepo),
          travelRepositoryProvider.overrideWithValue(travelRepo),
          routerProvider.overrideWithValue(router),
          // The rate provider follows the active destination, so it refires
          // when the travel profile resolves. Pinned here so the widget test
          // never reaches the network.
          liveExchangeRateProvider.overrideWith((ref) async => 15.50),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      );
    }

    testWidgets('Renders header with user name, Savings Account card, and eye balance toggle',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestHomeWidget());
      await tester.pumpAndSettle();

      // Verify user greeting and VessPay Home
      expect(find.text('Justice Ahovi'), findsOneWidget);
      expect(find.text('VessPay Home'), findsOneWidget);

      // Verify Travel Wallet card
      expect(find.text('Travel Wallet'), findsOneWidget);

      // Balance should initially be visible by default
      expect(find.text('\$500.00'), findsOneWidget);
      expect(find.text('≈ GH₵ 7750.00'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

      // Tap eye icon to hide balance
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      // Balance is now hidden
      expect(find.text('••••••••'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      // Tap eye icon again to show balance
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pumpAndSettle();

      expect(find.text('\$500.00'), findsOneWidget);
      expect(find.text('≈ GH₵ 7750.00'), findsOneWidget);
    });

    testWidgets('Renders "Hello..." fallback when user has no name',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestHomeWidget(
        user: const UserModel(id: 'anon', firstName: '', lastName: '', email: ''),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Hello...'), findsOneWidget);
    });

    testWidgets('Renders hero card primary actions: Add Money and Pay',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestHomeWidget());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('wallet_add_money_button')), findsOneWidget);
      expect(find.byKey(const Key('wallet_pay_button')), findsOneWidget);
      expect(find.text('Add Money'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('wallet_pay_button')),
          matching: find.text('Pay'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Surfaces a balance left behind in a non-primary currency',
        (WidgetTester tester) async {
      // Primary wallet is USD; a EUR balance is left over from an earlier choice.
      walletRepo = TestMockWalletRepository(balances: [
        const WalletBalanceModel(currency: 'USD', balance: 500.0),
        const WalletBalanceModel(currency: 'EUR', balance: 42.0),
      ]);
      await tester.pumpWidget(createTestHomeWidget());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home_secondary_balances')), findsOneWidget);
      expect(find.textContaining('You also hold'), findsOneWidget);
      expect(find.textContaining('€42.00'), findsOneWidget);
    });

    testWidgets('Hides the secondary balance line when only the primary wallet is funded',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestHomeWidget());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home_secondary_balances')), findsNothing);
      expect(find.textContaining('You also hold'), findsNothing);
    });

    testWidgets('Shows an error card rather than an invented balance when the fetch fails',
        (WidgetTester tester) async {
      walletRepo = TestMockWalletRepository(failOnBalances: true);
      await tester.pumpWidget(createTestHomeWidget());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('wallet_balance_error_card')), findsOneWidget);
      expect(find.text('Balance unavailable'), findsOneWidget);
      expect(find.byKey(const Key('wallet_balance_retry_button')), findsOneWidget);

      // No fabricated figure anywhere on the card
      expect(find.textContaining('500'), findsNothing);
    });

    testWidgets('Renders YOUR ACTIVITY empty state when there are no transactions',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestHomeWidget());
      await tester.pumpAndSettle();

      expect(find.text('YOUR ACTIVITY'), findsOneWidget);
      expect(find.byKey(const Key('activity_empty_state')), findsOneWidget);
      expect(find.text('No activities yet'), findsOneWidget);
      expect(find.text('Purchased airtime'), findsNothing);
      expect(find.text('Load a Virtual Card'), findsNothing);
      expect(find.text('Transfer to Kwame Mensah'), findsNothing);
      expect(find.text('SUCCESS'), findsNothing);
    });

    testWidgets('Renders 3-item Floating Bottom Navigation Bar: Profile, Home, Transactions and header actions',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestHomeWidget());
      await tester.pumpAndSettle();

      // Verify 3 floating navigation items, Home in the centre
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
      expect(find.byKey(const Key('nav_item_profile')), findsOneWidget);
      expect(find.byKey(const Key('nav_item_home')), findsOneWidget);
      expect(find.byKey(const Key('nav_item_transactions')), findsOneWidget);

      // Tap Help icon in header opens help bottom sheet
      final helpBtn = find.byKey(const Key('header_help_button'));
      expect(helpBtn, findsOneWidget);
      await tester.tap(helpBtn);
      await tester.pumpAndSettle();
      expect(find.text('Help & Support'), findsOneWidget);
      expect(find.text('24/7 Traveler Support Chat'), findsOneWidget);

      // Close sheet
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Tap Notifications icon in header opens notifications bottom sheet
      final notifBtn = find.byKey(const Key('header_notifications_button'));
      expect(notifBtn, findsOneWidget);
      await tester.tap(notifBtn);
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Travel Corridor Active'), findsOneWidget);
      expect(find.text('Airtime Purchase Succeeded'), findsNothing);

      // Close sheet
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Tap profile avatar in header navigates to Profile & Account screen
      await tester.tap(find.byKey(const Key('home_avatar_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile_screen')), findsOneWidget);
      expect(find.text('Profile & Account'), findsOneWidget);
      expect(find.text('Travel Corridor Setup'), findsOneWidget);
    });

    testWidgets('Renders Change Primary currency button next to exchange reference and opens currency bottom sheet',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestHomeWidget());
      await tester.pumpAndSettle();

      // Verify exchange reference text is displayed
      expect(find.textContaining('Exchange reference:'), findsOneWidget);

      // Verify Change Primary currency icon button
      final changeBtn = find.byKey(const Key('change_primary_currency_button'));
      expect(changeBtn, findsOneWidget);
      expect(find.byIcon(Icons.currency_exchange_rounded), findsOneWidget);

      // Tap Change Primary currency button to open currency selection sheet
      await tester.tap(changeBtn);
      await tester.pumpAndSettle();

      // Verify currency selection bottom sheet is opened
      expect(find.byKey(const Key('wallet_currency_selection_screen')), findsOneWidget);
      expect(find.text('What currency do you want your wallet in?'), findsOneWidget);
      expect(find.byKey(const Key('wallet_currency_card_usd')), findsOneWidget);
      expect(find.byKey(const Key('wallet_currency_card_gbp')), findsOneWidget);
      expect(find.byKey(const Key('wallet_currency_card_eur')), findsOneWidget);
    });
  });
}
