import 'package:dio/dio.dart';

/// Normalised error type raised by [ApiClient] so the UI layer never has to
/// inspect raw Dio errors. Mirrors the backend error envelope from API.md:
///
/// ```json
/// { "success": false, "error": { "code": "VALIDATION_ERROR", "message": "...", "details": [] } }
/// ```
class ApiException implements Exception {
  ApiException({
    required this.message,
    required this.code,
    this.statusCode,
    this.details = const [],
  });

  /// Human-readable message safe to surface to the user.
  final String message;

  /// Backend error code, e.g. `VALIDATION_ERROR`, `UNAUTHORIZED`, `NOT_FOUND`.
  final String code;

  /// HTTP status code when available.
  final int? statusCode;

  /// Optional validation detail list from the backend.
  final List<dynamic> details;

  bool get isUnauthorized => code == 'UNAUTHORIZED' || statusCode == 401;
  bool get isForbidden => code == 'FORBIDDEN' || statusCode == 403;
  bool get isNotFound => code == 'NOT_FOUND' || statusCode == 404;
  bool get isConflict => code == 'CONFLICT' || statusCode == 409;
  bool get isValidation => code == 'VALIDATION_ERROR' || statusCode == 400;
  bool get isPaymentError => code == 'PAYMENT_ERROR' || statusCode == 402;
  bool get isRateLimited => code == 'RATE_LIMITED' || statusCode == 429;
  bool get isNetwork => code == 'NETWORK_ERROR';

  /// Build an [ApiException] from a Dio failure, reading the backend envelope
  /// when present and falling back to sensible transport-level messages.
  factory ApiException.fromDio(DioException error) {
    final response = error.response;
    final data = response?.data;

    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException(
        message: (err['message'] as String?)?.trim().isNotEmpty == true
            ? err['message'] as String
            : 'Something went wrong. Please try again.',
        code: err['code'] as String? ?? 'INTERNAL',
        statusCode: response?.statusCode,
        details: err['details'] is List ? err['details'] as List : const [],
      );
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          message: 'The connection timed out. Please check your network.',
          code: 'NETWORK_ERROR',
          statusCode: response?.statusCode,
        );
      case DioExceptionType.connectionError:
        return ApiException(
          message: 'Unable to reach the server. Please check your connection.',
          code: 'NETWORK_ERROR',
        );
      case DioExceptionType.badResponse:
        return ApiException(
          message: 'Request failed (${response?.statusCode}).',
          code: 'INTERNAL',
          statusCode: response?.statusCode,
        );
      case DioExceptionType.cancel:
        return ApiException(message: 'Request cancelled.', code: 'CANCELLED');
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return ApiException(
          message: 'Something went wrong. Please try again.',
          code: 'INTERNAL',
          statusCode: response?.statusCode,
        );
    }
  }

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}
