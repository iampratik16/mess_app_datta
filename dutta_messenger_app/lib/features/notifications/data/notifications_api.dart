import 'package:dio/dio.dart';
import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';

/// Raw Dio calls for /api/v1/notifications.
/// The backend currently exposes unread-count, mark-read, and FCM token
/// register/delete. There is no list-notifications endpoint yet.
class NotificationsApi {
  final Dio _dio;

  NotificationsApi() : _dio = ApiClient().dio;

  /// GET /notifications/unread-count
  Future<int> unreadCount() async {
    try {
      final r = await _dio.get('/notifications/unread-count');
      return (r.data['data']?['unread'] as int?) ?? 0;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// POST /notifications/mark-read — marks all unread when no ids are given.
  Future<int> markAllRead() async {
    try {
      final r = await _dio.post(
        '/notifications/mark-read',
        data: {'notification_ids': []},
      );
      return (r.data['data']?['marked'] as int?) ?? 0;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// POST /notifications/tokens — register (or reactivate) a device FCM
  /// token. Returns the server-assigned token row id so the caller can
  /// later DELETE it via [revokeFcmToken].
  ///
  /// Backend accepts `device_type` ∈ ios|android|web (NOT `platform`).
  Future<RegisterFcmTokenResult> registerFcmToken({
    required String token,
    String? deviceName,
    String? deviceType,
  }) async {
    try {
      final r = await _dio.post('/notifications/tokens', data: {
        'token': token,
        if (deviceName != null) 'device_name': deviceName,
        if (deviceType != null) 'device_type': deviceType,
      });
      final data = r.data['data'] as Map<String, dynamic>?;
      final tokenObj = data?['token'] as Map<String, dynamic>?;
      return RegisterFcmTokenResult(
        tokenId: tokenObj?['id']?.toString() ?? '',
        reused: (data?['reused'] as bool?) ?? false,
      );
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// DELETE /notifications/tokens/{id} — soft-deactivate a device token.
  Future<void> revokeFcmToken(String tokenId) async {
    try {
      await _dio.delete('/notifications/tokens/$tokenId');
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }
}

/// Result of a token registration.
class RegisterFcmTokenResult {
  const RegisterFcmTokenResult({required this.tokenId, required this.reused});
  final String tokenId;
  final bool reused;
}
