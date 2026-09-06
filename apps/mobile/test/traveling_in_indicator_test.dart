import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vesspay/features/wallet/models/deposit_account_model.dart';
import 'package:vesspay/core/providers.dart';
import 'package:vesspay/core/routing/app_router.dart';
import 'package:vesspay/core/routing/app_routes.dart';
import 'package:vesspay/core/storage/token_storage.dart';
import 'package:vesspay/core/theme/app_theme.dart';
import 'package:vesspay/features/placeholders/placeholder_screens.dart';
import 'package:vesspay/features/travel/models/destination_model.dart';
import 'package:vesspay/features/travel/models/travel_profile_model.dart';
import 'package:vesspay/features/travel/providers/travel_providers.dart';
import 'package:vesspay/features/travel/repositories/travel_repository.dart';
import 'package:vesspay/features/travel/widgets/traveling_in_indicator.dart';
import 'package:vesspay/features/wallet/models/topup_model.dart';
import 'package:vesspay/features/wallet/models/wallet_balance_model.dart';
import 'package:vesspay/features/wallet/models/wallet_currency_model.dart';
import 'package:vesspay/features/wallet/repositories/wallet_repository.dart';

class MockTravelRepository implements TravelRepository {
  TravelProfileModel? profile;
  int setCallCount = 0;

  MockTravelRepository({this.profile});

  @override
  Future<List<DestinationModel>> getDestinations() async {
    return const [
      DestinationModel(country: 'GH', name: 'Ghana', currency: 'GHS'),
      DestinationModel(country: 'NG', name: 'Nigeria', currency: 'NGN'),
    ];
  }

  @override
  Future<TravelProfileModel?> getCurrentProfile() async {
    return profile;
  }

