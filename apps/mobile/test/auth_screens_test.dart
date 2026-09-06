import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesspay/core/api/api_error.dart';
import 'package:vesspay/core/providers.dart';
import 'package:vesspay/core/routing/app_router.dart';
import 'package:vesspay/core/routing/app_routes.dart';
import 'package:vesspay/core/storage/token_storage.dart';
import 'package:vesspay/core/theme/app_theme.dart';
import 'package:vesspay/features/auth/models/user_model.dart';
import 'package:vesspay/features/auth/repositories/auth_repository.dart';
import 'package:vesspay/features/auth/screens/login_screen.dart';
import 'package:vesspay/features/auth/screens/signup_screen.dart';
import 'package:vesspay/features/placeholders/placeholder_screens.dart';
import 'support/fake_wallet_currency.dart';

class FakeAuthRepository implements AuthRepository {
  bool shouldFail = false;
  String failCode = 'SERVER_ERROR';
  String failMessage = 'Operation failed';

  UserModel mockUser = const UserModel(
    id: 'test-user-id',
    firstName: 'Alex',
    lastName: 'Johnson',
    email: 'alex@example.com',
  );

  final TokenStorage tokenStorage;

  FakeAuthRepository({required this.tokenStorage});

  @override
  Future<UserModel> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? country,
    String? nationality,
  }) async {
    if (shouldFail) {
      throw ApiException(code: failCode, message: failMessage);
    }
    await tokenStorage.saveToken('fake-jwt-token');
    return mockUser;
  }

  @override
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    if (shouldFail) {
      throw ApiException(code: failCode, message: failMessage);
    }
    await tokenStorage.saveToken('fake-jwt-token');
    return mockUser;
  }

  @override
  Future<UserModel> getProfile() async => mockUser;

  @override
  Future<void> logout() async {
    await tokenStorage.deleteToken();
  }
}

