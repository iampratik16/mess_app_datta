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

  /// GET /groups/{id} — single group (members-only; 404 for non-members).
  Future<Group> getGroup(String groupId) async {
    try {
      final r = await _dio.get('/groups/$groupId');
      return Group.fromJson(r.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// PATCH /groups/{id} — admin/owner only. Send only fields that change.
  Future<Group> updateGroup({
    required String groupId,
    String? name,
    String? description,
    String? avatarUrl,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    };
    try {
      final r = await _dio.patch('/groups/$groupId', data: body);
      return Group.fromJson(r.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// DELETE /groups/{id} — owner only. Soft-delete (sets is_archived).
  Future<void> archiveGroup(String groupId) async {
    try {
      await _dio.delete('/groups/$groupId');
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// GET /groups/{id}/topics — empty list for simple-mode groups.
  Future<List<Topic>> listTopics(String groupId) async {
    try {
      final r = await _dio.get('/groups/$groupId/topics');
      final data = r.data['data'];
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map(Topic.fromJson)
            .toList();
      }
      return const [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// POST /groups/{id}/topics — admin/owner, topics-mode groups only.
  Future<Topic> createTopic({
    required String groupId,
    required String name,
    String? description,
    String? iconEmoji,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      if (description != null) 'description': description,
      if (iconEmoji != null) 'icon_emoji': iconEmoji,
    };
    try {
      final r = await _dio.post('/groups/$groupId/topics', data: body);
      return Topic.fromJson(r.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// DELETE /groups/{id}/topics/{topic_id} — admin/owner, cannot delete "General".
  ///
  /// Returns the updated group and the remaining topic list so the
  /// caller can hard-replace local state without a follow-up GET
  /// (audit 3.1 option a). Older builds that returned 204 will throw
  /// at the cast — bump backend before deploying this client.
  Future<TopicDeleteResult> deleteTopic({
    required String groupId,
    required String topicId,
  }) async {
    try {
      final r = await _dio.delete('/groups/$groupId/topics/$topicId');
      final data = r.data['data'] as Map<String, dynamic>;
      final topics = (data['topics'] as List?) ?? const [];
      return TopicDeleteResult(
        group: Group.fromJson(data['group'] as Map<String, dynamic>),
        topics: topics
            .whereType<Map<String, dynamic>>()
            .map(Topic.fromJson)
            .toList(),
      );
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }
}

/// Server response for `DELETE /groups/{id}/topics/{topic_id}` —
/// the updated group plus the remaining topics.
class TopicDeleteResult {
  const TopicDeleteResult({required this.group, required this.topics});
  final Group group;
  final List<Topic> topics;
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
