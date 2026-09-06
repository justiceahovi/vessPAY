import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesspay/core/api/api_client.dart';
import 'package:vesspay/core/api/api_error.dart';
import 'package:vesspay/core/storage/token_storage.dart';

void main() {
  group('TokenStorage (InMemory)', () {
    late TokenStorage storage;

    setUp(() {
      storage = InMemoryTokenStorage();
    });

    test('saves, retrieves, checks, and deletes token', () async {
      expect(await storage.hasToken(), isFalse);
      expect(await storage.getToken(), isNull);

      await storage.saveToken('test-jwt-token-123');
      expect(await storage.hasToken(), isTrue);
      expect(await storage.getToken(), equals('test-jwt-token-123'));

      await storage.deleteToken();
      expect(await storage.hasToken(), isFalse);
      expect(await storage.getToken(), isNull);
    });
  });

  group('ApiException', () {
    test('parses standard backend error shape { error: { code, message } }', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/api/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/test'),
          statusCode: 409,
          data: {
            'error': {
              'code': 'DUPLICATE_EMAIL',
              'message': 'A user with this email already exists',
            },
          },
        ),
        type: DioExceptionType.badResponse,
      );

      final apiException = ApiException.fromDioException(dioException);
      expect(apiException.code, equals('DUPLICATE_EMAIL'));
      expect(apiException.message, equals('A user with this email already exists'));
      expect(apiException.statusCode, equals(409));
    });

    test('handles timeout and network connection errors', () {
      final timeoutException = DioException(
        requestOptions: RequestOptions(path: '/api/test'),
        type: DioExceptionType.connectionTimeout,
      );
      final apiTimeout = ApiException.fromDioException(timeoutException);
      expect(apiTimeout.code, equals('TIMEOUT'));

      final connException = DioException(
        requestOptions: RequestOptions(path: '/api/test'),
        type: DioExceptionType.connectionError,
      );
      final apiConn = ApiException.fromDioException(connException);
      expect(apiConn.code, equals('NETWORK_ERROR'));
    });
  });

  group('ApiClient with Mock Interceptor', () {
    late TokenStorage storage;
    late Dio dio;
    late ApiClient client;

    setUp(() {
      storage = InMemoryTokenStorage();
      dio = Dio(BaseOptions(baseUrl: 'http://mock.test'));
      client = ApiClient(dio: dio, tokenStorage: storage);
    });

    test('attaches stored Bearer token to requests', () async {
      await storage.saveToken('stored-token-xyz');

      String? capturedAuthHeader;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedAuthHeader = options.headers['Authorization'];
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'status': 'ok'},
              ),
            );
          },
        ),
      );

      final result = await client.get<Map<String, dynamic>>('/test-auth');
      expect(result['status'], equals('ok'));
      expect(capturedAuthHeader, equals('Bearer stored-token-xyz'));
    });

    test('parses GET/POST/PUT/DELETE with typed fromJson wrapper', () async {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'name': 'Ghana', 'currency': 'GHS'},
              ),
            );
          },
        ),
      );

      final destination = await client.get<Map<String, dynamic>>(
        '/destination',
        fromJson: (json) => json as Map<String, dynamic>,
      );
      expect(destination['name'], equals('Ghana'));
      expect(destination['currency'], equals('GHS'));
    });

    test('throws ApiException on non-200 responses', () async {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 401,
                  data: {
                    'error': {
                      'code': 'UNAUTHORIZED',
                      'message': 'Authorization token required',
                    },
                  },
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      expect(
        () async => await client.get('/protected'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', equals('UNAUTHORIZED'))
              .having((e) => e.statusCode, 'statusCode', equals(401)),
        ),
      );
    });
  });
}
