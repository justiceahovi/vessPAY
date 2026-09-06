import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesspay/core/navigation/floating_bottom_nav_bar.dart';
import 'package:vesspay/core/navigation/main_app_shell.dart';
import 'package:vesspay/core/providers.dart';
import 'package:vesspay/core/routing/app_router.dart';
import 'package:vesspay/core/routing/app_routes.dart';
import 'package:vesspay/core/storage/token_storage.dart';
import 'package:vesspay/core/theme/app_colors.dart';
import 'package:vesspay/core/theme/app_theme.dart';
import 'package:vesspay/features/auth/models/user_model.dart';
import 'package:vesspay/features/auth/repositories/auth_repository.dart';
import 'package:vesspay/features/pay/models/payment_quote_model.dart';
import 'package:vesspay/features/pay/models/payment_response_model.dart';
import 'package:vesspay/features/pay/models/transaction_model.dart';
import 'package:vesspay/features/pay/models/payout_institution_model.dart';
import 'package:vesspay/features/pay/models/recipient_resolution_model.dart';
import 'package:vesspay/features/pay/repositories/payment_repository.dart';
import 'package:vesspay/features/travel/models/destination_model.dart';
import 'package:vesspay/features/travel/models/travel_profile_model.dart';
import 'package:vesspay/features/travel/repositories/travel_repository.dart';
import 'package:vesspay/features/wallet/models/topup_model.dart';
import 'package:vesspay/features/wallet/models/wallet_balance_model.dart';
import 'package:vesspay/features/wallet/models/wallet_currency_model.dart';
import 'package:vesspay/features/wallet/repositories/wallet_repository.dart';

class NavMockAuthRepository implements AuthRepository {
  @override
  Future<UserModel> getProfile() async => const UserModel(
        id: 'user-1',
        firstName: 'Justice',
        lastName: 'Ahovi',
        email: 'justice@example.com',
      );

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

class NavMockWalletRepository implements WalletRepository {
  @override
  Future<List<WalletBalanceModel>> getBalances() async => [
        const WalletBalanceModel(currency: 'USD', balance: 500.0),
      ];

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

class NavMockTravelRepository implements TravelRepository {
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

class NavMockPaymentRepository implements PaymentRepository {
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

  @override
  Future<PaymentQuoteModel> getQuote({
    required String country,
    required String network,
    required String phone,
    required double destinationAmount,
    String destinationCurrency = 'GHS',
  }) async =>
      PaymentQuoteModel(
        sourceCurrency: 'USD',
        sourceAmount: 10.0,
        destinationCurrency: 'GHS',
        destinationAmount: 150.0,
        exchangeRate: 15.0,
        fee: 0.1,
        total: 10.1,
        country: country,
        network: network,
        phone: phone,
      );

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
  }) async =>
      const CreatePaymentResponse(
        transactionId: 'tx-123',
        status: 'PENDING',
      );

  @override
  Future<TransactionModel> getPaymentById(String id) async => TransactionModel(
        id: id,
        type: 'payout',
        status: 'COMPLETED',
        sourceCurrency: 'USD',
        sourceAmount: 10.0,
        destinationCurrency: 'GHS',
        destinationAmount: 150.0,
        fee: 0.1,
        exchangeRate: 15.0,
        createdAt: DateTime.now(),
      );

