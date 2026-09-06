import 'package:flutter_test/flutter_test.dart';
import 'package:vesspay/core/api/api_client.dart';
import 'package:vesspay/core/storage/token_storage.dart';
import 'package:vesspay/features/auth/repositories/auth_repository.dart';

void main() {
  group('T1.6 Acceptance Criteria: Live Auth Flow Integration Test', () {
    const backendUrl = 'http://localhost:3000';
    late TokenStorage tokenStorage;
    late ApiClient apiClient;
    late AuthRepository authRepo;

    setUp(() {
      tokenStorage = InMemoryTokenStorage();
      apiClient = ApiClient(
        baseUrl: backendUrl,
        tokenStorage: tokenStorage,
      );
      authRepo = AuthRepositoryImpl(
        apiClient: apiClient,
        tokenStorage: tokenStorage,
      );
    });

    test('Live user registers, persists token, logs out, logs in, and fetches profile',
        () async {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final uniqueEmail = 't16_user_$timestamp@example.com';
      const password = 'SecurePassword123!';

      // 1. Register a real user against the backend
      final registeredUser = await authRepo.register(
        firstName: 'Kwame',
        lastName: 'Mensah',
        email: uniqueEmail,
        password: password,
        country: 'Ghana',
        nationality: 'Ghanaian',
      );

      expect(registeredUser.firstName, equals('Kwame'));
      expect(registeredUser.lastName, equals('Mensah'));
      expect(registeredUser.email, equals(uniqueEmail));
      expect(registeredUser.id, isNotEmpty);

      // 2. Verify token was saved to storage
      final hasTokenAfterRegister = await tokenStorage.hasToken();
      final tokenAfterRegister = await tokenStorage.getToken();
      expect(hasTokenAfterRegister, isTrue);
      expect(tokenAfterRegister, isNotNull);
      expect(tokenAfterRegister!.startsWith('ey'), isTrue); // valid JWT structure

      // 3. Clear token (simulate log out)
      await authRepo.logout();
      expect(await tokenStorage.hasToken(), isFalse);

      // 4. Log in with the registered credentials
      final loggedInUser = await authRepo.login(
        email: uniqueEmail,
        password: password,
      );

      expect(loggedInUser.id, equals(registeredUser.id));
      expect(loggedInUser.email, equals(uniqueEmail));

      // 5. Verify token is stored again
      final hasTokenAfterLogin = await tokenStorage.hasToken();
      final tokenAfterLogin = await tokenStorage.getToken();
      expect(hasTokenAfterLogin, isTrue);
      expect(tokenAfterLogin, isNotNull);

      // 6. Verify authenticated GET /api/auth/me works with the stored token
      final profile = await authRepo.getProfile();
      expect(profile.id, equals(registeredUser.id));
      expect(profile.fullName, equals('Kwame Mensah'));
      expect(profile.country, equals('Ghana'));
    });
  });
}
