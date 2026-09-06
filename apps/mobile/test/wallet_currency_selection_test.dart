import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesspay/core/providers.dart';
import 'package:vesspay/core/routing/app_router.dart';
import 'package:vesspay/core/routing/app_routes.dart';
import 'package:vesspay/core/storage/currency_preference_storage.dart';
import 'package:vesspay/features/auth/models/user_model.dart';
import 'package:vesspay/features/auth/repositories/auth_repository.dart';
import 'package:vesspay/features/wallet/models/topup_model.dart';
import 'package:vesspay/features/wallet/models/wallet_balance_model.dart';
import 'package:vesspay/features/wallet/models/wallet_currency_model.dart';
import 'package:vesspay/features/wallet/providers/currency_providers.dart';
import 'package:vesspay/features/wallet/providers/wallet_providers.dart';
import 'package:vesspay/features/wallet/repositories/wallet_repository.dart';

class FakeWalletRepository implements WalletRepository {
  String? savedCurrency;
  int setCurrencyCalls = 0;
  bool failOnSet = false;

  List<WalletBalanceModel> balances = const [
    WalletBalanceModel(currency: 'USD', balance: 0.0),
  ];

  @override
  Future<List<WalletBalanceModel>> getBalances() async => balances;

  @override
  Future<List<WalletCurrencyModel>> getSupportedCurrencies() async =>
      kDefaultWalletCurrencies;

  @override
  Future<String> setPrimaryCurrency(String currencyCode) async {
    setCurrencyCalls++;
    if (failOnSet) {
      throw Exception('network down');
    }
    savedCurrency = currencyCode.toUpperCase();
    return savedCurrency!;
  }

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
}

class FakeAuthRepository implements AuthRepository {
  /// What the server says this account already chose; null means "never chose".
  String? profileCurrency;

  FakeAuthRepository({this.profileCurrency});

  @override
  Future<UserModel> getProfile() async => UserModel(
        id: 'user-1',
        firstName: 'Alex',
        lastName: 'Johnson',
        email: 'alex@example.com',
        primaryCurrency: profileCurrency,
      );

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
  Future<UserModel> login({
    required String email,
    required String password,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> logout() async {}
}

ProviderContainer _container({
  required FakeWalletRepository wallet,
  required FakeAuthRepository auth,
  required CurrencyPreferenceStorage storage,
}) {
  return ProviderContainer(
    overrides: [
      walletRepositoryProvider.overrideWithValue(wallet),
      authRepositoryProvider.overrideWithValue(auth),
      currencyPreferenceStorageProvider.overrideWithValue(storage),
    ],
  );
}

Widget _wrap(ProviderContainer container) {
  // Drive the real router so confirming the choice can navigate onward,
  // exactly as it does in the first-run flow.
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig:
          createAppRouter(initialLocation: AppRoutes.walletCurrencySetup),
    ),
  );
}

