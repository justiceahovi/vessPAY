import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vesspay/core/theme/app_theme.dart';
import 'package:vesspay/features/wallet/models/crypto_deposit_model.dart';
import 'package:vesspay/features/wallet/providers/wallet_providers.dart';
import 'package:vesspay/features/wallet/screens/crypto_deposit_screen.dart';

const _baseChain = CryptoChainModel(
  chain: 'BASE',
  network: 'TESTNET',
  assets: ['USDC', 'GHST'],
  displayName: 'Base',
);
const _tronChain = CryptoChainModel(
  chain: 'TRON',
  network: 'TESTNET',
  assets: ['USDC'],
  displayName: 'Tron',
);
const _mainnetChain = CryptoChainModel(
  chain: 'BASE',
  network: 'MAINNET',
  assets: ['USDC'],
  displayName: 'Base',
);

Widget wrap({
  required List<CryptoChainModel> chains,
  required CryptoAddressModel address,
}) {
  return ProviderScope(
    overrides: [
      cryptoChainsProvider.overrideWith((ref) async => chains),
      cryptoAddressProvider.overrideWith((ref, chain) async => address),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const CryptoDepositScreen(),
    ),
  );
}

void main() {
  group('Crypto deposit screen', () {
    testWidgets('lists every network and what each one accepts',
        (tester) async {
      await tester.pumpWidget(wrap(
        chains: const [_baseChain, _tronChain],
        address: const CryptoAddressModel(
          state: CryptoAddressState.ready,
          chain: 'BASE',
          network: 'TESTNET',
          address: '0x14030e34D166D37203D561A6ECea0c8C609b7909',
          supportedAssets: ['USDC', 'GHST'],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('crypto_chain_base')), findsOneWidget);
      expect(find.byKey(const Key('crypto_chain_tron')), findsOneWidget);
      // One address serves every asset on its chain, so both are named.
      expect(find.text('Accepts USDC or GHST'), findsOneWidget);
      expect(find.text('Accepts USDC'), findsOneWidget);
    });

    testWidgets('shows the address with its network, and copies it',
        (tester) async {
      const addr = '0x14030e34D166D37203D561A6ECea0c8C609b7909';
      final copied = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') copied.add(call);
          return null;
        },
      );

      await tester.pumpWidget(wrap(
        chains: const [_baseChain],
        address: const CryptoAddressModel(
          state: CryptoAddressState.ready,
          chain: 'BASE',
          network: 'TESTNET',
          address: addr,
          supportedAssets: ['USDC', 'GHST'],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('crypto_deposit_address_text')), findsOneWidget);
      expect(find.text(addr), findsOneWidget);
      // The chain is stated on the address itself: sending on the wrong
      // network loses the funds.
      expect(find.text('Base · TESTNET'), findsOneWidget);

      await tester.tap(find.byKey(const Key('crypto_copy_address_button')));
      await tester.pump();

      expect(copied.length, 1);
      expect((copied.first.arguments as Map)['text'], addr);
      expect(find.byKey(const Key('crypto_address_copied_snackbar')), findsOneWidget);
    });

    testWidgets('warns loudly when the address is on a test network',
        (tester) async {
      await tester.pumpWidget(wrap(
        chains: const [_baseChain],
        address: const CryptoAddressModel(
          state: CryptoAddressState.ready,
          chain: 'BASE',
          network: 'TESTNET',
          address: '0xabc',
          supportedAssets: ['USDC'],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('crypto_testnet_warning')), findsOneWidget);
      expect(
        find.textContaining('real funds sent here cannot be recovered'),
        findsOneWidget,
      );
    });

    testWidgets('does not cry wolf on a mainnet address', (tester) async {
      await tester.pumpWidget(wrap(
        chains: const [_mainnetChain],
        address: const CryptoAddressModel(
          state: CryptoAddressState.ready,
          chain: 'BASE',
          network: 'MAINNET',
          address: '0xabc',
          supportedAssets: ['USDC'],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('crypto_testnet_warning')), findsNothing);
      expect(find.text('Base · MAINNET'), findsOneWidget);
    });

    testWidgets('shows a provisioning state rather than an empty address',
        (tester) async {
      await tester.pumpWidget(wrap(
        chains: const [_baseChain],
        address: const CryptoAddressModel(
          state: CryptoAddressState.provisioning,
          chain: 'BASE',
          network: 'TESTNET',
          address: null,
        ),
      ));
      // Not pumpAndSettle: the provisioning state carries a spinner, which
      // never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('crypto_address_provisioning')), findsOneWidget);
      expect(find.text('Creating your Base address'), findsOneWidget);
      expect(find.byKey(const Key('crypto_copy_address_button')), findsNothing);
    });

    testWidgets('an unverified user gets a next step, not a raw error',
        (tester) async {
      // The backend answers 409 SUBCUSTOMER_REQUIRED. That is an answer, not a
      // failure: showing the exception string would strand the user.
      await tester.pumpWidget(wrap(
        chains: const [_baseChain],
        address: CryptoAddressModel.verificationRequired('BASE'),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('crypto_verification_required')), findsOneWidget);
      expect(find.text('Verify your identity first'), findsOneWidget);
      expect(find.byKey(const Key('crypto_verify_identity_button')), findsOneWidget);
      expect(find.byKey(const Key('crypto_deposit_address_text')), findsNothing);
      expect(find.byKey(const Key('crypto_address_provisioning')), findsNothing);
    });

    testWidgets('an unavailable corridor states the reason it gave',
        (tester) async {
      await tester.pumpWidget(wrap(
        chains: const [_baseChain],
        address: CryptoAddressModel.unavailable(
          'BASE',
          'Crypto deposit addresses are not available right now',
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('Crypto deposit addresses are not available right now'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('crypto_copy_address_button')), findsNothing);
    });
  });
}
