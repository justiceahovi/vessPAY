import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vesspay/core/routing/app_routes.dart';
import 'package:vesspay/core/theme/app_theme.dart';
import 'package:vesspay/features/kyc/models/kyc_model.dart';
import 'package:vesspay/features/kyc/repositories/kyc_repository.dart';
import 'package:vesspay/features/wallet/screens/deposit_method_screen.dart';
import 'support/fake_wallet_currency.dart';

/// The screen is behind KycGate, which spins until a status resolves.
class VerifiedKycRepository implements KycRepository {
  @override
  Future<KycLinkModel> getKycLink() async =>
      KycLinkModel(url: 'https://verify.wewire.com/session', stage: 'ONBOARDING');

  @override
  Future<KycStatusModel> getKycStatus() async =>
      KycStatusModel(onboardingStatus: 'APPROVED', enhancedKycStatus: 'TIER_2');

  @override
  Future<KycStatusModel> submitDemoKyc() async => getKycStatus();
}

/// Records where a tap sent the user, without building the destination screens.
GoRouter buildRouter(List<String> visited) {
  return GoRouter(
    initialLocation: AppRoutes.depositMethod,
    routes: [
      GoRoute(
        path: AppRoutes.depositMethod,
        builder: (_, __) => const DepositMethodScreen(),
      ),
      GoRoute(
        path: AppRoutes.addMoney,
        builder: (_, __) {
          visited.add('bank');
          return const Scaffold(body: Text('bank flow'));
        },
      ),
      GoRoute(
        path: AppRoutes.cryptoDeposit,
        builder: (_, __) {
          visited.add('crypto');
          return const Scaffold(body: Text('crypto flow'));
        },
      ),
    ],
  );
}

void main() {
  group('Deposit method choice', () {
    Future<List<String>> pumpAndTap(WidgetTester tester, Key method) async {
      final visited = <String>[];
      final router = buildRouter(visited);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...walletCurrencyOverrides(),
            kycRepositoryProvider.overrideWithValue(VerifiedKycRepository()),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(method));
      await tester.pumpAndSettle();
      return visited;
    }

    testWidgets('offers both rails before asking for an amount',
        (tester) async {
      final visited = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...walletCurrencyOverrides(),
            kycRepositoryProvider.overrideWithValue(VerifiedKycRepository()),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: buildRouter(visited),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('deposit_method_screen')), findsOneWidget);
      expect(find.text('How would you like to add money?'), findsOneWidget);
      expect(find.byKey(const Key('deposit_method_bank')), findsOneWidget);
      expect(find.byKey(const Key('deposit_method_crypto')), findsOneWidget);

      // No amount is asked for here: the two rails disagree about whether an
      // amount even exists up front.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('bank transfer opens the amount-first flow', (tester) async {
      final visited = await pumpAndTap(tester, const Key('deposit_method_bank'));
      expect(visited, contains('bank'));
    });

    testWidgets('crypto opens the address-first flow', (tester) async {
      final visited = await pumpAndTap(tester, const Key('deposit_method_crypto'));
      expect(visited, contains('crypto'));
    });
  });
}