void main() {
  group('Wallet currency selection', () {
    testWidgets('offers every supported currency with USD preselected',
        (tester) async {
      final container = _container(
        wallet: FakeWalletRepository(),
        auth: FakeAuthRepository(),
        storage: InMemoryCurrencyPreferenceStorage(),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('wallet_currency_selection_screen')),
          findsOneWidget);
      expect(find.byKey(const Key('wallet_currency_card_usd')), findsOneWidget);
      expect(find.byKey(const Key('wallet_currency_card_gbp')), findsOneWidget);
      expect(find.byKey(const Key('wallet_currency_card_eur')), findsOneWidget);
      expect(find.text('Open my USD wallet'), findsOneWidget);
    });

    testWidgets('confirming a choice persists it to the backend and locally',
        (tester) async {
      final wallet = FakeWalletRepository();
      final storage = InMemoryCurrencyPreferenceStorage();
      final container = _container(
        wallet: wallet,
        auth: FakeAuthRepository(),
        storage: storage,
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('wallet_currency_card_gbp')));
      await tester.pump();
      expect(find.text('Open my GBP wallet'), findsOneWidget);

      await tester.tap(find.byKey(const Key('wallet_currency_confirm_button')));
      await tester.pumpAndSettle();

      expect(wallet.savedCurrency, 'GBP');
      expect(await storage.getCurrency(), 'GBP');
      expect(container.read(activeWalletCurrencyCodeProvider), 'GBP');
    });

    testWidgets('keeps the choice on this device when the server is down',
        (tester) async {
      final wallet = FakeWalletRepository()..failOnSet = true;
      final storage = InMemoryCurrencyPreferenceStorage();
      final container = _container(
        wallet: wallet,
        auth: FakeAuthRepository(),
        storage: storage,
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('wallet_currency_card_eur')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('wallet_currency_confirm_button')));
      await tester.pumpAndSettle();

      expect(wallet.savedCurrency, isNull);
      expect(await storage.getCurrency(), 'EUR');
      expect(container.read(activeWalletCurrencyCodeProvider), 'EUR');
    });
  });

  group('Wallet currency persistence', () {
    test('a returning user gets the currency stored on their account', () async {
      final storage = InMemoryCurrencyPreferenceStorage();
      final container = _container(
        wallet: FakeWalletRepository(),
        auth: FakeAuthRepository(profileCurrency: 'GBP'),
        storage: storage,
      );
      addTearDown(container.dispose);

      final currency = await container.read(walletCurrencyProvider.future);

      expect(currency, 'GBP');
      expect(await storage.getCurrency(), 'GBP',
          reason: 'server choice should refresh the local cache');
      expect(container.read(needsWalletCurrencyChoiceProvider), isFalse);
    });

    test('an account that never chose is flagged as needing a choice',
        () async {
      final container = _container(
        wallet: FakeWalletRepository(),
        auth: FakeAuthRepository(profileCurrency: null),
        storage: InMemoryCurrencyPreferenceStorage(),
      );
      addTearDown(container.dispose);

      final currency = await container.read(walletCurrencyProvider.future);

      expect(currency, isNull);
      expect(container.read(needsWalletCurrencyChoiceProvider), isTrue);
      expect(container.read(activeWalletCurrencyCodeProvider),
          kDefaultWalletCurrency);
    });

    test('launch renders from the local cache without waiting on the server',
        () async {
      final storage = InMemoryCurrencyPreferenceStorage(initialCurrency: 'EUR');
      final container = _container(
        wallet: FakeWalletRepository(),
        auth: FakeAuthRepository(profileCurrency: 'EUR'),
        storage: storage,
      );
      addTearDown(container.dispose);

      expect(await container.read(walletCurrencyProvider.future), 'EUR');
    });

    test('signing in reconciles a stale local cache with the server', () async {
      final storage = InMemoryCurrencyPreferenceStorage(initialCurrency: 'USD');
      final container = _container(
        wallet: FakeWalletRepository(),
        auth: FakeAuthRepository(profileCurrency: 'EUR'),
        storage: storage,
      );
      addTearDown(container.dispose);

      expect(await container.read(walletCurrencyProvider.future), 'USD');

      final refreshed =
          await container.read(walletCurrencyProvider.notifier).refresh();

      expect(refreshed, 'EUR');
      expect(await storage.getCurrency(), 'EUR');
    });

    test('formatting follows the chosen currency', () {
      expect(resolveWalletCurrency('GBP').format(12.5), '£12.50');
      expect(resolveWalletCurrency('EUR').format(12.5), '€12.50');
      expect(resolveWalletCurrency('USD').format(12.5), r'$12.50');
    });
  });

  group('Balance shown after a currency switch', () {
    test('shows zero in the newly chosen currency, not the old wallet balance',
        () async {
      final wallet = FakeWalletRepository()
        ..balances = const [WalletBalanceModel(currency: 'USD', balance: 500.0)];
      final container = _container(
        wallet: wallet,
        auth: FakeAuthRepository(profileCurrency: 'USD'),
        storage: InMemoryCurrencyPreferenceStorage(initialCurrency: 'USD'),
      );
      addTearDown(container.dispose);

      await container.read(walletBalancesProvider.future);
      expect(
        container.read(primaryWalletBalanceProvider).valueOrNull?.balance,
        equals(500.0),
      );

      // Switching to a currency the user holds nothing in: the backend creates
      // an empty EUR wallet and the USD balance is left untouched.
      await container.read(walletCurrencyProvider.notifier).select('EUR');
      await container.read(walletBalancesProvider.future);

      final shown = container.read(primaryWalletBalanceProvider).valueOrNull;
      expect(shown?.currency, equals('EUR'));
      expect(shown?.balance, equals(0.0));
    });

    test('a switch that fails server-side still never mislabels the old balance',
        () async {
      final wallet = FakeWalletRepository()
        ..balances = const [WalletBalanceModel(currency: 'USD', balance: 500.0)]
        ..failOnSet = true;
      final container = _container(
        wallet: wallet,
        auth: FakeAuthRepository(profileCurrency: 'USD'),
        storage: InMemoryCurrencyPreferenceStorage(initialCurrency: 'USD'),
      );
      addTearDown(container.dispose);

      await container.read(walletBalancesProvider.future);

      await expectLater(
        container.read(walletCurrencyProvider.notifier).select('EUR'),
        throwsA(isA<Exception>()),
      );

      // The choice is kept locally so the app stays usable offline, but the
      // USD balance must not be re-rendered under the EUR symbol.
      expect(container.read(activeWalletCurrencyCodeProvider), equals('EUR'));
      final shown = container.read(primaryWalletBalanceProvider).valueOrNull;
      expect(shown?.currency, equals('EUR'));
      expect(shown?.balance, equals(0.0));
    });
  });
}
