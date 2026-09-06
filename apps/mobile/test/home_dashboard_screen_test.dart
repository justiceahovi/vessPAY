import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:vesspay/features/wallet/repositories/wallet_repository.dart';

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
  Future<void> logout() async {}
}

class TestMockWalletRepository implements WalletRepository {
  final List<WalletBalanceModel> balances;
  TestMockWalletRepository({List<WalletBalanceModel>? balances})
      : balances = balances ??
            [
              const WalletBalanceModel(currency: 'USD', balance: 500.00),
            ];

  @override
  Future<List<WalletBalanceModel>> getBalances() async => balances;

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
  Future<TopupResponseModel> getTopupStatus(String fundingTransactionId) async =>
      throw UnimplementedError();

  @override
  Future<TopupResponseModel> confirmTopup(String fundingTransactionId) async =>
      throw UnimplementedError();
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

    testWidgets('Renders YOUR ACTIVITY feed with amounts and SUCCESS badges',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestHomeWidget());
      await tester.pumpAndSettle();

      expect(find.text('YOUR ACTIVITY'), findsOneWidget);
      expect(find.text('Purchased airtime'), findsOneWidget);
      expect(find.text('You have successfully purchased airtime of GHS 10.00'),
          findsOneWidget);
      expect(find.text('GHS 10.00'), findsOneWidget);
      expect(find.text('Load a Virtual Card'), findsOneWidget);
      expect(find.text('GHS 51.00'), findsOneWidget);
      expect(find.text('Transfer to Kwame Mensah'), findsOneWidget);
      expect(find.text('GHS 150.00'), findsOneWidget);
      expect(find.text('SUCCESS'), findsNWidgets(3));
    });

    testWidgets('Renders 3-item Floating Bottom Navigation Bar: Home, Pay, Cards and header actions',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestHomeWidget());
      await tester.pumpAndSettle();

      // Verify 3 floating navigation items
      expect(find.text('Home'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('nav_item_pay')),
          matching: find.text('Pay'),
        ),
        findsOneWidget,
      );
      expect(find.text('Cards'), findsOneWidget);
      expect(find.byKey(const Key('nav_item_home')), findsOneWidget);
      expect(find.byKey(const Key('nav_item_pay')), findsOneWidget);
      expect(find.byKey(const Key('nav_item_cards')), findsOneWidget);

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
      expect(find.text('Airtime Purchase Succeeded'), findsOneWidget);

      // Close sheet
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Tap profile avatar in header opens more options bottom sheet
      await tester.tap(find.byIcon(Icons.person_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.text('More Options'), findsOneWidget);
      expect(find.text('Travel Corridor Setup'), findsOneWidget);
    });
  });
}
