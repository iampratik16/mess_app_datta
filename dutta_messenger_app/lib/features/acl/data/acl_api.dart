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

  /// GET /acl/users/{user_id}/permissions — full payload (roles + perms).
  /// The same endpoint as [permissionsFor] but exposes the role IDs so admin
  /// UIs can render assignment toggles without a second round-trip.
  Future<UserAclSnapshot> snapshotFor(String userId) async {
    try {
      final r = await _dio.get('/acl/users/$userId/permissions');
      final data = r.data['data'];
      final perms = <String>[];
      final roleIds = <String>{};
      if (data is Map) {
        final pl = data['permissions'];
        if (pl is List) perms.addAll(pl.whereType<String>());
        final rl = data['roles'];
        if (rl is List) {
          for (final e in rl) {
            if (e is Map && e['id'] is String) {
              roleIds.add(e['id'] as String);
            }
          }
        }
      }
      return UserAclSnapshot(roleIds: roleIds, permissions: perms);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// GET /acl/roles — list roles in the institution. Admin-only; callers
  /// without `institution.manage_admins` get a 403 which surfaces as
  /// `ApiError.code == 'PERMISSION_DENIED'`.
  Future<List<AclRole>> listRoles() async {
    try {
      final r = await _dio.get('/acl/roles');
      final data = r.data['data'];
      final list = data is List
          ? data
          : (data is Map && data['roles'] is List ? data['roles'] as List : const []);
      return list
          .whereType<Map<String, dynamic>>()
          .map(AclRole.fromJson)
          .toList();
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// POST /acl/users/{user_id}/roles — assign a role. Admin-only.
  Future<void> assignRole({
    required String userId,
    required String roleId,
  }) async {
    try {
      await _dio.post(
        '/acl/users/$userId/roles',
        data: {'role_id': roleId},
      );
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// DELETE /acl/users/{user_id}/roles/{role_id} — revoke. Admin-only.
  Future<void> revokeRole({
    required String userId,
    required String roleId,
  }) async {
    try {
      await _dio.delete('/acl/users/$userId/roles/$roleId');
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }
}

/// Combined view: which roles a user has and what permissions they grant.
class UserAclSnapshot {
  const UserAclSnapshot({
    required this.roleIds,
    required this.permissions,
  });
  final Set<String> roleIds;
  final List<String> permissions;
}

/// One institution role. `isSystem` flags the immutable baseline roles
/// (owner/admin/member) — UI should not offer delete for these.
class AclRole {
  final String id;
  final String name;
  final String? description;
  final bool isSystem;

  const AclRole({
    required this.id,
    required this.name,
    this.description,
    this.isSystem = false,
  });

  factory AclRole.fromJson(Map<String, dynamic> j) => AclRole(
        id: j['id'] as String,
        name: j['name'] as String? ?? '(unnamed)',
        description: j['description'] as String?,
        isSystem: (j['is_system'] as bool?) ?? false,
      );
}
