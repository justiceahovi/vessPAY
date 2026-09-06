import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesspay/core/providers.dart';
import 'package:vesspay/core/routing/app_router.dart';
import 'package:vesspay/core/routing/app_routes.dart';
import 'package:vesspay/core/storage/token_storage.dart';
import 'package:vesspay/core/theme/app_theme.dart';
import 'package:vesspay/features/auth/screens/login_screen.dart';
import 'package:vesspay/features/auth/screens/signup_screen.dart';
import 'package:vesspay/features/placeholders/placeholder_screens.dart';
import 'package:vesspay/features/splash/screens/splash_screen.dart';
import 'support/fake_wallet_currency.dart';

void main() {
  group('T1.5 Acceptance Criteria: Navigation Shell & Splash Screen', () {
    testWidgets('App launches to splash screen with brand elements and animation',
        (WidgetTester tester) async {
      final tokenStorage = InMemoryTokenStorage();
      final router = createAppRouter(
        initialLocation: AppRoutes.splash,
        splashMinDuration: const Duration(milliseconds: 500),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(tokenStorage),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );

      // Verify Splash screen content is visible immediately
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.text('VessPay'), findsOneWidget);
      expect(find.text('Pay in Africa without a local SIM.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Drain timers
      await tester.pumpAndSettle();
    });

    testWidgets(
        'Routes to onboarding placeholder when no auth token is stored',
        (WidgetTester tester) async {
      final tokenStorage = InMemoryTokenStorage(); // no token
      final router = createAppRouter(
        initialLocation: AppRoutes.splash,
        splashMinDuration: const Duration(milliseconds: 200),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(tokenStorage),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );

      // Verify initial splash state
      expect(find.byType(SplashScreen), findsOneWidget);

      // Advance time past the splash minimum duration
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      // Verify routed to Onboarding
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.byType(OnboardingPlaceholderScreen), findsOneWidget);
      expect(find.byKey(const Key('onboarding_screen')), findsOneWidget);
      expect(find.text('Welcome to VessPay'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.text('Log In'), findsOneWidget);
      // Top right does not show Ghana since user hasn't selected destination
      expect(find.text('Ghana Active'), findsNothing);
      expect(find.byKey(const Key('onboarding_skip_button')), findsOneWidget);
    });

    testWidgets(
        'Routes to home placeholder when valid auth token is stored',
        (WidgetTester tester) async {
      final tokenStorage = InMemoryTokenStorage();
      await tokenStorage.saveToken('mock-valid-jwt-token'); // has token

      final router = createAppRouter(
        initialLocation: AppRoutes.splash,
        splashMinDuration: const Duration(milliseconds: 200),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(tokenStorage),
            // This account already holds a USD wallet, so no currency prompt.
            ...walletCurrencyOverrides(),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );

      // Verify initial splash state
      expect(find.byType(SplashScreen), findsOneWidget);

      // Advance time past the splash minimum duration
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      // Verify routed directly to Home
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.byType(HomePlaceholderScreen), findsOneWidget);
      expect(find.byKey(const Key('home_screen')), findsOneWidget);
      expect(find.text('VessPay Home'), findsOneWidget);
      expect(find.text('Log Out (Return to Login)'), findsOneWidget);
    });

    testWidgets(
        'GoRouter placeholder routes are all registered and render properly',
        (WidgetTester tester) async {
      final routesToTest = [
        (AppRoutes.onboarding, OnboardingPlaceholderScreen),
        (AppRoutes.login, LoginScreen),
        (AppRoutes.signup, SignupScreen),
        (AppRoutes.travelModeSetup, TravelModeSetupPlaceholderScreen),
        (AppRoutes.home, HomePlaceholderScreen),
      ];

      for (final entry in routesToTest) {
        final router = createAppRouter(initialLocation: entry.$1);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              routerProvider.overrideWithValue(router),
            ],
            child: MaterialApp.router(
              theme: AppTheme.lightTheme,
              routerConfig: router,
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.byType(entry.$2), findsOneWidget);
      }
    });

    testWidgets('Interactive navigation between placeholder screens works',
        (WidgetTester tester) async {
      final router = createAppRouter(initialLocation: AppRoutes.onboarding);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPlaceholderScreen), findsOneWidget);

      // Tap Create Account -> navigates to signup screen
      await tester.tap(find.byKey(const Key('onboarding_signup_button')));
      await tester.pumpAndSettle();
      expect(find.byType(SignupScreen), findsOneWidget);

      // In SignupScreen, tap Sign In -> navigates to login
      await tester.ensureVisible(find.byKey(const Key('signup_to_login_link')));
      await tester.tap(find.byKey(const Key('signup_to_login_link')));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}