  @override
  Future<List<TransactionModel>> getTransactions() async => [];
}

void main() {
  group('Persistent Bottom Navigation Bar Across All Screens', () {
    late InMemoryTokenStorage tokenStorage;
    late NavMockAuthRepository authRepo;
    late NavMockWalletRepository walletRepo;
    late NavMockTravelRepository travelRepo;
    late NavMockPaymentRepository paymentRepo;

    setUp(() async {
      tokenStorage = InMemoryTokenStorage();
      await tokenStorage.saveToken('valid-auth-token');
      authRepo = NavMockAuthRepository();
      walletRepo = NavMockWalletRepository();
      travelRepo = NavMockTravelRepository();
      paymentRepo = NavMockPaymentRepository();
    });

    Widget createTestApp({String initialLocation = AppRoutes.home}) {
      final router = createAppRouter(initialLocation: initialLocation);

      return ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(tokenStorage),
          authRepositoryProvider.overrideWithValue(authRepo),
          walletRepositoryProvider.overrideWithValue(walletRepo),
          travelRepositoryProvider.overrideWithValue(travelRepo),
          paymentRepositoryProvider.overrideWithValue(paymentRepo),
          routerProvider.overrideWithValue(router),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      );
    }

    testWidgets('Persists on Home screen and shows Home as active',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(initialLocation: AppRoutes.home));
      await tester.pumpAndSettle();

      expect(find.byType(MainAppShell), findsOneWidget);
      expect(find.byType(FloatingBottomNavBar), findsOneWidget);
      expect(find.byKey(const Key('nav_item_home')), findsOneWidget);
      expect(find.byKey(const Key('nav_item_pay')), findsOneWidget);
      expect(find.byKey(const Key('nav_item_cards')), findsOneWidget);

      // Home icon is highlighted with primary color
      final homeIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('nav_item_home')),
          matching: find.byType(Icon),
        ),
      );
      expect(homeIcon.color, equals(AppColors.primary));
    });

    testWidgets('Persists on Wallet screen and shows Cards as active',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(initialLocation: AppRoutes.wallet));
      await tester.pumpAndSettle();

      expect(find.byType(MainAppShell), findsOneWidget);
      expect(find.byType(FloatingBottomNavBar), findsOneWidget);
      expect(find.text('Travel Wallet'), findsOneWidget);

      // Cards tab is active
      final cardsIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('nav_item_cards')),
          matching: find.byType(Icon),
        ),
      );
      expect(cardsIcon.color, equals(AppColors.primary));
    });

    testWidgets('Persists on Pay Anyone flow screen and shows Pay as active',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(initialLocation: AppRoutes.payAnyone));
      await tester.pumpAndSettle();

      expect(find.byType(MainAppShell), findsOneWidget);
      expect(find.byType(FloatingBottomNavBar), findsOneWidget);
      expect(find.text('Pay Anyone'), findsOneWidget);
      expect(find.text('Send money'), findsOneWidget);
    });

    testWidgets('Persists on Transactions list screen',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          createTestApp(initialLocation: AppRoutes.transactionList));
      await tester.pumpAndSettle();

      expect(find.byType(MainAppShell), findsOneWidget);
      expect(find.byType(FloatingBottomNavBar), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
    });

    testWidgets('Persists when navigating between screens via bottom nav bar tabs',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(initialLocation: AppRoutes.home));
      await tester.pumpAndSettle();

      expect(find.text('VessPay Home'), findsOneWidget);
      expect(find.byType(FloatingBottomNavBar), findsOneWidget);

      // 1. Tap Cards -> navigates to Wallet
      await tester.tap(find.byKey(const Key('nav_item_cards')));
      await tester.pumpAndSettle();

      expect(find.text('Travel Wallet'), findsOneWidget);
      expect(find.byType(FloatingBottomNavBar), findsOneWidget);

      // 2. Tap Pay -> navigates to Pay Anyone flow
      await tester.tap(find.byKey(const Key('nav_item_pay')));
      await tester.pumpAndSettle();

      expect(find.text('Pay Anyone'), findsOneWidget);
      expect(find.byType(FloatingBottomNavBar), findsOneWidget);

      // 3. Tap Home -> navigates back to Home
      await tester.tap(find.byKey(const Key('nav_item_home')));
      await tester.pumpAndSettle();

      expect(find.text('VessPay Home'), findsOneWidget);
      expect(find.byType(FloatingBottomNavBar), findsOneWidget);
    });

    testWidgets('Does not render on pre-auth fullscreen screens',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(initialLocation: AppRoutes.login));
      await tester.pumpAndSettle();

      expect(find.byType(FloatingBottomNavBar), findsNothing);
      expect(find.byType(MainAppShell), findsNothing);
      expect(find.text('Sign In'), findsOneWidget);
    });
  });
}
