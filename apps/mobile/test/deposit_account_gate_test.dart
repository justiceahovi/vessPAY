import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesspay/features/kyc/models/kyc_model.dart';
import 'package:vesspay/features/kyc/repositories/kyc_repository.dart';
import 'package:vesspay/features/wallet/models/deposit_account_model.dart';
import 'package:vesspay/features/wallet/repositories/wallet_repository.dart';
import 'package:vesspay/features/wallet/screens/add_money_screen.dart';

import 'support/fake_wallet_currency.dart';

/// Basic onboarding is approved, so KycGate lets these through and the
/// deposit-account gate is the thing under test.
class _VerifiedKycRepository implements KycRepository {
  @override
  Future<KycLinkModel> getKycLink() async =>
      KycLinkModel(url: 'https://in.sumsub.com/websdk/p/sbx', stage: 'ONBOARDING');

  @override
  Future<KycStatusModel> getKycStatus() async => KycStatusModel(
        onboardingStatus: 'APPROVED',
        enhancedKycStatus: 'TIER_2',
      );

  @override
  Future<KycStatusModel> submitDemoKyc() async => getKycStatus();
}

Widget _wrap(FakeCurrencyWalletRepository wallet) {
  return ProviderScope(
    overrides: [
      walletRepositoryProvider.overrideWithValue(wallet),
      kycRepositoryProvider.overrideWithValue(_VerifiedKycRepository()),
    ],
    child: const MaterialApp(home: AddMoneyScreen()),
  );
}

void main() {
  group('Deposit account gate', () {
    testWidgets('A ready account goes straight to the deposit form',
        (tester) async {
      await tester.pumpWidget(_wrap(FakeCurrencyWalletRepository()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_money_amount_input')), findsOneWidget);
      expect(find.byKey(const Key('deposit_account_source_of_funds')),
          findsNothing);
    });

    testWidgets('Outstanding EDD is explained instead of the deposit form',
        (tester) async {
      await tester.pumpWidget(_wrap(FakeCurrencyWalletRepository(
        depositAccount: const DepositAccountModel(
          state: DepositAccountState.kycRequired,
          currency: 'USD',
          reason: 'Enhanced verification must be completed first.',
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('deposit_account_kyc_required')),
          findsOneWidget);
      expect(find.byKey(const Key('deposit_account_start_kyc_button')),
          findsOneWidget);
      expect(find.byKey(const Key('add_money_amount_input')), findsNothing);
    });

    testWidgets('Source of funds is asked here, and the user picks it',
        (tester) async {
      final wallet = FakeCurrencyWalletRepository(
        depositAccount: const DepositAccountModel(
          state: DepositAccountState.sourceOfFundsRequired,
          currency: 'USD',
          sourceOfFundsOptions: [
            SourceOfFundsOption(value: 'salary', label: 'Salary or wages'),
            SourceOfFundsOption(value: 'savings', label: 'Personal savings'),
          ],
        ),
      );
      await tester.pumpWidget(_wrap(wallet));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('deposit_account_source_of_funds')),
          findsOneWidget);
      expect(find.text('Salary or wages'), findsOneWidget);
      expect(find.byKey(const Key('add_money_amount_input')), findsNothing);

      // Nothing is submitted until the user actually chooses.
      final submit = find.byKey(const Key('deposit_account_submit_source_button'));
      expect(tester.widget<ElevatedButton>(submit).onPressed, isNull);

      await tester.tap(find.text('Personal savings'));
      await tester.pump();
      expect(tester.widget<ElevatedButton>(submit).onPressed, isNotNull);

      await tester.tap(submit);
      await tester.pump();

      expect(wallet.provisionCalls, equals(1));
      expect(wallet.provisionedSourceOfFunds, equals('savings'));
    });

    testWidgets('A jurisdiction block is stated plainly', (tester) async {
      await tester.pumpWidget(_wrap(FakeCurrencyWalletRepository(
        depositAccount: const DepositAccountModel(
          state: DepositAccountState.unavailable,
          currency: 'EUR',
          reason: 'GHA is not supported by OpenPayd for EUR',
        ),
      )));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('deposit_account_unavailable')), findsOneWidget);
      expect(find.text('GHA is not supported by OpenPayd for EUR'),
          findsOneWidget);
    });
  });
}
