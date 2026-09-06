import 'package:flutter_test/flutter_test.dart';
import 'package:vesspay/core/api/api_client.dart';
import 'package:vesspay/core/api/api_error.dart';
import 'package:vesspay/core/config/app_config.dart';
import 'package:vesspay/core/storage/token_storage.dart';

void main() {
  group('Live Backend Integration Test (T1.4 Acceptance Criteria)', () {
    late TokenStorage storage;
    late ApiClient client;

    setUp(() {
      storage = InMemoryTokenStorage();
      AppConfig.setBaseUrl('http://localhost:3000');
      client = ApiClient(tokenStorage: storage);
    });

    test('successfully calls GET /api/health against local backend', () async {
      final health = await client.get<Map<String, dynamic>>('/api/health');
      expect(health['status'], equals('ok'));
    });

    test('registers, stores token, and calls GET /api/auth/me with stored token', () async {
      final testEmail = 'flutter-client-${DateTime.now().millisecondsSinceEpoch}@example.com';

      // 1. Register a new user
      final registerRes = await client.post<Map<String, dynamic>>(
        '/api/auth/register',
        data: {
          'firstName': 'Flutter',
          'lastName': 'Tester',
          'email': testEmail,
          'password': 'Password123!',
          'country': 'GH',
          'nationality': 'Ghanaian',
        },
      );

      expect(registerRes['token'], isNotNull);
      final token = registerRes['token'] as String;
      final registeredUser = registerRes['user'] as Map<String, dynamic>;
      expect(registeredUser['email'], equals(testEmail));

      // 2. Save token to storage
      await client.saveToken(token);
      expect(await client.isAuthenticated(), isTrue);

      // 3. Call GET /api/auth/me (AuthInterceptor should attach Bearer token)
      final meRes = await client.get<Map<String, dynamic>>('/api/auth/me');
      expect(meRes['user'], isNotNull);
      final meUser = meRes['user'] as Map<String, dynamic>;
      expect(meUser['email'], equals(testEmail));
      expect(meUser['id'], equals(registeredUser['id']));

      // 4. Clear token and verify subsequent call fails with 401 UNAUTHORIZED
      await client.clearToken();
      expect(await client.isAuthenticated(), isFalse);

      expect(
        () async => await client.get('/api/auth/me'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', equals('UNAUTHORIZED'))
              .having((e) => e.statusCode, 'statusCode', equals(401)),
        ),
      );
    });
  });
}
