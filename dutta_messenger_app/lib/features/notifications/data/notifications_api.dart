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

  /// POST /notifications/tokens — register a device FCM token.
  Future<void> registerFcmToken({
    required String token,
    String platform = 'ios',
  }) async {
    try {
      await _dio.post('/notifications/tokens', data: {
        'token': token,
        'platform': platform,
      });
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }
}
