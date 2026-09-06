import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vesspay/core/routing/app_router.dart';
import 'package:vesspay/core/routing/app_routes.dart';
import 'package:vesspay/features/wallet/models/topup_model.dart';
import 'package:vesspay/features/wallet/models/wallet_balance_model.dart';
import 'package:vesspay/features/wallet/models/wallet_currency_model.dart';
import 'package:vesspay/features/wallet/repositories/wallet_repository.dart';
import 'package:vesspay/features/wallet/screens/wallet_screen.dart';

class MockWalletRepository implements WalletRepository {
  List<WalletBalanceModel> balances;
  int getBalancesCallCount = 0;

  MockWalletRepository({List<WalletBalanceModel>? initialBalances})
      : balances = initialBalances ??
            [
              const WalletBalanceModel(currency: 'USD', balance: 500.00),
            ];

  @override
  Future<List<WalletBalanceModel>> getBalances() async {
    getBalancesCallCount++;
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
    return TopupResponseModel(
      fundingTransactionId: 'ftx-mock',
      checkoutId: 'chk-mock',
      status: 'PENDING',
      amount: amount,
      currency: currency,
    );
  }

  @override
  Future<TopupResponseModel> getTopupStatus(String fundingTransactionId) async {
    return TopupResponseModel(
      fundingTransactionId: fundingTransactionId,
      checkoutId: 'chk-mock',
      status: 'COMPLETED',
      amount: 100.0,
      currency: 'USD',
    );
  }

  @override
  Future<TopupResponseModel> confirmTopup(String fundingTransactionId) async {
    return TopupResponseModel(
      fundingTransactionId: fundingTransactionId,
      checkoutId: 'chk-mock',
      status: 'COMPLETED',
      amount: 100.0,
      currency: 'USD',
    );
  }
}

void main() {
  group('T3.6: Wallet Screen Tests', () {
    test('WalletBalanceModel parses JSON accurately', () {
      final model = WalletBalanceModel.fromJson({
        'currency': 'USD',
        'balance': 1250.75,
      });

      expect(model.currency, equals('USD'));
      expect(model.balance, equals(1250.75));
      expect(model.formattedBalance, equals('\$1250.75'));
    });

    testWidgets('WalletScreen renders USD balance, GHS equivalent, and action buttons', (tester) async {
      final mockRepo = MockWalletRepository(
        initialBalances: [
          const WalletBalanceModel(currency: 'USD', balance: 500.00),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            walletRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(
            home: WalletScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Travel Wallet'), findsOneWidget);
      expect(find.byKey(const Key('wallet_primary_balance_text')), findsOneWidget);
      final primaryBalanceWidget = tester.widget<Text>(find.byKey(const Key('wallet_primary_balance_text')));
      expect(primaryBalanceWidget.data, equals('\$500.00'));

      // GHS equivalent: 500 * 15.50 = 7750.00
      expect(find.byKey(const Key('wallet_ghs_equivalent_text')), findsOneWidget);
      final ghsWidget = tester.widget<Text>(find.byKey(const Key('wallet_ghs_equivalent_text')));
      expect(ghsWidget.data, equals('≈ GH₵ 7750.00'));

      expect(find.byKey(const Key('wallet_add_money_button')), findsOneWidget);
      expect(find.byKey(const Key('wallet_pay_button')), findsOneWidget);
      expect(find.text('Add Money'), findsOneWidget);
      expect(find.text('Pay Anyone'), findsOneWidget);

      expect(find.text('Active Corridors & Balances'), findsOneWidget);
      expect(find.text('USD Wallet'), findsOneWidget);
    });

    testWidgets('Pull-to-refresh triggers repository getBalances() refresh', (tester) async {
      final mockRepo = MockWalletRepository(
        initialBalances: [
          const WalletBalanceModel(currency: 'USD', balance: 100.00),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            walletRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(
            home: WalletScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(mockRepo.getBalancesCallCount, equals(1));
      final initialBalanceWidget = tester.widget<Text>(find.byKey(const Key('wallet_primary_balance_text')));
      expect(initialBalanceWidget.data, equals('\$100.00'));

      // Change repo balance before refresh
      mockRepo.balances = [
        const WalletBalanceModel(currency: 'USD', balance: 350.00),
      ];

      // Tap refresh action button
      final refreshBtn = find.byKey(const Key('wallet_refresh_button'));
      expect(refreshBtn, findsOneWidget);
      await tester.tap(refreshBtn);
      await tester.pumpAndSettle();

      expect(mockRepo.getBalancesCallCount, greaterThanOrEqualTo(2));
      final updatedBalanceWidget = tester.widget<Text>(find.byKey(const Key('wallet_primary_balance_text')));
      expect(updatedBalanceWidget.data, equals('\$350.00'));
    });

    testWidgets('Home screen Travel Wallet card navigates to WalletScreen', (tester) async {
      final mockRepo = MockWalletRepository(
        initialBalances: [
          const WalletBalanceModel(currency: 'USD', balance: 500.00),
        ],
      );
      final router = createAppRouter(initialLocation: AppRoutes.home);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            walletRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final walletCard = find.byKey(const Key('home_wallet_card'));
      expect(walletCard, findsOneWidget);
      expect(find.text('Travel Wallet'), findsOneWidget);

      await tester.tap(walletCard);
      await tester.pumpAndSettle();

      // Should now be on WalletScreen
      expect(find.byKey(const Key('wallet_primary_balance_text')), findsOneWidget);
      final balanceWidget = tester.widget<Text>(find.byKey(const Key('wallet_primary_balance_text')));
      expect(balanceWidget.data, equals('\$500.00'));
    });
  });
}
