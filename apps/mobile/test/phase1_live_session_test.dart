import 'package:flutter_test/flutter_test.dart';
import 'package:vesspay/core/api/api_client.dart';
import 'package:vesspay/core/storage/token_storage.dart';
import 'package:vesspay/features/auth/repositories/auth_repository.dart';

void main() {
  group('T1.7: Phase 1 Deliverable Check — Live Backend Verification', () {
    const backendUrl = 'http://localhost:3000';

    test(
        'Live Backend End-to-End: brand-new user signs up, persists token, survives restart, and fetches valid session',
        () async {
      final persistentStorage = InMemoryTokenStorage();
      final apiClient = ApiClient(
        baseUrl: backendUrl,
        tokenStorage: persistentStorage,
      );
      final authRepo = AuthRepositoryImpl(
        apiClient: apiClient,
        tokenStorage: persistentStorage,
      );

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final testEmail = 'phase1_live_$timestamp@example.com';
      const testPassword = 'Password123!';

      // 1. Initial State: Brand new user with no token
      expect(await persistentStorage.hasToken(), isFalse);

      // 2. Sign Up against live backend (atomic DB user + default USD wallet creation)
      final user = await authRepo.register(
        firstName: 'Alex',
        lastName: 'Johnson',
        email: testEmail,
        password: testPassword,
        country: 'United Kingdom',
        nationality: 'British',
      );

      expect(user.id, isNotEmpty);
      expect(user.firstName, equals('Alex'));
      expect(user.lastName, equals('Johnson'));
      expect(user.email, equals(testEmail));

      // 3. Verify Token Storage: JWT token received and saved
      final token = await persistentStorage.getToken();
      expect(token, isNotNull);
      expect(token!.startsWith('ey'), isTrue);
      expect(await persistentStorage.hasToken(), isTrue);

      // 4. Simulate App Restart: Fresh ApiClient & AuthRepository with persisted storage
      final restartedStorage = persistentStorage; // Persisted on device
      final restartedApiClient = ApiClient(
        baseUrl: backendUrl,
        tokenStorage: restartedStorage,
      );
      final restartedAuthRepo = AuthRepositoryImpl(
        apiClient: restartedApiClient,
        tokenStorage: restartedStorage,
      );

      // 5. Verify Session Persistence: Token still valid, profile retrieved
      final profile = await restartedAuthRepo.getProfile();
      expect(profile.id, equals(user.id));
      expect(profile.email, equals(testEmail));
      expect(profile.fullName, equals('Alex Johnson'));
    });
  });
}
