import 'package:dio/dio.dart';
import '../storage/token_storage.dart';
import 'api_error.dart';

class AuthInterceptor extends QueuedInterceptor {
  final TokenStorage _tokenStorage;

  AuthInterceptor({required TokenStorage tokenStorage})
      : _tokenStorage = tokenStorage;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // If Authorization header is already explicitly set, don't overwrite it
    if (!options.headers.containsKey('Authorization')) {
      final token = await _tokenStorage.getToken();
      if (token != null && token.trim().isNotEmpty) {
        options.headers['Authorization'] = 'Bearer ${token.trim()}';
      }
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Attach parsed ApiException to the DioException for downstream consumption
    final apiException = ApiException.fromDioException(err);
    final enrichedError = err.copyWith(error: apiException);
    handler.next(enrichedError);
  }
}
