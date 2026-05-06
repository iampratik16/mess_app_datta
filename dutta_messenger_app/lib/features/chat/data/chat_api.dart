import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../domain/chat_models.dart';

/// Raw Dio calls for /api/v1/chat.
class ChatApi {
  static const _uuid = Uuid();
  final Dio _dio;

  ChatApi() : _dio = ApiClient().dio;

  /// POST /chat/conversations/open-group
  ///
  /// For topics-mode groups, pass [topicId] — each topic is a distinct
  /// conversation. Simple-mode groups omit it.
  Future<Conversation> openGroupConversation(
    String groupId, {
    String? topicId,
  }) async {
    try {
      final r = await _dio.post(
        '/chat/conversations/open-group',
        data: {
          'group_id': groupId,
          if (topicId != null) 'topic_id': topicId,
        },
      );
      return Conversation.fromJson(r.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// GET /chat/conversations/{id}/messages — newest-first.
  ///
  /// Pass [beforeId] (the id of the oldest message currently in local
  /// state) to page backwards into history. The query param the server
  /// expects is `before_id`; older builds of this client passed `cursor`
  /// which the server silently ignored, so paging never actually worked.
  Future<List<Message>> listMessages(
    String conversationId, {
    int limit = 50,
    String? beforeId,
  }) async {
    try {
      final r = await _dio.get(
        '/chat/conversations/$conversationId/messages',
        queryParameters: {
          'limit': limit,
          if (beforeId != null) 'before_id': beforeId,
        },
      );
      final data = r.data['data'];
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map(Message.fromJson)
            .toList();
      }
      return const [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// POST /chat/conversations/{id}/messages — sends a text message.
  /// Adds a `client_message_id` and `Idempotency-Key` for safe retries.
  ///
  /// `mediaIds` is set when the message re-shares existing vault items
  /// (Media Vault picker flow). The server uses it as a privacy guard:
  /// every id must be owned by the sender or the request is rejected
  /// with 403. Fresh-upload paths can also pass the just-completed
  /// media id here for consistency.
  Future<Message> sendMessage({
    required String conversationId,
    required String content,
    List<String>? mediaIds,
  }) async {
    try {
      final idempotencyKey = _uuid.v4();
      final r = await _dio.post(
        '/chat/conversations/$conversationId/messages',
        data: {
          'content': content,
          'client_message_id': _uuid.v4(),
          if (mediaIds != null && mediaIds.isNotEmpty) 'media_ids': mediaIds,
        },
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      return Message.fromJson(r.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// PATCH /chat/messages/{id} — edit own message. Server returns the
  /// updated row; other clients currently see the edit on next refresh
  /// (no WS broadcast for edits yet).
  Future<Message> editMessage({
    required String messageId,
    required String content,
  }) async {
    try {
      final r = await _dio.patch(
        '/chat/messages/$messageId',
        data: {'content': content},
      );
      return Message.fromJson(r.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// POST /chat/conversations/{id}/read
  Future<void> markRead({
    required String conversationId,
    required String lastReadMessageId,
  }) async {
    try {
      await _dio.post(
        '/chat/conversations/$conversationId/read',
        data: {'last_read_message_id': lastReadMessageId},
      );
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// DELETE /chat/messages/{id}
  Future<void> deleteMessage(String messageId) async {
    try {
      await _dio.delete('/chat/messages/$messageId');
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }
}
