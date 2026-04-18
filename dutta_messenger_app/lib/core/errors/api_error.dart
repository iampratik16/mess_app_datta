import 'package:dio/dio.dart';

/// Parses the backend's standard error envelope.
/// Backend format: {"error": {"code": "...", "message": "...", "details": {...}}}
class ApiError implements Exception {
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  final int? statusCode;

  const ApiError({
    required this.code,
    required this.message,
    this.details,
    this.statusCode,
  });

  factory ApiError.fromDioException(DioException e) {
    final statusCode = e.response?.statusCode;
    final data = e.response?.data;

    // Standard backend error envelope
    if (data is Map && data.containsKey('error')) {
      final err = data['error'] as Map<String, dynamic>;
      return ApiError(
        code: err['code'] as String? ?? 'UNKNOWN_ERROR',
        message: err['message'] as String? ?? 'An error occurred.',
        details: err['details'] as Map<String, dynamic>?,
        statusCode: statusCode,
      );
    }

    // FastAPI default format (Gap B — some endpoints still use this)
    if (data is Map && data.containsKey('detail')) {
      return ApiError(
        code: _statusToCode(statusCode),
        message: data['detail'] as String? ?? 'An error occurred.',
        statusCode: statusCode,
      );
    }

    // Network / timeout errors
    return ApiError(
      code: 'NETWORK_ERROR',
      message: e.message ?? 'Network error occurred.',
      statusCode: statusCode,
    );
  }

  static String _statusToCode(int? status) => switch (status) {
        400 => 'VALIDATION_ERROR',
        401 => 'UNAUTHORIZED',
        403 => 'FORBIDDEN',
        404 => 'NOT_FOUND',
        409 => 'CONFLICT',
        429 => 'RATE_LIMIT_EXCEEDED',
        _ => 'INTERNAL_ERROR',
      };

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => 'ApiError($code): $message';
}
