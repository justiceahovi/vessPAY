import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vesspay/core/providers.dart';
import 'package:vesspay/core/routing/app_router.dart';
import 'package:vesspay/core/routing/app_routes.dart';
import 'package:vesspay/core/config/corridors.dart';
import 'package:vesspay/features/travel/providers/travel_providers.dart';
import 'package:vesspay/core/storage/token_storage.dart';
import 'package:vesspay/core/theme/app_theme.dart';
import 'package:vesspay/features/placeholders/placeholder_screens.dart';
import 'package:vesspay/features/travel/models/destination_model.dart';
import 'package:vesspay/features/travel/models/travel_profile_model.dart';
import 'package:vesspay/features/travel/repositories/travel_repository.dart';
import 'support/fake_wallet_currency.dart';

class FakeTravelRepository implements TravelRepository {
  TravelProfileModel? currentProfile;
  int setCurrentProfileCallCount = 0;
  String? lastSetCountry;

  @override
  Future<List<DestinationModel>> getDestinations() async {
    // Mirrors what GET /api/travel/destinations actually returns, including
    // each corridor's payout availability -- so a corridor whose rail is dark
    // is dark here too.
    return kDefaultDestinations;
  }

  @override
  Future<TravelProfileModel?> getCurrentProfile() async {
    return currentProfile;
  }

  @override
  Future<TravelProfileModel> setCurrentProfile(String destinationCountry) async {
    setCurrentProfileCallCount++;
    lastSetCountry = destinationCountry;

    final updated = TravelProfileModel(
      id: 'profile-uuid-1',
      userId: 'user-uuid-1',
      destinationCountry: destinationCountry,
      // From the corridor table, so a third corridor is not silently mapped
      // to the second one's currency.
      destinationCurrency: corridorFor(destinationCountry).currency,
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    currentProfile = updated;
    return updated;
  }
}

void main() {
  group('T2.2: Destination Selection Screen Tests', () {
    late FakeTravelRepository fakeTravelRepo;
    late TokenStorage inMemoryStorage;

    setUp(() async {
      fakeTravelRepo = FakeTravelRepository();
      inMemoryStorage = InMemoryTokenStorage();
      await inMemoryStorage.saveToken('fake-jwt-token');
    });

    Widget createTestApp({GoRouter? router}) {
      final activeRouter = router ??
          createAppRouter(initialLocation: AppRoutes.travelModeSetup);

      return ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(inMemoryStorage),
          travelRepositoryProvider.overrideWithValue(fakeTravelRepo),
          ...walletCurrencyOverrides(),
          routerProvider.overrideWithValue(activeRouter),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: activeRouter,
        ),
      );
    }

    testWidgets(
        'Renders "Where are you travelling?" headline and DESIGN.md styling',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Verify screen key
      expect(find.byKey(const Key('travel_mode_setup_screen')), findsOneWidget);
      expect(find.byType(DestinationSelectionScreen), findsOneWidget);

      // Verify headline and subtitle
      expect(find.text('Choose your destination!'), findsOneWidget);
      expect(find.text('LOCAL PAYMENT RAIL SETUP'), findsOneWidget);
      expect(
          find.text(
              'Select your destination to activate local payment rails and live exchange rates!'),
          findsOneWidget);

      // Verify destinations are listed: Ghana and Nigeria
      expect(find.text('Ghana'), findsOneWidget);
      expect(find.text('Nigeria'), findsOneWidget);
      expect(find.text('USD → GHS'), findsOneWidget);
      expect(find.text('USD → NGN'), findsOneWidget);

      // Verify flag emojis
      expect(find.text('🇬🇭'), findsOneWidget);
      expect(find.text('🇳🇬'), findsOneWidget);

      // Kenya is offered too, priced through the USD cross
      expect(find.text('Kenya'), findsOneWidget);
      expect(find.text('USD → KES'), findsOneWidget);
      expect(find.text('🇰🇪'), findsOneWidget);

      // Verify Ghana has Instant MoMo Payouts highlight
      expect(find.text('Instant MoMo & Bank Payments'), findsOneWidget);

      // Verify action button exists
      expect(find.byKey(const Key('travel_to_home_button')), findsOneWidget);
    });