void main() {
  group('T1.6: Sign Up Screen Tests', () {
    late InMemoryTokenStorage tokenStorage;
    late FakeAuthRepository fakeAuthRepo;

    setUp(() {
      tokenStorage = InMemoryTokenStorage();
      fakeAuthRepo = FakeAuthRepository(tokenStorage: tokenStorage);
    });

    void setMobileView(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    testWidgets('Shows validation errors on empty submission',
        (WidgetTester tester) async {
      setMobileView(tester);
      final router = createAppRouter(initialLocation: AppRoutes.signup);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(tokenStorage),
            authRepositoryProvider.overrideWithValue(fakeAuthRepo),
            ...walletCurrencyOverrides(currency: null),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SignupScreen), findsOneWidget);

      // Scroll to submit button and tap
      final submitButton = find.byKey(const Key('signup_submit_button'));
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Assert inline validation messages
      expect(find.text('First name is required'), findsOneWidget);
      expect(find.text('Last name is required'), findsOneWidget);
      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('Shows password length validation error',
        (WidgetTester tester) async {
      setMobileView(tester);
      final router = createAppRouter(initialLocation: AppRoutes.signup);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(tokenStorage),
            authRepositoryProvider.overrideWithValue(fakeAuthRepo),
            ...walletCurrencyOverrides(currency: null),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('signup_first_name_field')), 'Alex');
      await tester.enterText(
          find.byKey(const Key('signup_last_name_field')), 'Johnson');
      await tester.enterText(
          find.byKey(const Key('signup_email_field')), 'alex@example.com');
      await tester.enterText(
          find.byKey(const Key('signup_password_field')), '123'); // < 6 chars

      final submitButton = find.byKey(const Key('signup_submit_button'));
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(find.text('Password must be at least 6 characters'), findsOneWidget);
    });

    testWidgets('Displays error banner when registration fails',
        (WidgetTester tester) async {
      setMobileView(tester);
      fakeAuthRepo.shouldFail = true;
      fakeAuthRepo.failCode = 'DUPLICATE_EMAIL';
      fakeAuthRepo.failMessage = 'A user with this email already exists';

      final router = createAppRouter(initialLocation: AppRoutes.signup);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(tokenStorage),
            authRepositoryProvider.overrideWithValue(fakeAuthRepo),
            ...walletCurrencyOverrides(currency: null),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('signup_first_name_field')), 'Alex');
      await tester.enterText(
          find.byKey(const Key('signup_last_name_field')), 'Johnson');
      await tester.enterText(
          find.byKey(const Key('signup_email_field')), 'alex@example.com');
      await tester.enterText(
          find.byKey(const Key('signup_password_field')), 'secret123');

      final submitButton = find.byKey(const Key('signup_submit_button'));
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('signup_error_banner')), findsOneWidget);
      expect(find.text('A user with this email already exists'), findsOneWidget);
      expect(await tokenStorage.hasToken(), isFalse);
    });

    testWidgets(
        'Successful registration stores token and navigates to wallet currency setup',
        (WidgetTester tester) async {
      setMobileView(tester);
      final router = createAppRouter(initialLocation: AppRoutes.signup);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(tokenStorage),
            authRepositoryProvider.overrideWithValue(fakeAuthRepo),
            ...walletCurrencyOverrides(currency: null),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('signup_first_name_field')), 'Alex');
      await tester.enterText(
          find.byKey(const Key('signup_last_name_field')), 'Johnson');
      await tester.enterText(
          find.byKey(const Key('signup_email_field')), 'alex.johnson@example.com');
      await tester.enterText(
          find.byKey(const Key('signup_password_field')), 'password123');

      final submitButton = find.byKey(const Key('signup_submit_button'));
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Token must be stored
      expect(await tokenStorage.hasToken(), isTrue);
      expect(await tokenStorage.getToken(), equals('fake-jwt-token'));

      // First run picks the wallet currency before travel mode setup
      expect(find.byKey(const Key('wallet_currency_selection_screen')),
          findsOneWidget);
      expect(find.text('What currency do you want your wallet in?'),
          findsOneWidget);
    });

    testWidgets('Tapping Sign In link navigates to LoginScreen',
        (WidgetTester tester) async {
      setMobileView(tester);
      final router = createAppRouter(initialLocation: AppRoutes.signup);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(tokenStorage),
            authRepositoryProvider.overrideWithValue(fakeAuthRepo),
            ...walletCurrencyOverrides(currency: null),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final loginLink = find.byKey(const Key('signup_to_login_link'));
      await tester.ensureVisible(loginLink);
      await tester.tap(loginLink);
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    });
  });

  group('T1.6: Login Screen Tests', () {
    late InMemoryTokenStorage tokenStorage;
    late FakeAuthRepository fakeAuthRepo;

    setUp(() {
      tokenStorage = InMemoryTokenStorage();
      fakeAuthRepo = FakeAuthRepository(tokenStorage: tokenStorage);
    });

    void setMobileView(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    testWidgets('Shows validation errors on empty login submission',
        (WidgetTester tester) async {
      setMobileView(tester);
      final router = createAppRouter(initialLocation: AppRoutes.login);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(tokenStorage),
            authRepositoryProvider.overrideWithValue(fakeAuthRepo),
            ...walletCurrencyOverrides(currency: null),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);

      final submitButton = find.byKey(const Key('login_submit_button'));
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('Displays error banner on invalid credentials',
        (WidgetTester tester) async {
      setMobileView(tester);
      fakeAuthRepo.shouldFail = true;
      fakeAuthRepo.failCode = 'INVALID_CREDENTIALS';
      fakeAuthRepo.failMessage = 'Invalid email or password';

      final router = createAppRouter(initialLocation: AppRoutes.login);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(tokenStorage),
            authRepositoryProvider.overrideWithValue(fakeAuthRepo),
            ...walletCurrencyOverrides(currency: null),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('login_email_field')), 'wrong@example.com');
      await tester.enterText(
          find.byKey(const Key('login_password_field')), 'wrongpass');

      final submitButton = find.byKey(const Key('login_submit_button'));
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_error_banner')), findsOneWidget);
      expect(find.text('Invalid email or password'), findsOneWidget);
      expect(await tokenStorage.hasToken(), isFalse);
    });

    testWidgets(
        'Successful login stores token and asks for a wallet currency when the '
        'account has none',
        (WidgetTester tester) async {
      setMobileView(tester);
      final router = createAppRouter(initialLocation: AppRoutes.login);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(tokenStorage),
            authRepositoryProvider.overrideWithValue(fakeAuthRepo),
            ...walletCurrencyOverrides(currency: null),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('login_email_field')), 'alex@example.com');
      await tester.enterText(
          find.byKey(const Key('login_password_field')), 'password123');

      final submitButton = find.byKey(const Key('login_submit_button'));
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Token must be stored
      expect(await tokenStorage.hasToken(), isTrue);
      expect(await tokenStorage.getToken(), equals('fake-jwt-token'));

      expect(find.byKey(const Key('wallet_currency_selection_screen')),
          findsOneWidget);
    });

    testWidgets(
        'Successful login skips currency setup when the account already has one',
        (WidgetTester tester) async {
      setMobileView(tester);
      fakeAuthRepo.mockUser = const UserModel(
        id: 'test-user-id',
        firstName: 'Alex',
        lastName: 'Johnson',
        email: 'alex@example.com',
        primaryCurrency: 'GBP',
      );
      final router = createAppRouter(initialLocation: AppRoutes.login);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(tokenStorage),
            authRepositoryProvider.overrideWithValue(fakeAuthRepo),
            ...walletCurrencyOverrides(currency: null),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('login_email_field')), 'alex@example.com');
      await tester.enterText(
          find.byKey(const Key('login_password_field')), 'password123');

      final submit = find.byKey(const Key('login_submit_button'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(find.byType(TravelModeSetupPlaceholderScreen), findsOneWidget);
    });

    testWidgets('Tapping Create account link navigates to SignupScreen',
        (WidgetTester tester) async {
      setMobileView(tester);
      final router = createAppRouter(initialLocation: AppRoutes.login);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(tokenStorage),
            authRepositoryProvider.overrideWithValue(fakeAuthRepo),
            ...walletCurrencyOverrides(currency: null),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final signupLink = find.byKey(const Key('login_to_signup_link'));
      await tester.ensureVisible(signupLink);
      await tester.tap(signupLink);
      await tester.pumpAndSettle();

      expect(find.byType(SignupScreen), findsOneWidget);
      expect(find.text('Create your account'), findsOneWidget);
    });
  });
}
