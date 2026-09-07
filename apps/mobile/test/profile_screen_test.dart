import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesspay/features/wallet/models/deposit_account_model.dart';
import 'package:vesspay/features/wallet/models/crypto_deposit_model.dart';
import 'package:vesspay/core/providers.dart';
import 'package:vesspay/core/routing/app_router.dart';
import 'package:vesspay/core/routing/app_routes.dart';
import 'package:vesspay/core/storage/token_storage.dart';
import 'package:vesspay/core/theme/app_theme.dart';
import 'package:vesspay/features/auth/models/user_model.dart';
import 'package:vesspay/features/auth/repositories/auth_repository.dart';
import 'package:vesspay/features/kyc/models/kyc_model.dart';
import 'package:vesspay/features/kyc/repositories/kyc_repository.dart';
import 'package:vesspay/features/travel/models/destination_model.dart';
import 'package:vesspay/features/travel/models/travel_profile_model.dart';
import 'package:vesspay/features/travel/repositories/travel_repository.dart';
import 'package:vesspay/features/wallet/models/topup_model.dart';
import 'package:vesspay/features/wallet/models/wallet_balance_model.dart';
import 'package:vesspay/features/wallet/models/wallet_currency_model.dart';
import 'package:vesspay/features/wallet/repositories/wallet_repository.dart';
import 'package:vesspay/features/pay/models/transaction_model.dart';

class TestMockAuthRepository implements AuthRepository {
  final UserModel? user;
  TestMockAuthRepository({this.user});

  @override
  Future<UserModel> getProfile() async {
    return user ??
        const UserModel(
          id: 'test-kwame-id',
          firstName: 'Kwame',
          lastName: 'Doe',
          email: 'kwame.doe@example.com',
          country: 'GH',
        );
  }

  @override
  Future<UserModel> login({
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<UserModel> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? country,
    String? nationality,
  }) async => throw UnimplementedError();

  @override
  Future<UserModel> updateProfile({
    String? firstName,
    String? lastName,
    String? country,
    String? nationality,
  }) async => throw UnimplementedError();

  @override
  Future<void> logout() async {}
}

class TestMockKycRepository implements KycRepository {
  final KycStatusModel status;
  TestMockKycRepository({KycStatusModel? status})
    : status =
          status ??
          KycStatusModel(
            onboardingStatus: 'APPROVED',
            enhancedKycStatus: 'TIER_2',
          );

  @override
  Future<KycLinkModel> getKycLink() async => KycLinkModel(
    url: 'https://verify.wewire.com/session-123',
    stage: 'ONBOARDING',
  );

  @override
  Future<KycStatusModel> getKycStatus() async => status;

  @override
  Future<KycStatusModel> submitDemoKyc() async => status;
}

class TestMockWalletRepository implements WalletRepository {
  @override
  Future<List<CryptoChainModel>> getCryptoChains() async => const [];

  @override
  Future<CryptoAddressModel> getCryptoAddress(String chain) async =>
      CryptoAddressModel.unavailable(chain, 'not stubbed');

  /// Last funding transaction a WeWire sandbox deposit was requested for.
  String? simulatedDepositFor;

