import 'package:dio/dio.dart';

/// Exception thrown for any VessPay API failure, parsing the standard error shape:
/// { "error": { "code": "STRING_CODE", "message": "human readable" } }
class ApiException implements Exception {
  final String code;
  final String message;
  final int? statusCode;
  final dynamic rawResponse;

  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.rawResponse,
  });

  factory ApiException.fromDioException(DioException error) {
    final response = error.response;
    final statusCode = response?.statusCode;
    final data = response?.data;

    // 1. Check for standard backend error shape: { "error": { "code": "...", "message": "..." } }
    if (data is Map<String, dynamic>) {
      final errorObj = data['error'];
      if (errorObj is Map) {
        return ApiException(
          code: errorObj['code']?.toString() ?? 'UNKNOWN_ERROR',
          message: errorObj['message']?.toString() ?? 'An error occurred',
          statusCode: statusCode,
          rawResponse: data,
        );
      } else if (errorObj is String) {
        return ApiException(
          code: 'API_ERROR',
          message: errorObj,
          statusCode: statusCode,
          rawResponse: data,
        );
      }

      if (data.containsKey('message')) {
        return ApiException(
          code: 'API_ERROR',
          message: data['message']?.toString() ?? 'An error occurred',
          statusCode: statusCode,
          rawResponse: data,
        );
      }
    }

    // 2. Handle connection / network / timeout errors
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          code: 'TIMEOUT',
          message: 'Connection timed out. Please check your connection and try again.',
          statusCode: statusCode,
          rawResponse: data,
        );

      case DioExceptionType.connectionError:
        return ApiException(
          code: 'NETWORK_ERROR',
          message: 'Unable to connect to the VessPay server. Please check your network.',
          statusCode: statusCode,
          rawResponse: data,
        );

      case DioExceptionType.cancel:
        return ApiException(
          code: 'REQUEST_CANCELLED',
          message: 'The request was cancelled.',
          statusCode: statusCode,
          rawResponse: data,
        );

      case DioExceptionType.badResponse:
        final defaultMsg = switch (statusCode) {
          400 => 'Bad request',
          401 => 'Unauthorized',
          403 => 'Forbidden',
          404 => 'Resource not found',
          409 => 'Conflict',
          500 => 'Internal server error',
          _ => 'Server returned an error ($statusCode)',
        };
        return ApiException(
          code: statusCode != null ? 'HTTP_$statusCode' : 'BAD_RESPONSE',
          message: defaultMsg,
          statusCode: statusCode,
          rawResponse: data,
        );

      default:
        return ApiException(
          code: 'CLIENT_ERROR',
          message: error.message ?? 'An unexpected error occurred.',
          statusCode: statusCode,
          rawResponse: data,
        );
    }
  }

  @override
  String toString() => 'ApiException(code: $code, statusCode: $statusCode, message: $message)';
}
