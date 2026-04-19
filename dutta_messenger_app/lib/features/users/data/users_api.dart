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
}
