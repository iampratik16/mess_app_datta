import 'package:dio/dio.dart';
import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../users/domain/user_models.dart';
import '../domain/group_models.dart';

/// Raw Dio calls for /api/v1/groups.
class GroupsApi {
  final Dio _dio;

  GroupsApi() : _dio = ApiClient().dio;

  Future<List<Group>> listGroups({int limit = 50}) async {
    try {
      final r = await _dio.get('/groups', queryParameters: {'limit': limit});
      final data = r.data['data'];
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map(Group.fromJson)
            .toList();
      }
      return const [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  Future<Group> createGroup({
    required String name,
    String mode = 'simple',
    String? description,
  }) async {
    try {
      final r = await _dio.post('/groups', data: {
        'name': name,
        'mode': mode,
        if (description != null) 'description': description,
      });
      return Group.fromJson(r.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// GET /groups/{id}/members — returns the member user profiles.
  Future<List<GroupMember>> listMembers(String groupId) async {
    try {
      final r = await _dio.get('/groups/$groupId/members');
      final data = r.data['data'];
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map(GroupMember.fromJson)
            .toList();
      }
      return const [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// POST /groups/{id}/members
  Future<void> addMember({
    required String groupId,
    required String userId,
    String role = 'member',
  }) async {
    try {
      await _dio.post('/groups/$groupId/members', data: {
        'user_id': userId,
        'role': role,
      });
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// DELETE /groups/{id}/members/{user_id}
  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {
    try {
      await _dio.delete('/groups/$groupId/members/$userId');
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }
}

/// A group membership row — wraps the nested user + role.
class GroupMember {
  final String userId;
  final String role; // 'owner' | 'admin' | 'member'
  final UserProfile? user;
  final DateTime? joinedAt;

  const GroupMember({
    required this.userId,
    required this.role,
    this.user,
    this.joinedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> j) {
    final userObj = j['user'] as Map<String, dynamic>?;
    return GroupMember(
      userId: (j['user_id'] as String?) ?? userObj?['id'] as String? ?? '',
      role: (j['role'] as String?) ?? 'member',
      user: userObj == null ? null : UserProfile.fromJson(userObj),
      joinedAt: j['joined_at'] == null
          ? null
          : DateTime.tryParse(j['joined_at'] as String),
    );
  }
}