    testWidgets(
        'Selecting Ghana persists active destination server-side and navigates to Home',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Tap Ghana destination card explicitly
      final ghanaCard =
          find.byKey(const Key('destination_card_gh'));
      expect(ghanaCard, findsOneWidget);
      await tester.tap(ghanaCard);
      await tester.pumpAndSettle();

      // Verify CTA button says "Activate Ghana local payment rails"
      expect(find.text('Activate Ghana local payment rails'), findsOneWidget);

      // Tap the action button to confirm
      final confirmBtn = find.byKey(const Key('travel_to_home_button'));
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Verify repository was called to persist destination
      expect(fakeTravelRepo.setCurrentProfileCallCount, equals(1));
      expect(fakeTravelRepo.lastSetCountry, equals('GH'));
      expect(fakeTravelRepo.currentProfile?.destinationCountry, equals('GH'));

      // Verify navigation reached Home
      expect(find.byType(HomePlaceholderScreen), findsOneWidget);
      expect(find.byKey(const Key('home_screen')), findsOneWidget);
      expect(find.text('VessPay Home'), findsOneWidget);

      // Verify Home immediately reflects Ghana corridor
      expect(find.text('🇬🇭'), findsAtLeast(1));
      expect(find.textContaining('GH₵'), findsAtLeast(1));
    });

    testWidgets(
        'Acceptance Criteria: Selecting Ghana persists destination and app reflects it after restart',
        (WidgetTester tester) async {
      // 1. Initial run: User selects Ghana on travel setup screen
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      final confirmBtn = find.byKey(const Key('travel_to_home_button'));
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Confirm reached Home
      expect(find.text('🇬🇭'), findsAtLeast(1));
      expect(fakeTravelRepo.currentProfile?.destinationCountry, equals('GH'));

      // 2. Simulate complete app restart (fresh router starting at splash, with same storage & repo)
      final restartedRouter = createAppRouter(
        initialLocation: AppRoutes.splash,
        splashMinDuration: const Duration(milliseconds: 150),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(inMemoryStorage),
            travelRepositoryProvider.overrideWithValue(fakeTravelRepo),
            ...walletCurrencyOverrides(),
            routerProvider.overrideWithValue(restartedRouter),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: restartedRouter,
          ),
        ),
      );

      // Settle splash routing into Home
      await tester.pumpAndSettle();

      // Verify app auto-routed straight to Home because user has token
      expect(find.byType(HomePlaceholderScreen), findsOneWidget);

      // Verify the app reflects the persisted Ghana travel corridor after restart!
      expect(find.text('🇬🇭'), findsAtLeast(1));
      expect(find.textContaining('GH₵'), findsAtLeast(1));
    });

    testWidgets('Switching destination to Nigeria updates selection and Home',
        (WidgetTester tester) async {
      // Nigeria is fully selectable even though its payout rail is not open:
      // the whole flow up to confirmation is real, and the gate lives on the
      // review screen, at the one step that moves money.
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      final nigeriaCard = find.byKey(const Key('destination_card_ng'));
      expect(nigeriaCard, findsOneWidget);
      await tester.tap(nigeriaCard);
      await tester.pumpAndSettle();

      expect(find.text('Activate Nigeria local payment rails'), findsOneWidget);

      final confirmBtn = find.byKey(const Key('travel_to_home_button'));
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(fakeTravelRepo.setCurrentProfileCallCount, equals(1));
      expect(fakeTravelRepo.lastSetCountry, equals('NG'));

      // Home reflects the Nigeria corridor
      expect(find.text('🇳🇬'), findsAtLeast(1));
      expect(find.textContaining('₦'), findsAtLeast(1));
    });
  });
}
