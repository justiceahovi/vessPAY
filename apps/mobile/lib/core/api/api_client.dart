import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'api_error.dart';
import 'auth_interceptor.dart';

class ApiClient {
  final Dio _dio;
  final TokenStorage _tokenStorage;

  ApiClient({
    Dio? dio,
    TokenStorage? tokenStorage,
    String? baseUrl,
  })  : _tokenStorage = tokenStorage ?? SecureTokenStorage(),
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ?? AppConfig.baseUrl,
                connectTimeout: AppConfig.connectTimeout,
                receiveTimeout: AppConfig.receiveTimeout,
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            ) {
    // Add AuthInterceptor to Dio instance
    _dio.interceptors.add(AuthInterceptor(tokenStorage: _tokenStorage));
  }

  Dio get dio => _dio;
  TokenStorage get tokenStorage => _tokenStorage;

  /// Typed GET request wrapper
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    T Function(dynamic data)? fromJson,
  }) async {
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
      if (fromJson != null) {
        return fromJson(response.data);
      }
      return response.data as T;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        code: 'CLIENT_ERROR',
        message: e.toString(),
      );
    }
  }

  /// Typed POST request wrapper
  Future<T> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    T Function(dynamic data)? fromJson,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
      if (fromJson != null) {
        return fromJson(response.data);
      }
      return response.data as T;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        code: 'CLIENT_ERROR',
        message: e.toString(),
      );
    }
  }

  /// Typed PUT request wrapper
  Future<T> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    T Function(dynamic data)? fromJson,
  }) async {
    try {
      final response = await _dio.put(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
      if (fromJson != null) {
        return fromJson(response.data);
      }
      return response.data as T;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        code: 'CLIENT_ERROR',
        message: e.toString(),
      );
    }
  }

  /// Typed DELETE request wrapper
  Future<T> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    T Function(dynamic data)? fromJson,
  }) async {
    try {
      final response = await _dio.delete(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
      if (fromJson != null) {
        return fromJson(response.data);
      }
      return response.data as T;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        code: 'CLIENT_ERROR',
        message: e.toString(),
      );
    }
  }

  /// Token management helpers
  Future<void> saveToken(String token) => _tokenStorage.saveToken(token);
  Future<String?> getToken() => _tokenStorage.getToken();
  Future<void> clearToken() => _tokenStorage.deleteToken();
  Future<bool> isAuthenticated() => _tokenStorage.hasToken();

  ApiException _handleDioError(DioException e) {
    if (e.error is ApiException) {
      return e.error as ApiException;
    }
    return ApiException.fromDioException(e);
  }
}