  @override
  Future<List<WalletBalanceModel>> getBalances() async => [
    const WalletBalanceModel(currency: 'USD', balance: 500.00),
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
  }) async => throw UnimplementedError();

  @override
  Future<TopupResponseModel?> getPendingTopup({
    String currency = 'USD',
  }) async => null;

  @override
  Future<TopupResponseModel> getTopupStatus(
    String fundingTransactionId,
  ) async => throw UnimplementedError();

  @override
  Future<DepositAccountModel> getDepositAccount() async =>
      const DepositAccountModel(
        state: DepositAccountState.ready,
        currency: 'USD',
      );

  @override
  Future<DepositAccountModel> provisionDepositAccount({
    String? sourceOfFunds,
  }) async => const DepositAccountModel(
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
  Future<TravelProfileModel> setCurrentProfile(
    String destinationCountry,
  ) async => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Profile & Account Screen Tests', () {
    late TokenStorage storage;
    late TestMockAuthRepository authRepo;
    late TestMockKycRepository kycRepo;
    late TestMockWalletRepository walletRepo;
    late TestMockTravelRepository travelRepo;

    setUp(() async {
      storage = InMemoryTokenStorage();
      await storage.saveToken('valid-token');
      authRepo = TestMockAuthRepository();
      kycRepo = TestMockKycRepository();
      walletRepo = TestMockWalletRepository();
      travelRepo = TestMockTravelRepository();
    });

    Widget createTestWidget({
      UserModel? user,
      KycStatusModel? kycStatus,
      String initialRoute = AppRoutes.profile,
    }) {
      final activeAuthRepo = user != null
          ? TestMockAuthRepository(user: user)
          : authRepo;
      final activeKycRepo = kycStatus != null
          ? TestMockKycRepository(status: kycStatus)
          : kycRepo;

      final router = createAppRouter(initialLocation: initialRoute);

      return ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          authRepositoryProvider.overrideWithValue(activeAuthRepo),
          kycRepositoryProvider.overrideWithValue(activeKycRepo),
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

    testWidgets(
      'Renders Profile screen with avatar initials, Kwame Doe name, and email',
      (WidgetTester tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Verify screen title
        expect(find.text('Profile & Account'), findsOneWidget);

        // Verify user's name & email
        expect(find.byKey(const Key('profile_user_name')), findsOneWidget);
        expect(find.text('Kwame Doe'), findsOneWidget);
        expect(find.text('kwame.doe@example.com'), findsOneWidget);

        // Verify initials "KD"
        expect(find.text('KD'), findsOneWidget);

        // Verify corridor indicator
        expect(find.text('Traveling in Ghana'), findsOneWidget);
      },
    );

    testWidgets(
      'Renders KYC status Verified badge and Tier 2 text when approved',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          createTestWidget(
            kycStatus: KycStatusModel(
              onboardingStatus: 'APPROVED',
              enhancedKycStatus: 'TIER_2',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('profile_kyc_card')), findsOneWidget);
        expect(find.text('Verified'), findsOneWidget);
        expect(
          find.text(
            'Tier 2 Verified • Full cross-border wallet & virtual card limits active.',
          ),
          findsOneWidget,
        );
        expect(find.text('View Verification Details'), findsOneWidget);
      },
    );

    testWidgets(
      'Renders KYC Action Required badge and navigates to KYC verification on tap',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          createTestWidget(
            kycStatus: KycStatusModel(
              onboardingStatus: 'DRAFT',
              enhancedKycStatus: 'NOT_STARTED',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Action Required'), findsOneWidget);
        expect(find.text('Verify Identity Now'), findsOneWidget);

        // Tap manage KYC button
        await tester.tap(find.byKey(const Key('home_kyc_card')));
        await tester.pumpAndSettle();

        // Navigated to Identity Verification (KYC) screen
        expect(find.text('Identity Verification'), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'Renders Invite a Friend card, displays referral code and copies to clipboard',
      (WidgetTester tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('profile_invite_card')), findsOneWidget);
        expect(find.text('Invite a Friend, Get \$10'), findsOneWidget);
        expect(find.text('VESSPAY-KWAME'), findsOneWidget);

        // Tap Copy referral code
        final copyBtn = find.byKey(const Key('profile_copy_code_button'));
        expect(copyBtn, findsOneWidget);
        await tester.ensureVisible(copyBtn);
        await tester.pumpAndSettle();
        await tester.tap(copyBtn);
        await tester.pump();

        // Verifies SnackBar feedback
        expect(find.text('Referral code copied to clipboard!'), findsOneWidget);
        await tester.pumpAndSettle();

        // Tap Invite Friends button opens modal
        final inviteBtn = find.byKey(const Key('profile_invite_button'));
        await tester.ensureVisible(inviteBtn);
        await tester.pumpAndSettle();
        await tester.tap(inviteBtn);
        await tester.pumpAndSettle();

        expect(find.text('Invite a Friend'), findsOneWidget);
        expect(find.byKey(const Key('modal_copy_link_button')), findsOneWidget);

        // Tap copy in modal
        await tester.tap(find.byKey(const Key('modal_copy_link_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Copied to clipboard!'), findsOneWidget);
        await tester.pumpAndSettle();
      },
    );

    testWidgets('Renders Share VessPay card and allows copying share link', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile_share_card')), findsOneWidget);
      expect(find.text('Share VessPay'), findsOneWidget);
      expect(find.text('https://vesspay.com/app'), findsOneWidget);

      // Tap Copy Link
      final copyShareBtn = find.byKey(
        const Key('profile_copy_share_link_button'),
      );
      expect(copyShareBtn, findsOneWidget);
      await tester.ensureVisible(copyShareBtn);
      await tester.pumpAndSettle();
      await tester.tap(copyShareBtn);
      await tester.pump();

      expect(find.text('VessPay download link copied!'), findsOneWidget);
      await tester.pumpAndSettle();

      // Tap Share App Link button opens modal
      final shareAppBtn = find.byKey(const Key('profile_share_app_button'));
      await tester.ensureVisible(shareAppBtn);
      await tester.pumpAndSettle();
      await tester.tap(shareAppBtn);
      await tester.pumpAndSettle();

      expect(find.text('Share VessPay App'), findsOneWidget);
      expect(find.byKey(const Key('modal_copy_link_button')), findsOneWidget);

      // Dismiss modal
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    });

    testWidgets('Navigates from Home dashboard avatar icon to Profile screen', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget(initialRoute: AppRoutes.home));
      await tester.pumpAndSettle();

      // On Home dashboard
      expect(find.text('VessPay Home'), findsOneWidget);
      expect(find.byKey(const Key('home_avatar_button')), findsOneWidget);

      // Tap top-left avatar icon
      await tester.tap(find.byKey(const Key('home_avatar_button')));
      await tester.pumpAndSettle();

      // Landed on Profile screen
      expect(find.byKey(const Key('profile_screen')), findsOneWidget);
      expect(find.text('Profile & Account'), findsOneWidget);
      expect(find.text('Kwame Doe'), findsOneWidget);

      // Tab screens carry no back button; the bottom nav returns to Home
      await tester.tap(find.byKey(const Key('nav_item_home')));
      await tester.pumpAndSettle();

      expect(find.text('VessPay Home'), findsOneWidget);
    });
  });
}
