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

  /// True when the failure is an upstream outage rather than anything the
  /// user did — a gateway error from us, or a provider failure the backend
  /// wrapped and passed through.
  bool get isUpstreamUnavailable {
    if (statusCode == 502 || statusCode == 503 || statusCode == 504) return true;
    final m = message.toLowerCase();
    return m.contains('service temporarily unavailable') ||
        m.contains('bad gateway') ||
        m.contains('gateway timeout') ||
        m.contains('(status: 502)') ||
        m.contains('(status: 503)') ||
        m.contains('(status: 504)');
  }

  /// Copy that is safe to put in front of a user.
  ///
  /// Provider failures reach us with the provider's own wording, and when
  /// their gateway is down that wording is an entire HTML error page. Nothing
  /// off the wire is rendered verbatim: anything that looks like markup, is
  /// empty, or is too long to be a sentence becomes a generic message.
  String get userMessage {
    if (isUpstreamUnavailable) {
      return 'The payment network is temporarily unavailable. '
          'Please try again in a moment.';
    }
    final clean = message.trim();
    if (clean.isEmpty || _looksLikeMarkup(clean) || clean.length > 160) {
      return 'Something went wrong. Please try again.';
    }
    return clean;
  }

  static bool _looksLikeMarkup(String value) =>
      RegExp(r'<\s*/?\s*[a-zA-Z]').hasMatch(value);

  @override
  String toString() => 'ApiException(code: $code, statusCode: $statusCode, message: $message)';
}

/// User-facing copy for any thrown object, so no screen has to render
/// `toString()` and risk leaking an exception wrapper or a provider's HTML.
String friendlyErrorMessage(Object error) {
  if (error is ApiException) return error.userMessage;
  final clean = error
      .toString()
      .replaceFirst('Exception: ', '')
      .trim();
  if (clean.isEmpty ||
      clean.length > 160 ||
      RegExp(r'<\s*/?\s*[a-zA-Z]').hasMatch(clean)) {
    return 'Something went wrong. Please try again.';
  }
  return clean;
}
