import 'package:dio/dio.dart';
import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';

/// Raw Dio calls for /api/v1/acl.
/// Permission listing is per-user; role listing requires
/// institution.manage_admins (403 for regular users).
class AclApi {
  final Dio _dio;

  AclApi() : _dio = ApiClient().dio;

  /// GET /acl/users/{user_id}/permissions — returns an array of permission
  /// strings ("groups.create", etc.) the user has across their roles.
  Future<List<String>> permissionsFor(String userId) async {
    try {
      final r = await _dio.get('/acl/users/$userId/permissions');
      final data = r.data['data'];
      if (data is Map && data['permissions'] is List) {
        return (data['permissions'] as List).whereType<String>().toList();
      }
      if (data is List) {
        return data.whereType<String>().toList();
      }
      return const [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }
}
