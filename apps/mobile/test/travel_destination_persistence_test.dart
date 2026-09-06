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
import 'package:vesspay/features/home/screens/home_dashboard_screen.dart';
import 'package:vesspay/features/pay/models/payment_quote_model.dart';
import 'package:vesspay/features/pay/models/payment_response_model.dart';
import 'package:vesspay/features/pay/models/payout_institution_model.dart';
import 'package:vesspay/features/pay/models/recipient_resolution_model.dart';
import 'package:vesspay/features/pay/models/transaction_model.dart';
import 'package:vesspay/features/pay/repositories/payment_repository.dart';
import 'package:vesspay/features/travel/models/destination_model.dart';
import 'package:vesspay/features/travel/models/travel_profile_model.dart';
import 'package:vesspay/features/travel/providers/travel_providers.dart';
import 'support/fake_wallet_currency.dart';
import 'package:vesspay/features/travel/repositories/travel_repository.dart';
import 'package:vesspay/features/travel/screens/destination_selection_screen.dart';
import 'package:vesspay/features/wallet/models/topup_model.dart';
import 'package:vesspay/features/wallet/models/wallet_balance_model.dart';
import 'package:vesspay/features/wallet/models/wallet_currency_model.dart';
import 'package:vesspay/features/wallet/repositories/wallet_repository.dart';

class FakeAuthRepository implements AuthRepository {
  final TokenStorage tokenStorage;

  FakeAuthRepository({required this.tokenStorage});

  @override
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    await tokenStorage.saveToken('fake-jwt-token');
    return const UserModel(
      id: 'user-1',
      firstName: 'Alex',
      lastName: 'Johnson',
      email: 'alex@example.com',
      primaryCurrency: 'USD',
    );
  }

  @override
  Future<UserModel> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? country,
    String? nationality,
  }) async =>
      throw UnimplementedError();

  @override
  Future<UserModel> getProfile() async => const UserModel(
        id: 'user-1',
        firstName: 'Alex',
        lastName: 'Johnson',
        email: 'alex@example.com',
        primaryCurrency: 'USD',
      );

  @override
  Future<void> logout() async => tokenStorage.deleteToken();
}

/// Travel repository backed by a stored profile, the way the server behaves
/// across sessions: whatever the user last set is what comes back.
class StoredTravelRepository implements TravelRepository {
  TravelProfileModel? stored;
  int getCurrentProfileCalls = 0;

  StoredTravelRepository({this.stored});

  @override
  Future<List<DestinationModel>> getDestinations() async => const [
        DestinationModel(country: 'GH', name: 'Ghana', currency: 'GHS'),
        DestinationModel(country: 'NG', name: 'Nigeria', currency: 'NGN'),
      ];

  @override
  Future<TravelProfileModel?> getCurrentProfile() async {
    getCurrentProfileCalls++;
    return stored;
  }

  @override
  Future<TravelProfileModel> setCurrentProfile(String destinationCountry) async {
    stored = TravelProfileModel(
      id: 'profile-1',
      userId: 'user-1',
      destinationCountry: destinationCountry.toUpperCase(),
      destinationCurrency:
          destinationCountry.toUpperCase() == 'GH' ? 'GHS' : 'NGN',
      isActive: true,
    );
    return stored!;
  }
}

class FakeWalletRepository implements WalletRepository {
  /// Last funding transaction a WeWire sandbox deposit was requested for.
  String? simulatedDepositFor;


  @override
  Future<List<WalletBalanceModel>> getBalances() async => const [
        WalletBalanceModel(currency: 'USD', balance: 500.0),
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

class FakePaymentRepository implements PaymentRepository {
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
      throw UnimplementedError();

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
      throw UnimplementedError();

  @override
  Future<TransactionModel> getPaymentById(String id) async =>
      throw UnimplementedError();

  @override
  Future<List<TransactionModel>> getTransactions() async => [];
}

void main() {
  late InMemoryTokenStorage tokenStorage;
  late FakeAuthRepository authRepository;

  setUp(() {
    tokenStorage = InMemoryTokenStorage();
    authRepository = FakeAuthRepository(tokenStorage: tokenStorage);
  });

  void setMobileView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Future<void> pumpLogin(
    WidgetTester tester,
    StoredTravelRepository travelRepository,
  ) async {
    final router = createAppRouter(initialLocation: AppRoutes.login);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(tokenStorage),
          authRepositoryProvider.overrideWithValue(authRepository),
          travelRepositoryProvider.overrideWithValue(travelRepository),
          walletRepositoryProvider.overrideWithValue(FakeWalletRepository()),
          ...walletCurrencyOverrides(includeRepository: false),
          paymentRepositoryProvider.overrideWithValue(FakePaymentRepository()),
          routerProvider.overrideWithValue(router),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('login_email_field')), 'alex@example.com');
    await tester.enterText(
        find.byKey(const Key('login_password_field')), 'password123');

    final submitButton = find.byKey(const Key('login_submit_button'));
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();
  }

  group('Saved travel destination survives sign-out and sign-in', () {
    testWidgets('login with a saved destination goes straight to the dashboard',
        (WidgetTester tester) async {
      setMobileView(tester);
      final travelRepository = StoredTravelRepository(
        stored: TravelProfileModel(
          id: 'profile-1',
          userId: 'user-1',
          destinationCountry: 'GH',
          destinationCurrency: 'GHS',
          isActive: true,
        ),
      );

      await pumpLogin(tester, travelRepository);

      // The saved country is loaded instead of being asked for again
      expect(find.byType(HomeDashboardScreen), findsOneWidget);
      expect(find.byKey(const Key('travel_mode_setup_screen')), findsNothing);
      expect(travelRepository.getCurrentProfileCalls, greaterThan(0));
    });

    testWidgets('the loaded destination is the one the user last set',
        (WidgetTester tester) async {
      setMobileView(tester);
      // The user previously switched to Nigeria; that is what must come back
      final travelRepository = StoredTravelRepository();
      await travelRepository.setCurrentProfile('NG');

      await pumpLogin(tester, travelRepository);

      expect(find.byType(HomeDashboardScreen), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeDashboardScreen)),
      );
      expect(container.read(activeDestinationCountryProvider), 'NG');
      expect(container.read(activeDestinationCurrencyProvider), 'NGN');
      expect(container.read(travelingInTextProvider), contains('Nigeria'));
    });

    testWidgets('login without a saved destination still asks for one',
        (WidgetTester tester) async {
      setMobileView(tester);
      final travelRepository = StoredTravelRepository();

      await pumpLogin(tester, travelRepository);

      expect(find.byType(DestinationSelectionScreen), findsOneWidget);
      expect(find.byType(HomeDashboardScreen), findsNothing);
    });

    test('clear() drops the cached profile at sign-out', () async {
      final travelRepository = StoredTravelRepository(
        stored: TravelProfileModel(
          id: 'profile-1',
          userId: 'user-1',
          destinationCountry: 'GH',
          destinationCurrency: 'GHS',
          isActive: true,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          travelRepositoryProvider.overrideWithValue(travelRepository),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(currentTravelProfileProvider.notifier);
      expect((await notifier.refresh())?.destinationCountry, 'GH');

      notifier.clear();
      expect(container.read(currentTravelProfileProvider).valueOrNull, isNull);

      // Signing back in reloads it from the server, unchanged
      expect((await notifier.refresh())?.destinationCountry, 'GH');
    });
  });
}
