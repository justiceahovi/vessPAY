import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesspay/core/providers.dart';
import 'package:vesspay/core/routing/app_router.dart';
import 'package:vesspay/core/routing/app_routes.dart';
import 'package:vesspay/core/storage/token_storage.dart';
import 'package:vesspay/core/theme/app_theme.dart';
import 'package:vesspay/features/auth/models/user_model.dart';
import 'package:vesspay/features/auth/repositories/auth_repository.dart';
import 'package:vesspay/features/auth/screens/signup_screen.dart';
import 'package:vesspay/features/placeholders/placeholder_screens.dart';
import 'package:vesspay/features/splash/screens/splash_screen.dart';
import 'package:vesspay/core/storage/currency_preference_storage.dart';
import 'package:vesspay/features/wallet/repositories/wallet_repository.dart';
import 'support/fake_wallet_currency.dart';

class DeliverableMockAuthRepository implements AuthRepository {
  final TokenStorage tokenStorage;
  UserModel? registeredUser;

  DeliverableMockAuthRepository({required this.tokenStorage});

  @override
  Future<UserModel> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? country,
    String? nationality,
  }) async {
    const token = 'ey.mock.jwt.token.phase1.deliverable';
    await tokenStorage.saveToken(token);
    registeredUser = UserModel(
      id: 'phase1-user-id-123',
      firstName: firstName,
      lastName: lastName,
      email: email,
      country: country,
      nationality: nationality,
      createdAt: DateTime.now(),
    );
    return registeredUser!;
  }

  @override
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    const token = 'ey.mock.jwt.token.phase1.deliverable';
    await tokenStorage.saveToken(token);
    return registeredUser ??
        UserModel(
          id: 'phase1-user-id-123',
          firstName: 'Alex',
          lastName: 'Johnson',
          email: email,
          createdAt: DateTime.now(),
        );
  }

  @override
  Future<UserModel> getProfile() async {
    return registeredUser ??
        const UserModel(
          id: 'phase1-user-id-123',
          firstName: 'Alex',
          lastName: 'Johnson',
          email: 'alex.johnson@example.com',
        );
  }

  @override
  Future<UserModel> updateProfile({
    String? firstName,
    String? lastName,
    String? country,
    String? nationality,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> logout() async {
    await tokenStorage.deleteToken();
  }
}

void main() {
  group('T1.7: Phase 1 Deliverable Check — End-to-End User Flow', () {
    testWidgets(
        'Full Journey: Cold launch -> Onboarding -> Sign up -> Reach Home -> Restart app -> Straight to Home with persisted session',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Persistent token storage simulating device storage that survives app restarts
      final persistentStorage = InMemoryTokenStorage();
      final mockAuthRepo = DeliverableMockAuthRepository(
        tokenStorage: persistentStorage,
      );

      // -------------------------------------------------------------
      // Step 1: Brand-new user opens the app (Cold Start, No Token)
      // -------------------------------------------------------------
      expect(await persistentStorage.hasToken(), isFalse);

      final walletRepo = FakeCurrencyWalletRepository();
      final currencyStorage = InMemoryCurrencyPreferenceStorage();

      var appRouter = createAppRouter(
        initialLocation: AppRoutes.splash,
        splashMinDuration: const Duration(milliseconds: 200),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(persistentStorage),
            authRepositoryProvider.overrideWithValue(mockAuthRepo),
            walletRepositoryProvider.overrideWithValue(walletRepo),
            currencyPreferenceStorageProvider
                .overrideWithValue(currencyStorage),
            routerProvider.overrideWithValue(appRouter),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: appRouter,
          ),
        ),
      );

      // Verify app launches to Splash Screen
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.text('VessPay'), findsOneWidget);

      // Splash minimum duration expires -> Auto-routes to Onboarding (no token)
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.byType(SplashScreen), findsNothing);
      expect(find.byType(OnboardingPlaceholderScreen), findsOneWidget);
      expect(find.text('Welcome to VessPay'), findsOneWidget);

      // -------------------------------------------------------------
      // Step 2: User taps Create Account & fills registration form
      // -------------------------------------------------------------
      final createAccountBtn = find.byKey(const Key('onboarding_signup_button'));
      await tester.ensureVisible(createAccountBtn);
      await tester.tap(createAccountBtn);
      await tester.pumpAndSettle();

      expect(find.byType(SignupScreen), findsOneWidget);
      expect(find.text('Create your account'), findsOneWidget);

      // Fill in signup fields
      await tester.enterText(
          find.byKey(const Key('signup_first_name_field')), 'Alex');
      await tester.enterText(
          find.byKey(const Key('signup_last_name_field')), 'Johnson');
      await tester.enterText(
          find.byKey(const Key('signup_email_field')), 'alex.johnson@example.com');
      await tester.enterText(
          find.byKey(const Key('signup_password_field')), 'Password123!');

      // Submit registration
      final signupSubmitBtn = find.byKey(const Key('signup_submit_button'));
      await tester.ensureVisible(signupSubmitBtn);
      await tester.tap(signupSubmitBtn);
      await tester.pumpAndSettle();

      // Verify token is now saved in storage
      expect(await persistentStorage.hasToken(), isTrue);

      // -------------------------------------------------------------
      // Step 3: Choose the wallet currency (first run only)
      // -------------------------------------------------------------
      expect(find.byKey(const Key('wallet_currency_selection_screen')),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('wallet_currency_card_gbp')));
      await tester.pump();
      final confirmCurrencyBtn =
          find.byKey(const Key('wallet_currency_confirm_button'));
      await tester.ensureVisible(confirmCurrencyBtn);
      await tester.tap(confirmCurrencyBtn);
      await tester.pumpAndSettle();

      // The choice is persisted before onboarding continues
      expect(walletRepo.savedCurrency, 'GBP');
      expect(await currencyStorage.getCurrency(), 'GBP');

      // User arrives at Travel Mode Setup placeholder screen
      expect(find.byType(TravelModeSetupPlaceholderScreen), findsOneWidget);

      // -------------------------------------------------------------
      // Step 4: Proceed to Home Dashboard
      // -------------------------------------------------------------
      final toHomeBtn = find.byKey(const Key('travel_to_home_button'));
      await tester.ensureVisible(toHomeBtn);
      await tester.tap(toHomeBtn);
      await tester.pumpAndSettle();

      // Verify user has reached the Home screen
      expect(find.byType(HomePlaceholderScreen), findsOneWidget);
      expect(find.byKey(const Key('home_screen')), findsOneWidget);
      expect(find.text('VessPay Home'), findsOneWidget);

      // -------------------------------------------------------------
      // Step 5: App Restart (Session & Currency Persistence Check)
      // -------------------------------------------------------------
      // Create a new router starting at splash, using the SAME persistent storage
      final restartedRouter = createAppRouter(
        initialLocation: AppRoutes.splash,
        splashMinDuration: const Duration(milliseconds: 200),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(persistentStorage),
            authRepositoryProvider.overrideWithValue(mockAuthRepo),
            walletRepositoryProvider.overrideWithValue(walletRepo),
            currencyPreferenceStorageProvider
                .overrideWithValue(currencyStorage),
            routerProvider.overrideWithValue(restartedRouter),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: restartedRouter,
          ),
        ),
      );

      // Relaunches to Splash Screen
      expect(find.byType(SplashScreen), findsOneWidget);

      // Splash minimum duration expires
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      // ACCEPTANCE CRITERIA VERIFIED:
      // User is routed straight to Home, NOT back to Onboarding or Login!
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.byType(OnboardingPlaceholderScreen), findsNothing);
      expect(find.byType(SignupScreen), findsNothing);
      expect(find.byType(HomePlaceholderScreen), findsOneWidget);
      expect(find.byKey(const Key('home_screen')), findsOneWidget);
      expect(find.text('VessPay Home'), findsOneWidget);

      // The wallet currency chosen at sign-up survived the restart
      expect(await currencyStorage.getCurrency(), 'GBP');
    });
  });
}
