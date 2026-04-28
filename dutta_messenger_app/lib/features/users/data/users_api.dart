import 'package:dio/dio.dart';
import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../domain/user_models.dart';

/// Raw Dio calls for /api/v1/users.
class UsersApi {
  final Dio _dio;

  UsersApi() : _dio = ApiClient().dio;

  /// GET /users/me — returns the authenticated user.
  Future<UserProfile> me() async {
    try {
      final r = await _dio.get('/users/me');
      return UserProfile.fromJson(r.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// GET /users/{id} — returns a specific user profile.
  Future<UserProfile> getById(String id) async {
    try {
      final r = await _dio.get('/users/$id');
      return UserProfile.fromJson(r.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// GET /users/search?q=...
  /// Empty [query] returns an empty list; otherwise hits the backend (which
  /// accepts 1-char queries).
  Future<List<UserProfile>> search(String query, {int limit = 50}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final r = await _dio.get('/users/search',
          queryParameters: {'q': q, 'limit': limit});
      final data = r.data['data'];
      final items = data is Map && data['results'] is List
          ? data['results'] as List
          : (data is List ? data : const []);
      return items
          .whereType<Map<String, dynamic>>()
          .map(UserProfile.fromJson)
          .toList();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// GET /users/me/settings
  Future<UserSettings> settings() async {
    try {
      final r = await _dio.get('/users/me/settings');
      return UserSettings.fromJson(r.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// PATCH /users/me — update own profile. Only send fields that change.
  /// Backend accepts: full_name, avatar_url, bio, phone_number.
  /// `status` lives on the user table but is admin-only via this endpoint;
  /// passing it here is a no-op on the server (kept for client-side cache
  /// updates only — see UpdateProfileRequest in the backend).
  Future<UserProfile> updateMe({
    String? fullName,
    String? bio,
    String? status,
    String? avatarUrl,
    String? phoneNumber,
  }) async {
    final body = <String, dynamic>{
      if (fullName != null) 'full_name': fullName,
      if (bio != null) 'bio': bio,
      if (status != null) 'status': status,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (phoneNumber != null) 'phone_number': phoneNumber,
    };
    try {
      final r = await _dio.patch('/users/me', data: body);
      return UserProfile.fromJson(r.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// PATCH /users/me/settings — partial update of notification + theme prefs.
  Future<UserSettings> updateSettings({
    bool? notificationMessages,
    bool? notificationGroups,
    bool? notificationSound,
    String? theme,
    String? language,
  }) async {
    final body = <String, dynamic>{
      if (notificationMessages != null)
        'notification_messages': notificationMessages,
      if (notificationGroups != null)
        'notification_groups': notificationGroups,
      if (notificationSound != null) 'notification_sound': notificationSound,
      if (theme != null) 'theme': theme,
      if (language != null) 'language': language,
    };
    try {
      final r = await _dio.patch('/users/me/settings', data: body);
      return UserSettings.fromJson(r.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// GET /users/online?user_ids=a&user_ids=b — returns the subset of ids
  /// that are currently online. The backend takes repeated `user_ids`
  /// params (not comma-joined) and replies with a `{id: bool}` map; we
  /// flatten to the online-only subset for callers.
  Future<Set<String>> bulkOnlineStatus(Iterable<String> userIds) async {
    final ids = userIds.toSet().toList();
    if (ids.isEmpty) return const {};
    try {
      final r = await _dio.get(
        '/users/online',
        queryParameters: {'user_ids': ids},
        options: Options(
          listFormat: ListFormat.multi,
        ),
      );
      final data = r.data['data'];
      final online = data is Map ? data['online'] : null;
      if (online is Map) {
        return online.entries
            .where((e) => e.value == true)
            .map((e) => e.key as String)
            .toSet();
      }
      if (online is List) {
        return online.whereType<String>().toSet();
      }
      return const {};
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }
}
