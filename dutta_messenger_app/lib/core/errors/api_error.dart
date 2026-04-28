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

    // FastAPI default format. `detail` is usually a string but pydantic
    // validation responses ship it as a List[dict] / Map; coerce so the
    // `as String?` cast doesn't crash the app.
    //
    // Some endpoints double-wrap (HTTPException(detail=<dict>)) so we end
    // up with `{"detail": {"error": {"code": ..., "message": ...}}}` —
    // peel the inner error envelope so the user sees a clean message
    // instead of the whole map's toString.
    if (data is Map && data.containsKey('detail')) {
      final detail = data['detail'];
      if (detail is Map && detail['error'] is Map) {
        final err = detail['error'] as Map;
        return ApiError(
          code: err['code']?.toString() ?? _statusToCode(statusCode),
          message: err['message']?.toString() ?? 'An error occurred.',
          details: err['details'] is Map<String, dynamic>
              ? err['details'] as Map<String, dynamic>
              : null,
          statusCode: statusCode,
        );
      }
      final String message;
      if (detail is String) {
        message = detail;
      } else if (detail == null) {
        message = 'An error occurred.';
      } else if (detail is Map && detail['message'] is String) {
        message = detail['message'] as String;
      } else if (detail is List && detail.isNotEmpty) {
        // Pydantic validation: list of {loc, msg, type}
        final first = detail.first;
        message = first is Map && first['msg'] is String
            ? first['msg'] as String
            : detail.toString();
      } else {
        message = detail.toString();
      }
      return ApiError(
        code: _statusToCode(statusCode),
        message: message,
        details: detail is Map<String, dynamic> ? detail : null,
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