  @override
  Future<TravelProfileModel> setCurrentProfile(String destinationCountry) async {
    setCallCount++;
    final updated = TravelProfileModel(
      id: 'profile-$destinationCountry',
      userId: 'user-1',
      destinationCountry: destinationCountry,
      destinationCurrency: destinationCountry == 'GH' ? 'GHS' : 'NGN',
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    profile = updated;
    return updated;
  }
}

/// The Home balance card only renders its local-currency reference line when
/// balances resolve, so the corridor assertions need a working wallet source.
class MockWalletRepositoryForIndicator implements WalletRepository {
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
  Future<TopupResponseModel> confirmTopup(String fundingTransactionId) async =>
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
}

void main() {
  group('T2.3: Global "Traveling in" State & Indicator Tests', () {
    late MockTravelRepository mockRepo;
    late TokenStorage storage;

    final ghanaProfile = TravelProfileModel(
      id: 'profile-gh-1',
      userId: 'user-1',
      destinationCountry: 'GH',
      destinationCurrency: 'GHS',
      isActive: true,
    );

    final nigeriaProfile = TravelProfileModel(
      id: 'profile-ng-1',
      userId: 'user-1',
      destinationCountry: 'NG',
      destinationCurrency: 'NGN',
      isActive: true,
    );

    setUp(() async {
      storage = InMemoryTokenStorage();
      await storage.saveToken('valid-token-123');
      mockRepo = MockTravelRepository(profile: ghanaProfile);
    });

    Widget createIndicatorTestWidget({
      TravelingInVariant variant = TravelingInVariant.card,
      VoidCallback? onTap,
    }) {
      return ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          travelRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: TravelingInIndicator(
                variant: variant,
                onTap: onTap,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Global selectors reactively expose active travel profile details',
        (WidgetTester tester) async {
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(storage),
            travelRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              final text = ref.watch(travelingInTextProvider);
              final country = ref.watch(activeDestinationCountryProvider);
              final currency = ref.watch(activeDestinationCurrencyProvider);
              return Directionality(
                textDirection: TextDirection.ltr,
                child: Text('$text | $country | $currency'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(capturedRef.read(travelingInTextProvider),
          equals('Traveling in 🇬🇭 Ghana'));
      expect(capturedRef.read(activeDestinationCountryProvider), equals('GH'));
      expect(capturedRef.read(activeDestinationCurrencyProvider), equals('GHS'));
    });

    testWidgets('Compact pill indicator renders "Traveling in 🇬🇭 Ghana"',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createIndicatorTestWidget(variant: TravelingInVariant.compact),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('traveling_in_indicator_compact')),
          findsOneWidget);
      expect(find.text('Traveling in 🇬🇭 Ghana'), findsOneWidget);
    });

    testWidgets('Card banner indicator renders full corridor details',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createIndicatorTestWidget(variant: TravelingInVariant.card),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home_active_corridor_badge')),
          findsOneWidget);
      expect(find.text('Traveling in 🇬🇭 Ghana'), findsOneWidget);
      expect(find.text('Active corridor: USD → GHS'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
    });

    testWidgets('Empty state rendered when no profile is set',
        (WidgetTester tester) async {
      mockRepo = MockTravelRepository(profile: null);

      await tester.pumpWidget(
        createIndicatorTestWidget(variant: TravelingInVariant.card),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('traveling_in_indicator_empty')),
          findsOneWidget);
      expect(find.text('No destination selected. Tap to setup.'),
          findsOneWidget);
    });

    testWidgets('Tapping indicator triggers navigation callback',
        (WidgetTester tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        createIndicatorTestWidget(
          variant: TravelingInVariant.card,
          onTap: () => tapped = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home_active_corridor_badge')));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets(
        'Acceptance Criteria: Indicator updates immediately after changing destination, without requiring an app restart',
        (WidgetTester tester) async {
      // Setup live GoRouter starting at Home with Ghana as initial profile
      mockRepo = MockTravelRepository(profile: ghanaProfile);

      final router = createAppRouter(initialLocation: AppRoutes.home);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(storage),
            travelRepositoryProvider.overrideWithValue(mockRepo),
            walletRepositoryProvider
                .overrideWithValue(MockWalletRepositoryForIndicator()),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Initial verification on Home: Ghana active
      expect(find.byType(HomePlaceholderScreen), findsOneWidget);
      expect(find.text('🇬🇭'), findsAtLeast(1));
      expect(find.textContaining('GH₵'), findsAtLeast(1));

      // 2. Navigate to destination selection modal by tapping header flag dropdown
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();

      // Verify arrived on "Where are you travelling?" screen
      expect(find.byType(DestinationSelectionScreen), findsOneWidget);
      expect(find.text('Where are you travelling?'), findsOneWidget);

      // 3. Select Nigeria
      final nigeriaCard = find.byKey(const Key('destination_card_ng'));
      expect(nigeriaCard, findsOneWidget);
      await tester.tap(nigeriaCard);
      await tester.pumpAndSettle();

      // 4. Confirm selection ("Activate Nigeria Travel Mode")
      final activateBtn = find.byKey(const Key('travel_to_home_button'));
      expect(find.text('Activate Nigeria Travel Mode'), findsOneWidget);
      await tester.tap(activateBtn);
      await tester.pumpAndSettle();

      // 5. Returned to Home screen:
      // VERIFY THE CORRIDOR HAS IMMEDIATELY UPDATED TO NIGERIA WITHOUT RESTART!
      expect(find.byType(HomePlaceholderScreen), findsOneWidget);
      expect(find.text('🇳🇬'), findsAtLeast(1));
      expect(find.textContaining('₦'), findsAtLeast(1));

      // 6. Change destination back to Ghana to confirm roundtrip reactivity
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();

      final ghanaCard = find.byKey(const Key('destination_card_gh'));
      await tester.tap(ghanaCard);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('travel_to_home_button')));
      await tester.pumpAndSettle();

      // VERIFY IMMEDIATELY BACK TO GHANA WITHOUT RESTART!
      expect(find.text('🇬🇭'), findsAtLeast(1));
      expect(find.textContaining('GH₵'), findsAtLeast(1));
    });
  });
}
